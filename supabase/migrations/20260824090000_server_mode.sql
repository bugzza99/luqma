-- Server functions declare themselves.
--
-- The column guards exist to stop *clients* moving what only the server may move. But
-- the server's own functions — recording a payment, placing an order — must move those
-- columns, and `is_admin()` reads the caller's token, which a function called through
-- the service role does not carry.
--
-- So a trusted function sets `app.server_mode` for its transaction and the guards step
-- aside. The setting is transaction-local and no HTTP client can set it: PostgREST
-- exposes none of it. This is the line between "the server decided" and "somebody
-- typed it", drawn where it can be seen.
create or replace function public.guard_columns()
returns trigger
language plpgsql
as $$
declare
  allowed text[] := tg_argv[0]::text[] || array['updated_at'];
  touched text[];
begin
  -- A trusted server function has declared itself; every column is theirs to move.
  if coalesce(current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  if public.is_admin() then
    return new;
  end if;

  select coalesce(array_agg(k), '{}')
    into touched
    from jsonb_each(to_jsonb(new)) as changes(k, v)
   where v is distinct from (to_jsonb(old) -> changes.k);

  if not (touched <@ allowed) then
    raise exception 'column not yours to change on %: %',
      tg_table_name,
      array_to_string(
        array(select unnest(touched) except select unnest(allowed)), ', '
      )
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

-- And the two billing functions declare themselves.
create or replace function public.record_subscription_payment(
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

create or replace function public.top_up_wallet(
  p_merchant_id uuid,
  p_amount      integer,
  p_recorded_by uuid
)
returns void
language plpgsql
as $$
begin
  perform set_config('app.server_mode', 'on', true);

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
