-- Phase 9: one current truth for a merchant's plan.
--
-- The nightly billing pass used to answer "has this merchant stopped paying" by reading
-- every subscription term and taking the newest — correct, but unbounded, and it reads
-- the whole table every night for as long as the platform lives. The fix decided in the
-- audit: put the term's end date on the merchant itself. Then the pass is a range query
-- over one small table, and a merchant who has paid has their end date *moved*, which is
-- the same act as paying rather than a second fact that can drift away from the first.
--
-- `subscriptions` goes back to being receipts — history somebody asks about, not state
-- every night rereads.

-- ---------------------------------------------------------------- the column

alter table public.merchants
  add column if not exists plan_expires_at timestamptz;

comment on column public.merchants.plan_expires_at is
  'When the merchant''s current paid term ends. Written when a payment is recorded, '
  'cleared by the nightly pass when it lapses. One current truth; subscriptions are '
  'receipts.';

-- Backfill from the receipts already on file: the newest term wins, whatever order the
-- rows arrived in.
update public.merchants m
   set plan_expires_at = s.newest_end
  from (
    select merchant_id, max(expires_at) as newest_end
      from public.subscriptions
     group by merchant_id
  ) s
 where s.merchant_id = m.id;

-- ---------------------------------------------------------------- the nightly pass

-- Now bounded: it touches only merchants whose own row says "expired", and clearing the
-- field removes them from tomorrow night's query by itself. No group-by, no full scan of
-- receipts, no chance of downgrading a merchant who paid this morning — their end date
-- moved with the payment.
create or replace function public.downgrade_expired_subscriptions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_downgraded integer := 0;
begin
  perform set_config('app.server_mode', 'on', true);

  with moved as (
    update public.merchants m
       set plan_id = null,
           plan_expires_at = null,
           updated_at = now()
     where m.plan_expires_at is not null
       and m.plan_expires_at < now()
    returning 1
  )
  select count(*) into v_downgraded from moved;

  return v_downgraded;
end;
$$;

revoke execute on function public.downgrade_expired_subscriptions()
  from public, anon, authenticated;
grant execute on function public.downgrade_expired_subscriptions() to service_role;

-- ---------------------------------------------------------------- recording a payment

-- Same function S1 rebuilt (admin-only, self-auditing); the one change is that the term's
-- end lands on the merchant as well, so the receipt and the truth are written in the same
-- statement. A payment recorded without this would leave a merchant whose plan says paid
-- and whose expiry says nothing — the drift the column exists to end.
create or replace function public.record_subscription_payment(
  p_merchant_id uuid,
  p_plan_id     text,
  p_amount      integer,
  p_months      integer,
  p_recorded_by uuid default null
)
returns jsonb
language plpgsql
as $fn$
declare
  v_actor   uuid := auth.uid();
  latest    public.subscriptions;
  starts_at timestamptz;
  term      public.subscriptions;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin records a payment' using errcode = '42501';
  end if;

  perform set_config('app.server_mode', 'on', true);

  if p_months < 1 or p_amount < 0 then
    raise exception 'months must be positive and amount non-negative'
      using errcode = 'check_violation';
  end if;

  select * into latest
    from public.subscriptions
   where merchant_id = p_merchant_id
   order by expires_at desc
   limit 1;

  if found and latest.expires_at > now() then
    starts_at := latest.expires_at;
  else
    starts_at := now();
  end if;

  insert into public.subscriptions
    (merchant_id, plan_id, amount, started_at, expires_at, recorded_by)
  values
    (p_merchant_id, p_plan_id, p_amount, starts_at,
     starts_at + make_interval(days => 30 * p_months), v_actor)
  returning * into term;

  -- The subscription is the receipt; these two are the state every feature check reads.
  -- Written together or not at all — they are in one transaction here.
  update public.merchants
     set plan_id = p_plan_id,
         plan_expires_at = term.expires_at
   where id = p_merchant_id;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values ('recordSubscriptionPayment', v_actor, p_merchant_id,
          jsonb_build_object('planId', p_plan_id, 'amount', p_amount,
                             'months', p_months));

  return to_jsonb(term);
end;
$fn$;

revoke execute on function public.record_subscription_payment(uuid, text, integer, integer, uuid)
  from public, anon;
grant execute on function public.record_subscription_payment(uuid, text, integer, integer, uuid)
  to authenticated, service_role;
