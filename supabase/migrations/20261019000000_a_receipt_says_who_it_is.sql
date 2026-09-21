-- H-13: a courier payment's reply names the receipt it belongs to.
--
-- `record_courier_payment` answered with `{remaining, amount}`. Neither says *which*
-- payment, so the screen reconciling a pending attempt had nothing to check against: any
-- balance coming back looked like a valid reply to the attempt in hand. A stale pending
-- record and a later collection could therefore be told apart by nobody — the screen
-- would report a success that belonged to a different payment, in a cash business where
-- the receipt is the only evidence there is.
--
-- The reply now carries the whole identity: the receipt, its kind, whose it is, the
-- amount, when it was first recorded, the balance left, and — the field the screen most
-- needs — whether this call *recorded* anything or merely read back a receipt the server
-- already held.
--
-- `repeated` is not decoration. Without it, "the cash was taken" and "the cash had
-- already been taken, and this changed nothing" are the same sentence, and only one of
-- them is true of the tap in front of the operator.

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
  v_actor           uuid := (select auth.uid());
  v_prior_mode      text;
  v_existing        public.payment_receipts;
  v_existing_amount integer;
  v_remaining       integer;
  v_created_at      timestamptz;
  v_result          jsonb;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin records a collection' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'a payment is a positive amount' using errcode = '22023';
  end if;

  if p_receipt_id is not null then
    select * into v_existing from public.payment_receipts where id = p_receipt_id;
    if found then
      -- A receipt is for one kind of payment, for one subject. Replaying a shop's
      -- top-up as a courier's collection would be one receipt paying for the wrong
      -- thing, so the mismatch is refused rather than reconciled.
      if v_existing.kind <> 'courierCommission'
         or v_existing.courier_uid is distinct from p_courier_uid
         or v_existing.merchant_id is not null then
        raise exception 'receipt belongs to another payment' using errcode = '23505';
      end if;

      if v_existing.result ? 'amount'
         and v_existing.result->>'amount' ~ '^[1-9][0-9]*$' then
        v_existing_amount := (v_existing.result->>'amount')::integer;
      else
        -- A receipt written by an older release can still be verified from the audit row
        -- that release wrote in the same transaction.
        select (detail->>'amount')::integer
          into v_existing_amount
          from public.audit_log
         where action = 'recordCourierPayment'
           and detail->>'receipt' = p_receipt_id::text
           and detail->>'courier' = p_courier_uid::text
           and detail->>'amount' ~ '^[1-9][0-9]*$'
         order by at desc
         limit 1;

        -- Heal the old receipt while we are here, so the next replay can be verified
        -- from the receipt itself rather than from a log row that retention may one day
        -- take away.
        if v_existing_amount is not null then
          update public.payment_receipts
             set result = result || pg_catalog.jsonb_build_object('amount', v_existing_amount)
           where id = p_receipt_id;
        end if;
      end if;

      if v_existing_amount is null then
        raise exception 'receipt amount cannot be verified' using errcode = '23505';
      end if;
      if v_existing_amount <> p_amount then
        raise exception 'receipt belongs to another payment' using errcode = '23505';
      end if;

      -- The balance as it stands now, not as it stood when the receipt was written. The
      -- operator is looking at this courier's account today, and a figure from last week
      -- presented as the answer is a figure they would act on.
      select commission_owed into v_remaining
        from public.staff where uid = p_courier_uid;

      return pg_catalog.jsonb_build_object(
        'receiptId', p_receipt_id,
        'kind',      'courierCommission',
        'courierUid', p_courier_uid,
        'amount',    v_existing_amount,
        'createdAt', v_existing.created_at,
        'remaining', v_remaining,
        'repeated',  true);
    end if;
  end if;

  perform 1
    from public.staff
   where uid = p_courier_uid
     and role = 'courier'
   for update;
  if not found then
    raise exception 'no such courier' using errcode = 'P0002';
  end if;

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  insert into public.courier_commission_payments
    (courier_uid, amount, note, recorded_by)
  values
    (p_courier_uid, p_amount, nullif(pg_catalog.btrim(p_note), ''), v_actor)
  returning created_at into v_created_at;

  update public.staff
     set commission_owed = commission_owed - p_amount
   where uid = p_courier_uid
  returning commission_owed into v_remaining;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);

  insert into public.audit_log (action, actor, detail)
  values ('recordCourierPayment', v_actor,
          pg_catalog.jsonb_build_object('courier', p_courier_uid, 'amount', p_amount,
                                        'receipt', p_receipt_id));

  v_result := pg_catalog.jsonb_build_object(
    'receiptId',  p_receipt_id,
    'kind',       'courierCommission',
    'courierUid', p_courier_uid,
    'amount',     p_amount,
    'createdAt',  v_created_at,
    'remaining',  v_remaining,
    'repeated',   false);

  if p_receipt_id is not null then
    insert into public.payment_receipts
      (id, kind, merchant_id, courier_uid, result, recorded_by)
    values
      (p_receipt_id, 'courierCommission', null, p_courier_uid, v_result, v_actor);
  end if;

  return v_result;
end;
$fn$;

revoke execute on function public.record_courier_payment(uuid, integer, text, uuid)
  from public, anon;
grant execute on function public.record_courier_payment(uuid, integer, text, uuid)
  to authenticated, service_role;
