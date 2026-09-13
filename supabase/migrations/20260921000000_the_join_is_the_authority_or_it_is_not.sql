-- Detaching a courier did not detach them.
--
-- `20260920000000` introduced `courier_merchants` and said the join was the authority on
-- courier access. It was not. `belongs_to_merchant` accepted **either** the token's
-- `merchant_id` claim or the join, and the hook stamps that claim from `staff.merchant_id`
-- for every account regardless of role — so a courier created against a shop carried that
-- shop's id on their token for the life of the session. Switching their attachment off
-- left them reading that shop's orders, with every customer's address and telephone number
-- on them.
--
-- The claim arm was written for owners and quietly served couriers too. It is the owner's
-- now and nobody else's: **a courier is the join and nothing else.**
--
-- Found by the review pass rather than by me. It is the exact failure `CLAUDE.md` already
-- records from the other end — "a dismissal is a boundary change, not a claim change" —
-- arrived at by adding a claim back into a predicate that had just been taught to read a
-- table.
create or replace function public.belongs_to_merchant(m uuid) returns boolean
language sql stable as $fn$
  select m is not null
     and public.is_active_staff()
     and (
       -- An owner, a moderator, an admin acting for a shop: one merchant, from the token.
       (public.staff_role() is distinct from 'courier'
        and public.claim('merchant_id')::uuid = m)
       or public.courier_carries(m)
     );
$fn$;

-- And the delivery identity has to read the same table.
--
-- This still asked the claim whether the caller was the shop's courier, and asked
-- `staff_scope()` whether they were the platform's — both the old scalar shape. So a
-- courier attached to three shops could act on one of them, and a courier holding the
-- platform row could not act on a platform order at all unless their *scope column* also
-- said platform. The predicate that decides who may write `delivered` — the transition
-- that moves money — was reading a field the product had stopped maintaining.
--
-- `is_courier_for` and `is_platform_courier` both read the join now, and
-- `is_platform_courier` still honours the legacy `scope = 'platform'` so an account made
-- before yesterday does not lose the platform today.
create or replace function public.is_courier_for_order(
  p_courier_uid uuid,
  p_merchant_id uuid,
  p_delivery_by text
)
returns boolean
language sql
stable
as $fn$
  select public.is_active_staff()
     and (
       p_courier_uid = (select auth.uid())
       or (
         p_courier_uid is null
         and (
           public.is_courier_for(p_merchant_id)
           or (p_delivery_by = 'platform' and public.is_platform_courier())
         )
       )
     );
$fn$;
