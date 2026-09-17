-- A retry after a lost reply recorded the same cash twice.
--
-- `record_commission_payment` subtracted the amount and wrote a fresh receipt on every
-- call, with nothing to say two calls were the same collection. If the transaction
-- committed and its reply never arrived — an ordinary thing on a phone in a shop —
-- AdminApp told the owner it had **not** been recorded and offered to try again. That
-- advice was false, and taking it turned a 100 debt into zero and then into 100 of
-- credit: money the platform now owes for cash it collected once.
--
-- The same shape as `orders.client_order_id`, and for the same reason: the caller names
-- the attempt, and a unique index — not a `select` first — is what settles two requests
-- that arrive together.

alter table commission_payments
  add column if not exists client_payment_id uuid;

-- Partial, so every receipt written before this column existed stays legal, and two
-- unidentified collections on the same day remain two collections.
create unique index if not exists commission_payments_client_idx
  on commission_payments (merchant_id, client_payment_id)
  where client_payment_id is not null;

comment on column commission_payments.client_payment_id is
  'Names one collection attempt, so a retry after a lost reply returns the original '
  'receipt instead of taking the money a second time.';

-- Dropped rather than replaced: a changed argument list is a new function to Postgres,
-- and two overloads would leave PostgREST choosing between them.
drop function if exists public.record_commission_payment(uuid, integer, text);

create function public.record_commission_payment(
  p_merchant_id uuid,
  p_amount      integer,
  p_note        text default null,
  p_client_payment_id uuid default null
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

  -- The cheap path: this attempt already landed. Return what it wrote, before touching
  -- a balance.
  if p_client_payment_id is not null then
    select * into v_payment from public.commission_payments
     where merchant_id = p_merchant_id
       and client_payment_id = p_client_payment_id;
    if found then
      select commission_owed into v_remaining
        from public.merchants where id = p_merchant_id;
      return jsonb_build_object('payment', to_jsonb(v_payment),
                                'remaining', v_remaining);
    end if;
  end if;

  v_prior_mode := coalesce(current_setting('app.server_mode', true), '');
  perform set_config('app.server_mode', 'on', true);

  -- Everything from here is one subtransaction, so a lost race to the unique index takes
  -- the balance change back with the receipt rather than leaving the money moved and no
  -- paper for it.
  begin
    update public.merchants
       set commission_owed = commission_owed - p_amount
     where id = p_merchant_id
    returning commission_owed into v_remaining;

    if not found then
      raise exception 'no such merchant' using errcode = 'P0002';
    end if;

    insert into public.commission_payments
      (merchant_id, amount, note, recorded_by, client_payment_id)
    values (p_merchant_id, p_amount, nullif(btrim(p_note), ''), v_actor,
            p_client_payment_id)
    returning * into v_payment;

    insert into public.audit_log (action, actor, merchant_id, detail)
    values ('recordCommissionPayment', v_actor, p_merchant_id,
            jsonb_build_object('amount', p_amount, 'remaining', v_remaining));
  exception
    when unique_violation then
      -- Another request carrying the same id won. Its receipt is the answer; this one's
      -- subtraction has already rolled back with the block.
      select * into v_payment from public.commission_payments
       where merchant_id = p_merchant_id
         and client_payment_id = p_client_payment_id;
      if not found then
        -- A different unique boundary. Not an idempotent retry, so keep the real error
        -- rather than dressing it as one.
        raise;
      end if;
      select commission_owed into v_remaining
        from public.merchants where id = p_merchant_id;
  end;

  perform set_config('app.server_mode', v_prior_mode, true);

  return jsonb_build_object('payment', to_jsonb(v_payment), 'remaining', v_remaining);
end;
$fn$;

revoke execute on function
  public.record_commission_payment(uuid, integer, text, uuid) from public, anon;
grant execute on function
  public.record_commission_payment(uuid, integer, text, uuid) to authenticated, service_role;
