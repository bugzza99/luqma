-- A payment is recorded once, however many times the button is pressed.
--
-- The QA review of 2026-09-19 found the two places money is written from AdminApp could
-- both be written twice:
--
--   * `top_up_wallet` added to the balance on every call. The owner taps «سجّل», the server
--     credits the shop, the reply dies with the connection, the owner taps again — and the
--     shop has twice the credit for one handful of cash.
--   * `record_subscription_payment` inserted a new term on every call, and read the latest
--     term without a lock, so a retry extended the plan twice and two admins recording at
--     the same moment each started a term from the same expiry.
--
-- The fix is the ordinary one for a request that must not happen twice: the phone names the
-- payment. It makes a receipt id when the dialog opens and sends the same id on every retry;
-- the first call to arrive with it does the work and keeps the answer, and any later call
-- with it gets that answer back and changes nothing. The merchant row is locked for the
-- length of the work, so two different payments for one shop are applied one after the other
-- rather than both reading the same expiry.
--
-- The receipt is optional (default null) so an admin phone still carrying an older APK keeps
-- working — it gets the lock, just not the protection against its own retries.

create table if not exists public.payment_receipts (
  id          uuid primary key,
  kind        text not null check (kind in ('walletTopUp', 'subscriptionPayment')),
  merchant_id uuid not null references public.merchants on delete cascade,
  result      jsonb not null default '{}'::jsonb,
  recorded_by uuid references auth.users on delete set null,
  created_at  timestamptz not null default now()
);

comment on table public.payment_receipts is
  'One row per payment an admin recorded, keyed by the id the phone made for it. A second '
  'call with the same id returns the first answer instead of recording the money again.';

alter table public.payment_receipts enable row level security;
alter table public.payment_receipts force row level security;
revoke all on public.payment_receipts from public, anon, authenticated;
grant select on public.payment_receipts to authenticated;
create policy admin_reads_receipts on public.payment_receipts
  for select to authenticated using (public.is_admin());

-- ------------------------------------------------------------------ the wallet

drop function if exists public.top_up_wallet(uuid, integer, uuid);

create or replace function public.top_up_wallet(
  p_merchant_id uuid,
  p_amount      integer,
  p_recorded_by uuid default null,
  p_receipt_id  uuid default null
)
returns jsonb
language plpgsql
-- Definer, because `payment_receipts` grants no insert to anybody: the receipt is written
-- here or nowhere. An invoker function failed every receipt-bearing payment for a real
-- admin token and passed every owner-run test (Astra's review, 2026-09-19).
security definer
set search_path = ''
as $fn$
declare
  v_actor    uuid := auth.uid();
  v_prior    text;
  v_existing public.payment_receipts;
  v_balance  integer;
  v_result   jsonb;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin tops up a wallet' using errcode = '42501';
  end if;
  if p_amount <= 0 then
    raise exception 'a top-up must be positive' using errcode = 'check_violation';
  end if;

  -- The shop, locked: this payment and any other for the same shop happen in turn.
  perform 1 from public.merchants where id = p_merchant_id for update;
  if not found then
    raise exception 'no such merchant' using errcode = 'P0002';
  end if;

  if p_receipt_id is not null then
    select * into v_existing from public.payment_receipts where id = p_receipt_id;
    if found then
      if v_existing.kind <> 'walletTopUp' or v_existing.merchant_id <> p_merchant_id then
        raise exception 'that receipt belongs to another payment' using errcode = '23505';
      end if;
      return v_existing.result || jsonb_build_object('repeated', true);
    end if;
  end if;

  v_prior := coalesce(current_setting('app.server_mode', true), '');
  perform set_config('app.server_mode', 'on', true);

  update public.merchants
     set wallet_balance = wallet_balance + p_amount
   where id = p_merchant_id
  returning wallet_balance into v_balance;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values ('topUpWallet', v_actor, p_merchant_id,
          jsonb_build_object('amount', p_amount, 'receipt', p_receipt_id));

  v_result := jsonb_build_object('amount', p_amount, 'walletBalance', v_balance);

  if p_receipt_id is not null then
    insert into public.payment_receipts (id, kind, merchant_id, result, recorded_by)
    values (p_receipt_id, 'walletTopUp', p_merchant_id, v_result, v_actor);
  end if;

  perform set_config('app.server_mode', v_prior, true);
  return v_result || jsonb_build_object('repeated', false);
end;
$fn$;

revoke execute on function public.top_up_wallet(uuid, integer, uuid, uuid) from public, anon;
grant execute on function public.top_up_wallet(uuid, integer, uuid, uuid)
  to authenticated, service_role;

-- ------------------------------------------------------------------ a subscription term

drop function if exists public.record_subscription_payment(uuid, text, integer, integer, uuid);

create or replace function public.record_subscription_payment(
  p_merchant_id uuid,
  p_plan_id     text,
  p_amount      integer,
  p_months      integer,
  p_recorded_by uuid default null,
  p_receipt_id  uuid default null
)
returns jsonb
language plpgsql
-- Definer, because `payment_receipts` grants no insert to anybody: the receipt is written
-- here or nowhere. An invoker function failed every receipt-bearing payment for a real
-- admin token and passed every owner-run test (Astra's review, 2026-09-19).
security definer
set search_path = ''
as $fn$
declare
  v_actor    uuid := auth.uid();
  v_prior    text;
  v_existing public.payment_receipts;
  latest     public.subscriptions;
  starts_at  timestamptz;
  term       public.subscriptions;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin records a payment' using errcode = '42501';
  end if;
  if p_months < 1 or p_amount < 0 then
    raise exception 'months must be positive and amount non-negative'
      using errcode = 'check_violation';
  end if;

  -- Locked first, before the latest term is read: two payments for one shop recorded at
  -- the same moment used to both start from the same expiry and overlap.
  perform 1 from public.merchants where id = p_merchant_id for update;
  if not found then
    raise exception 'no such merchant' using errcode = 'P0002';
  end if;

  if p_receipt_id is not null then
    select * into v_existing from public.payment_receipts where id = p_receipt_id;
    if found then
      if v_existing.kind <> 'subscriptionPayment' or v_existing.merchant_id <> p_merchant_id then
        raise exception 'that receipt belongs to another payment' using errcode = '23505';
      end if;
      return v_existing.result;
    end if;
  end if;

  v_prior := coalesce(current_setting('app.server_mode', true), '');
  perform set_config('app.server_mode', 'on', true);

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

  update public.merchants
     set plan_id = p_plan_id,
         plan_expires_at = term.expires_at
   where id = p_merchant_id;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values ('recordSubscriptionPayment', v_actor, p_merchant_id,
          jsonb_build_object('planId', p_plan_id, 'amount', p_amount,
                             'months', p_months, 'receipt', p_receipt_id));

  if p_receipt_id is not null then
    insert into public.payment_receipts (id, kind, merchant_id, result, recorded_by)
    values (p_receipt_id, 'subscriptionPayment', p_merchant_id, to_jsonb(term), v_actor);
  end if;

  perform set_config('app.server_mode', v_prior, true);
  return to_jsonb(term);
end;
$fn$;

revoke execute on function public.record_subscription_payment(uuid, text, integer, integer, uuid, uuid)
  from public, anon;
grant execute on function public.record_subscription_payment(uuid, text, integer, integer, uuid, uuid)
  to authenticated, service_role;
