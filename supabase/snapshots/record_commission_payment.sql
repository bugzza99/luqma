-- SNAPSHOT of public.record_commission_payment as it runs — written by snapshot-functions.mjs.
-- Documentation only: never applied. Change it with a migration.

CREATE OR REPLACE FUNCTION public.record_commission_payment(p_merchant_id uuid, p_amount integer, p_note text DEFAULT NULL::text, p_client_payment_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_actor      uuid := auth.uid();
  v_prior_mode text;
  v_payment    public.commission_payments;
  v_remaining  integer;
begin
  if v_actor is null or not public.is_platform_admin() then
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
$function$;

CREATE OR REPLACE FUNCTION public.record_commission_payment(p_merchant_id uuid, p_amount integer, p_note text, p_client_payment_id uuid, p_expected_owed integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_current integer;
begin
  if auth.uid() is null or not public.is_platform_admin() then
    raise exception 'only an admin records a collection' using errcode = '42501';
  end if;

  select commission_owed
    into v_current
    from public.merchants
   where id = p_merchant_id
   for update;
  if not found then
    raise exception 'no such merchant' using errcode = 'P0002';
  end if;

  if p_client_payment_id is not null
     and exists (
       select 1 from public.commission_payments
        where merchant_id = p_merchant_id
          and client_payment_id = p_client_payment_id) then
    return public.record_commission_payment(
      p_merchant_id, p_amount, p_note, p_client_payment_id);
  end if;

  if p_expected_owed is not null and v_current is distinct from p_expected_owed then
    raise exception 'shop balance changed' using errcode = 'P0001';
  end if;

  return public.record_commission_payment(
    p_merchant_id, p_amount, p_note, p_client_payment_id);
end;
$function$;
