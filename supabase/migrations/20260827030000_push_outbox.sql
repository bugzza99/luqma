-- Telling the merchant an order arrived.
--
-- The one notification the business genuinely depends on: an order lands, the merchant's
-- phone is in their pocket with the app closed, and if nothing rings, nothing happens.
-- The Android side of it — the `orders_critical` channel at max importance and the
-- looping alarm in `new_order.wav` — has been built since Phase 4 and has been waiting
-- for a message ever since.
--
-- **The order writes a row here, and something else sends it.** Not `pg_net` from inside
-- the trigger: that puts an HTTP call in the same transaction as the order, so a slow or
-- broken FCM makes `place_order` slow or broken, and a customer loses an order because
-- Google had a bad minute. An order that succeeds and a notification that arrives late
-- is a bad evening; an order that fails is money gone.
--
-- And not the client calling an Edge Function after placing: the customer with the weak
-- connection is exactly the one whose call would not arrive, and the merchant would
-- never learn about their order at all.

create table push_outbox (
  id           uuid primary key default gen_random_uuid(),
  -- Who to wake. Tokens are looked up at send time rather than copied in here: a token
  -- captured now may be dead by the time this row is drained, and the account's current
  -- tokens are the only ones worth trying.
  uid          uuid not null references auth.users on delete cascade,
  title        text not null,
  body         text not null,
  -- What the app does when it is tapped: which screen, which order.
  data         jsonb not null default '{}'::jsonb,
  -- The Android channel. Operational alerts must not be silenced by the switch somebody
  -- flipped for marketing, and the channel is what the OS separates them by.
  channel      text not null default 'orders_critical'
                 check (channel in ('orders_critical', 'orders', 'marketing')),
  created_at   timestamptz not null default now(),
  sent_at      timestamptz,
  attempts     integer not null default 0,
  last_error   text
);

-- The drain's query: unsent, oldest first, and not one that has already failed its way
-- out of usefulness. Partial, so it stays small however many notifications have been
-- sent — the table is a log as well as a queue.
create index push_outbox_pending_idx
  on push_outbox (created_at)
  where sent_at is null and attempts < 5;

alter table push_outbox enable row level security;

-- No client reads or writes this, ever. It is written by a trigger and drained by a
-- service-role function, both of which bypass RLS; leaving it with no policy at all is
-- what says so.
revoke all on push_outbox from anon, authenticated;

-- ---------------------------------------------------------------- what fills it

-- An instant order arriving at a shop.
--
-- Pre-orders are deliberately not here: a daily meal is collected in a window on a named
-- day, has no accept deadline, and waking a cook at midnight for a meal they publish
-- themselves is the fastest way to have them turn notifications off — and then they miss
-- the ones that matter.
create or replace function public.queue_new_order_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_merchant text;
begin
  if new.type <> 'instant' then
    return new;
  end if;

  -- The owner, not the courier. They share a merchant_id, and only one of them decides
  -- whether the shop takes this order.
  select s.uid into v_owner
    from public.staff s
   where s.merchant_id = new.merchant_id
     and s.role = 'owner'
     and s.is_active
   limit 1;

  if v_owner is null then
    return new;
  end if;

  select m.name into v_merchant from public.merchants m where m.id = new.merchant_id;

  insert into public.push_outbox (uid, title, body, data, channel)
  values (
    v_owner,
    'أوردر جديد',
    'أوردر جديد في ' || coalesce(v_merchant, 'مطعمك'),
    jsonb_build_object('kind', 'newOrder', 'orderId', new.id::text),
    'orders_critical'
  );

  return new;
end;
$$;

create trigger orders_queue_push
  after insert on orders
  for each row execute function public.queue_new_order_push();

-- ---------------------------------------------------------------- what empties it

-- Claims a batch and hands it to whoever is sending.
--
-- `for update skip locked` so two drains running at once cannot take the same row and
-- send one merchant the same alarm twice — which, on a channel whose whole point is that
-- it is loud, is worse than it sounds.
create or replace function public.claim_push_batch(p_limit integer default 20)
returns table (
  id uuid,
  tokens text[],
  title text,
  body text,
  data jsonb,
  channel text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  with claimed as (
    select o.id
      from public.push_outbox o
     where o.sent_at is null and o.attempts < 5
     order by o.created_at
     limit p_limit
     for update skip locked
  ), bumped as (
    update public.push_outbox o
       set attempts = o.attempts + 1
      from claimed
     where o.id = claimed.id
    returning o.*
  )
  select b.id, u.fcm_tokens, b.title, b.body, b.data, b.channel
    from bumped b
    join public.users u on u.id = b.uid;
end;
$$;

-- Marks one row done, or records why it is not.
create or replace function public.settle_push(
  p_id uuid,
  p_error text default null,
  p_dead_tokens text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
begin
  if p_error is null then
    update public.push_outbox set sent_at = now(), last_error = null where id = p_id;
  else
    update public.push_outbox set last_error = p_error where id = p_id;
  end if;

  -- FCM answers with the tokens it no longer recognises, and this is the only place that
  -- knows. Without pruning them, a merchant who has changed phones twice accumulates
  -- dead tokens for ever, every send starts failing against them, and the logs fill with
  -- errors that look like a broken integration rather than an old handset.
  if array_length(p_dead_tokens, 1) > 0 then
    select uid into v_uid from public.push_outbox where id = p_id;
    update public.users
       set fcm_tokens = array(
             select t from unnest(fcm_tokens) t where t <> all(p_dead_tokens)
           )
     where id = v_uid;
  end if;
end;
$$;

revoke all on function public.claim_push_batch(integer) from public, anon, authenticated;
revoke all on function public.settle_push(uuid, text, text[])
  from public, anon, authenticated;

-- ---------------------------------------------------------------- the drain's schedule

-- Every minute, guarded by availability like every other job here — PGlite runs the
-- local migration suite and has no pg_cron.
--
-- The URL and the secret are settings rather than literals: the same migration has to
-- apply to the local stack and to the hosted project, which are different hosts. Until
-- they are set the job is scheduled and does nothing, which is the right failure — a
-- notification that has not been configured yet, rather than a migration that refuses to
-- run.
do $$
declare v_cron boolean;
begin
  select count(*) > 0 into v_cron from pg_available_extensions where name = 'pg_cron';
  if not v_cron then return; end if;

  create extension if not exists pg_cron;
  create extension if not exists pg_net;

  perform cron.unschedule('luqma-send-push')
    where exists (select 1 from cron.job where jobname = 'luqma-send-push');

  perform cron.schedule('luqma-send-push', '* * * * *', $c$
    select net.http_post(
      url := current_setting('app.functions_url', true) || '/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', current_setting('app.cron_secret', true)
      ),
      body := '{}'::jsonb
    )
    where current_setting('app.functions_url', true) is not null
      and current_setting('app.cron_secret', true) is not null
  $c$);
end;
$$;
