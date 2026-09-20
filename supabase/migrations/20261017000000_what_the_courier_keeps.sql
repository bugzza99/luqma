-- What the courier keeps, what the shop gets, and what the platform is owed.
--
-- The second half of the platform-courier feature, and the half a structural review
-- parked on 2026-09-20. The documents shipped first (20261016000000); this is the money.
--
-- The owner's decisions, 2026-09-20:
--   * a platform courier **keeps the delivery fee** and pays the platform a percentage of
--     it — `courier_commission_percent`, 10 by default — collected in cash weekly, the
--     same arrangement every shop already has;
--   * a shop's own courier hands the shop everything and what they are paid is between
--     them. The app does not invent a wage it has no column for;
--   * a courier's debt survives them leaving.
--
-- ------------------------------------------------------------------ why this is a rewrite
--
-- The parked `apply_courier_settlement` asked, at settlement time, whether the courier was
-- eligible — an active `staff` row, the platform row in `courier_merchants` — and
-- **returned silently** when the answer was no. Two things follow, and both are why the
-- shape below is different rather than the same code with the bug taken out:
--
--   * `is_courier_for_order` had already let that courier mark the order delivered, on
--     `auth.uid()` and an active staff row alone. So "may deliver" and "is charged" were
--     two questions with two answers, and the gap between them was money.
--   * A silent return leaves nothing behind. A courier dropped from the platform roster
--     went on working, nothing accrued, no error was raised and no row was written — and
--     the first sign would have been a Saturday reminder that never came.
--
-- So: **there is a row for every delivered order**, with the amount and the reason it is
-- what it is. A zero is a recorded decision rather than an absence, and `ground` says
-- which decision. That is the rule `apply_order_settlement` already follows — "an audit
-- trail with the uninteresting entries left out is one nobody can count" — applied to the
-- side that did not have it.
--
-- And eligibility is asked **once**, inside the transaction that marks the order
-- delivered, and frozen onto the row. A reversal reads the frozen figures back rather
-- than recomputing, so a rate changed next month cannot hand back an amount that was
-- never taken.

-- ------------------------------------------------------------------ the rate

insert into public.config (key, value) values ('courier_commission_percent', '10'::jsonb)
on conflict (key) do nothing;

create or replace function public.courier_commission_bps()
returns integer
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(
    (select round((value #>> '{}')::numeric * 100)::integer
       from public.config where key = 'courier_commission_percent'),
    1000);
$fn$;

revoke all on function public.courier_commission_bps() from public, anon;
grant execute on function public.courier_commission_bps() to authenticated, service_role;

-- Guarded on the table, so a direct write and an older AdminApp meet the same range.
create or replace function public.config_keeps_courier_commission_sane()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_number numeric;
begin
  if new.key <> 'courier_commission_percent' then
    return new;
  end if;
  begin
    v_number := (new.value #>> '{}')::numeric;
  exception when others then
    raise exception '% must be a number', new.key using errcode = 'check_violation';
  end;
  -- Zero is allowed and is not a mistake: it is how a courier runs at no commission,
  -- which is what every platform courier does until the owner decides otherwise.
  if v_number is null or v_number < 0 or v_number > 50 then
    raise exception '% is out of range', new.key using errcode = 'check_violation';
  end if;
  return new;
end;
$fn$;

drop trigger if exists config_keeps_courier_commission_sane on public.config;
create trigger config_keeps_courier_commission_sane
  before insert or update of value on public.config
  for each row execute function public.config_keeps_courier_commission_sane();

-- ------------------------------------------------------------------ what a courier owes

alter table public.staff
  add column if not exists commission_owed integer not null default 0;

comment on column public.staff.commission_owed is
  'Running total of platform commission this courier has accrued and not yet paid in '
  'cash. The ledger in courier_settlements is the evidence; this is the answer.';

-- A courier who can lower their own balance is a courier who owes nothing. `staff` already
-- refuses a self-edit of anything but `paused_until`, and activation already has to come
-- through the server boundary — this closes the last door, which is an *admin* writing the
-- figure directly instead of recording a payment against it.
create or replace function public.guard_staff_money()
returns trigger
language plpgsql
as $fn$
begin
  if new.commission_owed is distinct from old.commission_owed
     and coalesce(current_setting('app.server_mode', true), '') <> 'on' then
    raise exception 'commission_owed moves by settlement or payment, not by hand'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$fn$;

drop trigger if exists guard_staff_money on public.staff;
create trigger guard_staff_money before update on public.staff
  for each row execute function public.guard_staff_money();

-- ------------------------------------------------------------------ the ledger

create table if not exists public.courier_settlements (
  -- The primary key is the guard. A trigger inside the status transaction cannot be
  -- missed; it can still run twice — a retry, a second write of the same status, an admin
  -- touching a neighbouring column with `status` in the `set` list. Atomicity is not
  -- idempotence.
  order_id    uuid primary key references public.orders (id) on delete restrict,
  -- Null once the person has been deleted. The money stays, the person goes — the same
  -- rule as an order outliving the customer who placed it.
  courier_uid uuid references public.staff (uid) on delete set null,
  -- What the courier actually collected for the delivery: the fee less any discount on
  -- it, floored at zero. Free delivery means no commission, because charging a percentage
  -- of a fee nobody received is charging for money nobody received. The same sentence as
  -- «العمولة على الأكل مش على الفاتورة», from the other side.
  basis       integer not null check (basis >= 0),
  bps         integer not null check (bps between 0 and 5000),
  amount      integer not null check (amount >= 0),
  -- Why the amount is what it is. Written for every delivered order including the zeros,
  -- so "this courier was charged nothing" is a fact with a reason rather than a missing
  -- row somebody has to guess about.
  ground      text not null check (ground in (
                'platform',            -- a platform courier's own delivery: charged
                'merchantDelivery',    -- the shop delivered; the fee was never the courier's
                'notPlatformCourier'   -- carried for a shop, not for the platform
              )),
  settled_at  timestamptz not null default now(),
  reversed_at timestamptz
);

comment on table public.courier_settlements is
  'One row per delivered order, including the zeros. What the courier kept, what the '
  'platform is owed on it, and which of the three grounds decided that.';

create index if not exists courier_settlements_courier_idx
  on public.courier_settlements (courier_uid, settled_at desc);

alter table public.courier_settlements enable row level security;
alter table public.courier_settlements force row level security;
revoke all on public.courier_settlements from public, anon, authenticated;
grant select on public.courier_settlements to authenticated;

-- A courier reads their own; an admin reads everyone's. Nobody writes: every write is a
-- settlement or a payment, and both go through a definer function.
drop policy if exists read_own_courier_settlements on public.courier_settlements;
create policy read_own_courier_settlements on public.courier_settlements
  for select to authenticated
  using (courier_uid = (select auth.uid()) or public.is_admin());

-- ------------------------------------------------------------------ settling a delivery

create or replace function public.apply_courier_settlement(
  p_order_id uuid,
  p_charged  boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_order       record;
  v_existing    record;
  v_has_row     boolean;
  v_charged_now boolean;
  v_basis       integer;
  v_bps         integer;
  v_amount      integer;
  v_ground      text;
  v_uid         uuid;
  v_sign        integer;
  v_prior_mode  text;
begin
  -- `security definer` does not satisfy `guard_staff_money`, which asks whether a trusted
  -- server function has declared itself rather than who owns the function. And the setting
  -- is transaction-local inside somebody else's transaction, so it has to be put back.
  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  select id, delivery_by, courier_uid, pricing
    into v_order
    from public.orders
   where id = p_order_id;

  if not found then
    perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
    raise exception 'no such order: %', p_order_id using errcode = 'P0002';
  end if;

  select * into v_existing
    from public.courier_settlements
   where order_id = p_order_id
   for update;

  v_has_row := found;
  v_charged_now := v_has_row and v_existing.reversed_at is null;

  if v_charged_now = p_charged then
    perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
    return;
  end if;

  if p_charged then
    v_uid := v_order.courier_uid;

    -- Asked once, here, and frozen onto the row. The parked version asked at settlement
    -- time and said nothing when the answer was no; this says which answer it got.
    v_ground := case
      when v_order.delivery_by is distinct from 'platform' then 'merchantDelivery'
      when v_uid is null then 'merchantDelivery'
      when not exists (
             select 1 from public.courier_merchants cm
              where cm.courier_uid = v_uid
                and cm.merchant_id is null
                and cm.is_active
           ) then 'notPlatformCourier'
      else 'platform'
    end;

    v_basis := case
      when v_ground = 'platform' then greatest(
        coalesce((v_order.pricing ->> 'deliveryFee')::integer, 0)
        - coalesce((v_order.pricing ->> 'deliveryDiscount')::integer, 0), 0)
      else 0
    end;
    v_bps    := case when v_ground = 'platform' then public.courier_commission_bps() else 0 end;
    v_amount := (v_basis * v_bps) / 10000;
    v_sign   := 1;
  else
    -- A reversal returns exactly what was taken, read back off the row rather than
    -- recomputed. Recomputing would use today's rate for a charge made under terms that
    -- have since changed, and hand back an amount nobody was ever charged.
    v_uid    := v_existing.courier_uid;
    v_basis  := v_existing.basis;
    v_bps    := v_existing.bps;
    v_amount := v_existing.amount;
    v_ground := v_existing.ground;
    v_sign   := -1;
  end if;

  insert into public.courier_settlements
         (order_id, courier_uid, basis, bps, amount, ground)
  values (p_order_id, v_uid, v_basis, v_bps, v_amount, v_ground)
      on conflict (order_id) do update
         set reversed_at = case when p_charged then null else pg_catalog.now() end,
             settled_at  = case when p_charged then pg_catalog.now()
                                else courier_settlements.settled_at end;

  -- Nothing to move on a zero, and nobody to move it on once the person is gone. Both are
  -- ordinary, so neither is an error.
  if v_amount > 0 and v_uid is not null then
    update public.staff
       set commission_owed = commission_owed + v_sign * v_amount
     where uid = v_uid;
  end if;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
end;
$fn$;

revoke execute on function public.apply_courier_settlement(uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.apply_courier_settlement(uuid, boolean) to service_role;

-- The same trigger the merchant settlement already hangs off, so both happen inside the
-- transaction that moved the status and neither can be missed.
create or replace function public.settle_on_delivery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if new.status = 'delivered' then
    perform public.apply_order_settlement(new.id, true);
    perform public.apply_courier_settlement(new.id, true);
  elsif old.status = 'delivered' then
    perform public.apply_order_settlement(new.id, false);
    perform public.apply_courier_settlement(new.id, false);
  end if;
  return null;
end;
$fn$;

-- ------------------------------------------------------------------ collecting it

alter table public.payment_receipts
  drop constraint if exists payment_receipts_kind_check;
alter table public.payment_receipts
  add constraint payment_receipts_kind_check
  check (kind in ('walletTopUp', 'subscriptionPayment', 'courierCommission'));

alter table public.payment_receipts alter column merchant_id drop not null;
alter table public.payment_receipts
  add column if not exists courier_uid uuid references public.staff (uid) on delete set null;

-- A receipt is for a shop or for a courier, never for both and never for neither.
alter table public.payment_receipts
  drop constraint if exists payment_receipts_subject_check;
alter table public.payment_receipts
  add constraint payment_receipts_subject_check
  check ((kind = 'courierCommission' and merchant_id is null and courier_uid is not null)
      or (kind in ('walletTopUp', 'subscriptionPayment') and merchant_id is not null));

create table if not exists public.courier_commission_payments (
  id          uuid primary key default gen_random_uuid(),
  courier_uid uuid not null references public.staff (uid) on delete restrict,
  amount      integer not null check (amount > 0),
  note        text check (note is null or char_length(note) <= 500),
  recorded_by uuid references auth.users on delete set null,
  created_at  timestamptz not null default now()
);

comment on table public.courier_commission_payments is
  'Cash the owner collected from a courier. No write policy on purpose: a receipt that '
  'can be written without moving the balance is paper saying money changed hands while '
  'the account says otherwise, which is what a receipt exists to rule out.';

create index if not exists courier_commission_payments_courier_idx
  on public.courier_commission_payments (courier_uid, created_at desc);

alter table public.courier_commission_payments enable row level security;
alter table public.courier_commission_payments force row level security;
revoke all on public.courier_commission_payments from public, anon, authenticated;
grant select on public.courier_commission_payments to authenticated;

drop policy if exists read_own_courier_payments on public.courier_commission_payments;
create policy read_own_courier_payments on public.courier_commission_payments
  for select to authenticated
  using (courier_uid = (select auth.uid()) or public.is_admin());

create or replace function public.record_courier_payment(
  p_courier_uid uuid,
  p_amount      integer,
  p_note        text default null,
  p_receipt_id  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor      uuid := (select auth.uid());
  v_prior_mode text;
  v_existing   public.payment_receipts;
  v_remaining  integer;
  v_result     jsonb;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin records a collection' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'a payment is a positive amount' using errcode = '22023';
  end if;

  -- The phone names the payment, so a retry after a lost reply returns the stored answer
  -- instead of collecting twice. Optional, so an admin handset on an older APK keeps
  -- working — it just loses the protection against its own retries.
  if p_receipt_id is not null then
    select * into v_existing from public.payment_receipts where id = p_receipt_id;
    if found then
      return v_existing.result;
    end if;
  end if;

  -- The courier row is locked for the length of the work, so two admins recording at the
  -- same moment apply one after the other rather than both reading the same balance.
  perform 1 from public.staff where uid = p_courier_uid for update;
  if not found then
    raise exception 'no such courier' using errcode = 'P0002';
  end if;

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  insert into public.courier_commission_payments (courier_uid, amount, note, recorded_by)
  values (p_courier_uid, p_amount, nullif(pg_catalog.btrim(p_note), ''), v_actor);

  -- Not capped at what is owed. Somebody handing over more than they owe is credit, and
  -- both screens say so in words rather than printing a minus sign.
  update public.staff
     set commission_owed = commission_owed - p_amount
   where uid = p_courier_uid
  returning commission_owed into v_remaining;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);

  insert into public.audit_log (action, actor, detail)
  values ('recordCourierPayment', v_actor,
          pg_catalog.jsonb_build_object('courier', p_courier_uid, 'amount', p_amount,
                                        'receipt', p_receipt_id));

  v_result := pg_catalog.jsonb_build_object('remaining', v_remaining);

  if p_receipt_id is not null then
    insert into public.payment_receipts (id, kind, merchant_id, courier_uid, result, recorded_by)
    values (p_receipt_id, 'courierCommission', null, p_courier_uid, v_result, v_actor);
  end if;

  return v_result;
end;
$fn$;

revoke execute on function public.record_courier_payment(uuid, integer, text, uuid)
  from public, anon;
grant execute on function public.record_courier_payment(uuid, integer, text, uuid)
  to authenticated, service_role;

-- ------------------------------------------------------------------ what a rider earned

-- Today, this week and this month in one call.
--
-- One call rather than three because the person reading it is standing in the street on a
-- phone, and three round trips is three chances for one of them not to arrive. The week
-- starts on Saturday and the month is a calendar month, because that is how somebody
-- settling up weekly thinks about it — not a rolling seven days that never lines up with
-- the conversation they are about to have.
create or replace function public.courier_earnings()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $fn$
  with bounds as (
    select (pg_catalog.now() at time zone 'Africa/Cairo')::date as today
  ),
  spans as (
    select 'today'::text as span, today as from_day, today as to_day from bounds
    union all
    -- Saturday is day 6 in Postgres's dow, and the week somebody settles for starts there.
    -- `date_part` rather than `extract`, which is syntax rather than a function and so
    -- cannot be schema-qualified — and this body runs with an empty search_path.
    select 'week', today - ((pg_catalog.date_part('dow', today)::integer + 1) % 7), today
      from bounds
    union all
    select 'month', pg_catalog.date_trunc('month', today)::date, today from bounds
  ),
  mine as (
    select o.merchant_id,
           o.merchant_name,
           o.status,
           -- When the work happened, not when the row was last touched: an admin editing
           -- a note next week must not move last night's delivery into next week.
           coalesce(o.delivered_at, o.updated_at) as happened_at,
           coalesce((o.pricing ->> 'total')::bigint, 0) as cash,
           case when o.delivery_by = 'platform'
                then greatest(coalesce((o.pricing ->> 'deliveryFee')::bigint, 0)
                              - coalesce((o.pricing ->> 'deliveryDiscount')::bigint, 0), 0)
                else 0 end as fee,
           coalesce(cs.amount, 0)::bigint as commission
      from public.orders o
      left join public.courier_settlements cs
             on cs.order_id = o.id and cs.reversed_at is null
     -- Their own work and nobody else's. `read_orders` would also show every order of
     -- every shop they carry for, which is right for a queue and wrong for a count of
     -- what *they* did.
     where o.courier_uid = (select auth.uid())
       and (o.status = 'delivered'
            or (o.status = 'cancelled' and o.cancelled_by = 'courier'))
  ),
  per_span as (
    select s.span,
           count(*) filter (where m.status = 'delivered')::int as delivered,
           count(*) filter (where m.status = 'cancelled')::int as returned,
           coalesce(sum(m.cash) filter (where m.status = 'delivered'), 0)::bigint as cash,
           coalesce(sum(m.fee) filter (where m.status = 'delivered'), 0)::bigint as fees,
           coalesce(sum(m.commission) filter (where m.status = 'delivered'), 0)::bigint
             as commission
      from spans s
      left join mine m
             on (m.happened_at at time zone 'Africa/Cairo')::date
                  between s.from_day and s.to_day
     group by s.span
  )
  select pg_catalog.jsonb_object_agg(
           span,
           pg_catalog.jsonb_build_object(
             'delivered',  delivered,
             'returned',   returned,
             'cash',       cash,
             'fees',       fees,
             'commission', commission,
             -- What is actually theirs once the platform's share comes out. Computed here
             -- rather than on the phone, so the figure a courier argues from and the
             -- figure the owner collects against come from one statement.
             'net',        fees - commission
           ))
    from per_span;
$fn$;

revoke execute on function public.courier_earnings() from public, anon;
grant execute on function public.courier_earnings() to authenticated, service_role;
