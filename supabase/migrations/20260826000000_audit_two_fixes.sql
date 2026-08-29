-- The second pre-launch audit, 2026-08-26.
--
-- Three findings, all in the same place: the code that steps around the guards on
-- purpose. `app.server_mode` and `security definer` exist because the server must move
-- what no client may — that is right and necessary. What the audit found is that **a
-- door which bypasses the guards needs a guard of its own**, and three of them opened
-- without one.

-- ---------------------------------------------------------------- S1

-- Blocking a customer did nothing at all.
--
-- `users.is_blocked` was written by `admin_set_customer_blocked` and read by *nobody*:
-- not by `place_order`, not by any policy, not by the token hook. The comment beside it
-- said sessions die at the sign-in boundary; no code did that. Proven by running it — a
-- blocked customer placed an order exactly as an unblocked one did.
--
-- Checked at the one door every order comes through, and before anything else is read:
-- a blocked customer has no business being told which merchant is closed.
--
-- The three hundred lines of pricing are not rewritten to add four. The existing
-- function becomes a private helper and a new `place_order` guards it.
--
-- **The rename carries the old grants with it**, which would leave the helper callable
-- by `authenticated` — the door beside the door, and exactly the class of hole being
-- fixed here. So it is revoked from everyone: the wrapper is SECURITY DEFINER and runs
-- as the owner, so it needs no grant to reach it, and nobody else can.
alter function public.place_order(jsonb) rename to place_order_priced;

revoke all on function public.place_order_priced(jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.place_order(p_draft jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if auth.uid() is null then
    raise exception 'sign in to place an order' using errcode = '42501';
  end if;

  if exists (select 1 from public.users where id = auth.uid() and is_blocked) then
    raise exception 'this account cannot place orders' using errcode = '42501';
  end if;

  return public.place_order_priced(p_draft);
end;
$fn$;

revoke execute on function public.place_order(jsonb) from public, anon;
grant execute on function public.place_order(jsonb) to authenticated, service_role;

comment on function public.place_order(jsonb) is
  'The one door every order comes through. Refuses a blocked customer, then hands the '
  'draft to place_order_priced, which reads every price from its source.';

-- ---------------------------------------------------------------- M1 and M2

-- Two functions declared `app.server_mode` — which stands every column guard down — and
-- then asked nobody who was calling. Both are granted to `authenticated`.
--
-- The exploit was closed only by accident: a merchant owner's call reached the wallet
-- update and was stopped by the audit_log insert policy, the last statement in the
-- function. Reorder the statements or loosen that policy and the door is open, and a
-- merchant tops up their own prepaid wallet — free service, indefinitely.
--
-- And the audit log believed the caller. `p_recorded_by` was a parameter, so the log
-- recorded whoever was named rather than whoever called. Proven: real caller and logged
-- actor were two different accounts. A log that can be lied to is not evidence, and the
-- one question it exists to answer is "who did this" when money is disputed.
--
-- The parameter stays in the signature so no caller breaks, and is ignored.
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

  -- The subscription is the receipt; this is the state every feature check reads.
  update public.merchants set plan_id = p_plan_id where id = p_merchant_id;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values ('recordSubscriptionPayment', v_actor, p_merchant_id,
          jsonb_build_object('planId', p_plan_id, 'amount', p_amount,
                             'months', p_months));

  return to_jsonb(term);
end;
$fn$;

create or replace function public.top_up_wallet(
  p_merchant_id uuid,
  p_amount      integer,
  p_recorded_by uuid default null
)
returns void
language plpgsql
as $fn$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin tops up a wallet' using errcode = '42501';
  end if;

  perform set_config('app.server_mode', 'on', true);

  if p_amount <= 0 then
    raise exception 'a top-up must be positive' using errcode = 'check_violation';
  end if;

  update public.merchants
     set wallet_balance = wallet_balance + p_amount
   where id = p_merchant_id;
  if not found then
    raise exception 'no such merchant' using errcode = 'P0002';
  end if;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values ('topUpWallet', v_actor, p_merchant_id,
          jsonb_build_object('amount', p_amount));
end;
$fn$;

revoke execute on function public.record_subscription_payment(uuid, text, integer, integer, uuid)
  from public, anon;
grant execute on function public.record_subscription_payment(uuid, text, integer, integer, uuid)
  to authenticated, service_role;
revoke execute on function public.top_up_wallet(uuid, integer, uuid) from public, anon;
grant execute on function public.top_up_wallet(uuid, integer, uuid)
  to authenticated, service_role;
