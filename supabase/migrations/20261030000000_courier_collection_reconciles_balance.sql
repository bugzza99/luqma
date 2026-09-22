-- M-10/M-11: the balance an admin collects against must still be the balance on the row.
--
-- Realtime can make a displayed number move sooner, but it cannot close the gap between
-- reading it and recording cash. Two admins can hold the same figure, mint different
-- receipts, and both calls are valid to the four-argument function; its row lock merely
-- applies them one after the other. The second payment then becomes credit even though
-- neither operator intended an overpayment.
--
-- The five-argument overload carries the opening balance the operator acted on. It checks
-- that figure while holding the same staff-row lock the payment will use. A receipt already
-- on file wins before the freshness check: retrying after a lost reply must reconcile the
-- first payment, not reject it because that payment changed the balance itself.

create or replace function public.record_courier_payment(
  p_courier_uid     uuid,
  p_amount          integer,
  p_note            text,
  p_receipt_id      uuid,
  p_expected_balance integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor   uuid := (select auth.uid());
  v_current integer;
begin
  if v_actor is null or not public.is_platform_admin() then
    raise exception 'only an admin records a collection' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'a payment is a positive amount' using errcode = '22023';
  end if;

  select commission_owed
    into v_current
    from public.staff
   where uid = p_courier_uid
     and role = 'courier'
   for update;
  if not found then
    raise exception 'no such courier' using errcode = 'P0002';
  end if;

  if p_receipt_id is not null
     and exists (select 1 from public.payment_receipts where id = p_receipt_id) then
    return public.record_courier_payment(
      p_courier_uid, p_amount, p_note, p_receipt_id);
  end if;

  -- Null belongs only to a pending attempt written by an older APK. It keeps the old
  -- reconciliation path alive; every new attempt sends a figure and gets this guard.
  if p_expected_balance is not null
     and v_current is distinct from p_expected_balance then
    raise exception 'courier balance changed' using errcode = 'P0001';
  end if;

  return public.record_courier_payment(
    p_courier_uid, p_amount, p_note, p_receipt_id);
end;
$fn$;

revoke execute on function public.record_courier_payment(uuid, integer, text, uuid, integer)
  from public, anon;
grant execute on function public.record_courier_payment(uuid, integer, text, uuid, integer)
  to authenticated, service_role;
