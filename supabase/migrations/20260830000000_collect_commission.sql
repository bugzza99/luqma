-- Taking the money.
--
-- Since yesterday the platform charges for a delivery: `order_settlements` records what
-- was taken and `merchants.commission_owed` is the running total. Nothing ever lowered
-- it. A debt that only grows is not an account, it is a number that eventually stops
-- meaning anything — and the first merchant to pay in cash would have watched the figure
-- on their own screen stay exactly where it was.
--
-- This is the other half, and it is deliberately the same shape as
-- `record_subscription_payment`: an admin, a figure, a row, and a line in the audit log.
-- Collection here is a person and a receipt, because the money is cash.

-- ------------------------------------------------------------------ the receipts

create table commission_payments (
  id          uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants on delete restrict,

  -- Piastres, and positive. A negative payment would be a refund, which is a different
  -- act with a different conversation behind it, and letting it in through this door
  -- would make one screen able to both collect and hand back without saying which.
  amount      integer not null check (amount > 0),

  -- What was said at the counter. Optional, and it is the only free text in the money
  -- path — "دفع ٤٧٠ والباقي الأسبوع الجاي" is the kind of thing that decides an argument
  -- three weeks later.
  note        text,

  -- Never a parameter. The second pre-launch audit found `record_subscription_payment`
  -- taking `p_recorded_by` and believing it, so the log recorded whoever the caller
  -- named. A log that can be lied to is not evidence, and answering "who took this
  -- money" is the only reason it exists.
  recorded_by uuid not null references auth.users,
  recorded_at timestamptz not null default now()
);

-- The merchant's own receipts, newest first, and the admin's per-merchant view.
create index commission_payments_merchant_idx
  on commission_payments (merchant_id, recorded_at desc);

-- ------------------------------------------------------------------ recording one

-- Records a cash collection against a merchant's commission.
--
-- `security definer`, unlike `top_up_wallet`, and for a reason worth stating: this writes
-- a *receipt*, and `commission_payments` has no insert policy on purpose. Adding one for
-- admins would let an admin write a receipt without moving the balance — a piece of paper
-- saying money changed hands while the account says it did not, which is the exact thing
-- a receipt exists to rule out. So the table is writable by nothing at all, and this
-- function, which does both halves or neither, is the only way in.
--
-- It still declares `app.server_mode`: `security definer` does not satisfy `guard_columns`
-- on `commission_owed`, because that guard asks whether a trusted server function has
-- declared itself, not who owns the function.
--
-- The amount is *not* capped at what is owed. An admin standing in a shop takes what is
-- handed over, and a merchant who rounds up by five pounds must not meet an error with
-- the cash already on the counter — the balance simply goes negative, which is the
-- platform holding credit for them and is what the next delivery eats into.
create or replace function public.record_commission_payment(
  p_merchant_id uuid,
  p_amount      integer,
  p_note        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_actor      uuid := auth.uid();
  v_prior_mode text;
  v_payment    public.commission_payments;
  v_remaining  integer;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin records a collection' using errcode = '42501';
  end if;

  if p_amount <= 0 then
    raise exception 'a collection must be positive' using errcode = 'check_violation';
  end if;

  v_prior_mode := coalesce(current_setting('app.server_mode', true), '');
  perform set_config('app.server_mode', 'on', true);

  update public.merchants
     set commission_owed = commission_owed - p_amount
   where id = p_merchant_id
  returning commission_owed into v_remaining;

  if not found then
    raise exception 'no such merchant' using errcode = 'P0002';
  end if;

  insert into public.commission_payments (merchant_id, amount, note, recorded_by)
  values (p_merchant_id, p_amount, nullif(btrim(p_note), ''), v_actor)
  returning * into v_payment;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values ('recordCommissionPayment', v_actor, p_merchant_id,
          jsonb_build_object('amount', p_amount, 'remaining', v_remaining));

  -- Put back, rather than left standing. The setting is transaction-local, and a
  -- function that opens every guard and walks away has opened them for whatever runs
  -- next in the same transaction.
  perform set_config('app.server_mode', v_prior_mode, true);

  -- The new balance comes back with the receipt so the screen can show what is left
  -- without a second read — and so the figure it shows is the one this statement wrote,
  -- rather than one a re-fetch might have raced a delivery to.
  return jsonb_build_object(
    'payment', to_jsonb(v_payment),
    'remaining', v_remaining
  );
end;
$fn$;

revoke execute on function public.record_commission_payment(uuid, integer, text)
  from public, anon;
grant execute on function public.record_commission_payment(uuid, integer, text)
  to authenticated, service_role;

-- ------------------------------------------------------------------ who may read it

alter table commission_payments enable row level security;

-- A merchant reads their own receipts; an admin reads anybody's. No write policy, and
-- there is not meant to be one: the only thing that may write this table is the function
-- above, and it checks who is calling before it does.
create policy read_own_commission_payments on commission_payments
  for select to authenticated
  using (public.is_merchant_owner(merchant_id) or public.is_admin());

grant select on commission_payments to authenticated;
