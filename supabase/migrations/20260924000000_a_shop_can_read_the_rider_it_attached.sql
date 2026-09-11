-- A shop could attach a rider and then not read their name.
--
-- `read_staff` lets an owner see the accounts whose **`staff.merchant_id`** is their shop.
-- That column is a scalar and holds one shop, so a rider who works for the koshari place
-- and was attached to the fish place is, to the fish place, an attachment row with nobody
-- on it: no name, no telephone number. Which is the roster screen drawing a blank line for
-- exactly the riders `courier_merchants` was built for, and the shop unable to ring the
-- person carrying its food.
--
-- The attachment is the grant. A shop reads the staff row of a courier on **its own
-- roster**, and no further — this is not a directory, and an owner still cannot see a
-- rider who works for somebody else and not for them.
create or replace function public.owner_of_rosters_courier(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
      from public.courier_merchants cm
     where cm.courier_uid = p_uid
       and cm.is_active
       and cm.merchant_id is not null
       and public.is_merchant_owner(cm.merchant_id)
  );
$fn$;

-- `security definer` and not otherwise. This is called from a policy **on `staff`**, and
-- its own lookup goes to `courier_merchants`, whose read policy calls `is_merchant_owner`
-- — which reads `is_active_staff`, which reads `staff`. Left as invoker the subquery would
-- be filtered by the very policy it is helping to evaluate, and the answer would be a
-- quiet false for some callers and not others. The same shape as `is_active_staff` and
-- `courier_carries`, and for the same reason.
revoke execute on function public.owner_of_rosters_courier(uuid) from public, anon;
grant execute on function public.owner_of_rosters_courier(uuid)
  to authenticated, service_role;

drop policy read_staff on public.staff;
create policy read_staff on public.staff for select to authenticated
  using (public.is_admin()
         or uid = (select auth.uid())
         or public.is_merchant_owner(merchant_id)
         or public.owner_of_rosters_courier(uid));
