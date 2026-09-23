-- A platform courier reads the platform orders they could still carry (A11).
--
-- `read_orders` lets a courier read what `is_courier_for_order` says is theirs, and for a
-- platform courier that included every platform order with nobody's name on it — with no
-- limit on status or age. A rider could list months of cancelled and escalated orders,
-- each with a customer's name, phone, street and notes. The pool a rider picks from is
-- the live one: placed, accepted, preparing. Once a platform order has finished or been
-- escalated without them, it is none of theirs.
--
-- Narrowed on the unclaimed *platform* branch only. A rider's own orders stay readable
-- whatever their status, because the statement and the queue's replay check are built
-- from them; and a shop's own orders are left exactly as they were, because a shop's
-- rider may deliver one that went out with nobody's name on it and must still be able to
-- read it back.
--
-- The rest of the policy is `20260905000000`'s, unchanged.

drop policy read_orders on public.orders;
create policy read_orders on public.orders for select to authenticated
  using (public.is_admin()
         or customer_uid = auth.uid()
         or public.belongs_to_merchant(merchant_id)
         or (public.is_courier_for_order(courier_uid, merchant_id, delivery_by)
             and (courier_uid is not null
                  or delivery_by is distinct from 'platform'
                  or status in ('placed', 'accepted', 'preparing'))));
