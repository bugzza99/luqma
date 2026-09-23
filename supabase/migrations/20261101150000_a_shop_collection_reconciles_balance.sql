-- The balance an admin collects a shop's commission against must still be the balance on
-- the row (D8) — the rule M-10 gave the courier's collection, given to the shop's.
--
-- Two admins, or one admin on two devices, both read «المستحق 200 ج», minted different
-- receipts and both recorded 200. Each call was valid; the row lock merely applied them
-- one after the other, and the shop went 200 into credit that neither of them meant.
--
-- The five-argument overload carries the balance the collection dialog opened on, and
-- checks it under the same merchant-row lock the payment takes. A receipt already on file
-- wins before the check: a retry after a lost reply must reconcile the first payment, not
-- be refused because that payment is what moved the balance. The four-argument function
-- is untouched, so an APK already on a phone keeps working as it did.

create or replace function public.record_commission_payment(
  p_merchant_id       uuid,
  p_amount            integer,
  p_note              text,
  p_client_payment_id uuid,
  p_expected_owed     integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
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
$fn$;

revoke execute on function public.record_commission_payment(uuid, integer, text, uuid, integer)
  from public, anon;
grant execute on function public.record_commission_payment(uuid, integer, text, uuid, integer)
  to authenticated, service_role;
