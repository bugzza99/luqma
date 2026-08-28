-- Billing, feedback and promotions join realtime: each is watched live somewhere.
select public.add_table_to_realtime('subscriptions');
select public.add_table_to_realtime('ratings');
select public.add_table_to_realtime('promotions');

-- ---------------------------------------------------------------- billing

-- Taking a subscription payment, in one statement.
--
-- Three writes that must land together: the receipt (the subscription row), the state
-- (the plan moving onto the merchant), and the memory (an audit entry). A payment whose
-- receipt landed but whose plan did not would charge a merchant for a plan they never
-- got. Renewing an unexpired term extends it — throwing away days already paid for is
-- the kind of thing a merchant notices once and never forgets.
create function public.record_subscription_payment(
  p_merchant_id uuid,
  p_plan_id     text,
  p_amount      integer,
  p_months      integer,
  p_recorded_by uuid
)
returns jsonb
language plpgsql
as $$
declare
  latest    public.subscriptions;
  starts_at timestamptz;
  term      public.subscriptions;
begin
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
     starts_at + make_interval(days => 30 * p_months), p_recorded_by)
  returning * into term;

  -- The subscription is the receipt; this is the state every feature check reads.
  update public.merchants set plan_id = p_plan_id where id = p_merchant_id;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values ('recordSubscriptionPayment', p_recorded_by, p_merchant_id,
          jsonb_build_object('planId', p_plan_id, 'amount', p_amount,
                             'months', p_months));

  return to_jsonb(term);
end;
$$;

-- Adding prepaid credit. Adds to the balance; never replaces it.
create function public.top_up_wallet(
  p_merchant_id uuid,
  p_amount      integer,
  p_recorded_by uuid
)
returns void
language plpgsql
as $$
begin
  if p_amount <= 0 then
    raise exception 'a top-up must be positive'
      using errcode = 'check_violation';
  end if;

  update public.merchants
     set wallet_balance = wallet_balance + p_amount
   where id = p_merchant_id;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values ('topUpWallet', p_recorded_by, p_merchant_id,
          jsonb_build_object('amount', p_amount));
end;
$$;

revoke execute on function public.record_subscription_payment(uuid, text, integer, integer, uuid)
  from public, anon;
grant execute on function public.record_subscription_payment(uuid, text, integer, integer, uuid)
  to authenticated, service_role;
revoke execute on function public.top_up_wallet(uuid, integer, uuid) from public, anon;
grant execute on function public.top_up_wallet(uuid, integer, uuid)
  to authenticated, service_role;
