-- L5: a courier could read every account under their shop.
--
-- Recorded as a debt in the first audit and left alone because RLS cannot be argued with
-- on PGlite, so the change would have shipped unverified. The stack-backed suite exists
-- now, and this is the pass that was waited for.
--
-- The policy read `belongs_to_merchant`, which is true for an owner **and** for their
-- courier — they carry the same merchant on the token. That is the same distinction the
-- first audit found in the order rules and again in the menu rules: *belongs to* is not
-- *runs*. A courier manages nobody; their own row is the whole of what they need, and
-- the roster would have handed them the owner's phone number and every other rider's.
--
-- `is_merchant_owner` is the half that means "runs this shop". `uid = auth.uid()` above
-- it already gives everyone their own record, which is what the courier actually reads.
--
-- Nothing loses a screen: only AdminApp reads the list today, as a platform admin. What
-- this leaves open is the right door for a merchant's own "my couriers" screen later —
-- owner only, by construction.
drop policy if exists read_staff on staff;

create policy read_staff on staff for select to authenticated
  using (public.is_admin()
         or uid = auth.uid()
         or public.is_merchant_owner(merchant_id));
