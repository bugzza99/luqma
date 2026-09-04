-- A promotion on the `push` channel had no sender, and nobody could turn one off.
--
-- Everything around it was built: the channel is in the enum, the admin approves one,
-- `push_slot_available` rations them to a few a week, and `push_outbox.channel` has
-- allowed 'marketing' since the day the outbox existed — with a comment saying operational
-- alerts must not be silenced by the switch somebody flipped for marketing. What was
-- missing was the switch and the fan-out. So an approved push promotion went live, sat
-- there for its whole run, and reached nobody; and a customer who found the ads
-- intrusive had no way to stop them, which is the half that is not merely a missing
-- feature.

-- ---------------------------------------------------------------- the switch

-- Default true, because a promotion nobody has opted into is a channel nobody would ever
-- pay for, and this is the revenue the merchants are being sold. What makes that
-- defensible is that it is one switch on حسابي, it is honest about what it stops, and it
-- cannot touch the three operational messages — those go out on `orders` regardless.
alter table public.users
  add column marketing_push boolean not null default true;

comment on column public.users.marketing_push is
  'Marketing notifications only. Order status is never gated on this.';

-- The customer writes it themselves, so the guard has to let it through. Absent here,
-- flipping the switch fails with "column not yours to change on users" and the screen
-- shows an error for an action that is entirely the customer's to take.
drop trigger users_guard_columns on public.users;
create trigger users_guard_columns before update on public.users for each row
  execute function public.guard_columns(
    '{name,phone,fcm_tokens,default_address_id,marketing_push}');

-- ---------------------------------------------------------------- sent, once

-- A campaign runs for days; the notification is one moment inside it. Without this the
-- cron pass below would find the same live promotion every minute and send it again
-- every minute, which is the single fastest way to make a whole city turn the app's
-- notifications off.
alter table public.promotions
  add column pushed_at timestamptz;

comment on column public.promotions.pushed_at is
  'When the one marketing notification for this campaign was queued. Null means never.';

-- ---------------------------------------------------------------- the fan-out

-- Queues one notification per opted-in customer for every push promotion that has come
-- live and not yet been sent.
--
-- Rows in `push_outbox`, not calls to FCM: the existing drain owns the sending, the
-- lease, the retries and the pruning of dead tokens, and none of that is worth a second
-- implementation. This function only decides who and what.
create or replace function public.send_promotion_push()
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_promotion record;
  v_limit     integer;
  v_queued    integer := 0;
  v_rows      integer;
begin
  -- The cap is the city's, and it is read here rather than taken as an argument for the
  -- same reason the audit gave for `record_subscription_payment`: a limit the caller
  -- supplies is a limit the caller can raise.
  select coalesce((value #>> '{}')::integer, 0) into v_limit
    from public.config where key = 'marketing_push_per_week';
  v_limit := coalesce(v_limit, 0);

  for v_promotion in
    select id, city_id, merchant_id, title, body, zone_ids
      from public.promotions
     where channel = 'push'
       and status = 'approved'
       and pushed_at is null
       and start_at <= now()
       and end_at > now()
     -- Oldest first, so a backlog is worked through in the order the admin approved it
     -- rather than in whatever order the planner returns.
     order by start_at
     for update skip locked
  loop
    -- Re-checked per promotion rather than once: each send consumes a slot, so two
    -- approved campaigns going live in the same minute must not both get through a cap
    -- of one.
    if not public.push_slot_available(v_promotion.city_id, v_limit) then
      exit;
    end if;

    insert into public.push_outbox (uid, title, body, data, channel)
    select u.id,
           v_promotion.title,
           v_promotion.body,
           pg_catalog.jsonb_build_object(
             'kind', 'promotion',
             'promotionId', v_promotion.id::text,
             'merchantId', v_promotion.merchant_id::text
           ),
           'marketing'
      from public.users u
     where u.marketing_push
       and not u.is_blocked
       -- The city is the floor, and an empty `zone_ids` narrows to nothing *within* it.
       --
       -- "The whole city" is what the column comment on `promotions` has always said,
       -- and a merchant who did not narrow their campaign meant everybody in their own
       -- town rather than everybody anywhere. Reading the empty array as "no filter at
       -- all" sends an Edku restaurant's offer to every customer in every city this
       -- product ever serves — which is invisible during an Edku-only launch and
       -- becomes a mailing to strangers on the day a second city opens.
       and exists (
         select 1
           from public.addresses a
           join public.zones z on z.id = a.zone_id
          where a.user_id = u.id
            and z.city_id = v_promotion.city_id
            and (
              v_promotion.zone_ids = '{}'::uuid[]
              or a.zone_id = any(v_promotion.zone_ids)
            )
       );

    get diagnostics v_rows = row_count;
    v_queued := v_queued + v_rows;

    -- Stamped whether or not anybody was queued. A campaign that reached nobody has
    -- still had its turn; leaving it null would make it a candidate again on the next
    -- pass, for ever.
    update public.promotions set pushed_at = now() where id = v_promotion.id;
  end loop;

  return v_queued;
end;
$fn$;

-- Nobody calls this from a phone. It is the cron job's, and the service role's for
-- anybody who has to run it by hand.
revoke all on function public.send_promotion_push() from public, anon, authenticated;
grant execute on function public.send_promotion_push() to service_role;

-- Guarded by availability, the same way `20260824130000_scheduled_jobs.sql` is: PGlite
-- runs the local migration suite and has no pg_cron, and a bare `create extension` there
-- stops every local test before it reaches a constraint.
do $body$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;

    -- Every five minutes rather than every minute. A marketing notification is not an
    -- order: nothing is waiting on it, and the drain it feeds already runs every minute,
    -- so the longest a campaign waits from going live to arriving is five minutes plus
    -- one.
    perform cron.unschedule('luqma-promotion-push')
      where exists (select 1 from cron.job where jobname = 'luqma-promotion-push');
    perform cron.schedule('luqma-promotion-push', '*/5 * * * *',
      'select public.send_promotion_push()');
  end if;
end;
$body$;
