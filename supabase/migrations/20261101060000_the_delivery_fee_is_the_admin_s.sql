-- What a delivery costs is the admin's to set, not the shop's (A12).
--
-- `delivery_fee_override` was on the list of columns a shop owner may write (last set in
-- `20260929000000_merchant_review_boundaries.sql`). A shop whose orders the platform's
-- riders carry could PATCH it to zero: the rider delivered for nothing, and the
-- platform's cut — a share of that very fee — was zero too. CLAUDE.md settled that the
-- zone, the delivery fee and the plan stay the owner's to settle, and the owner confirmed
-- it on 2026-09-23. No screen in MerchantApp ever offered the field, so nothing a shop can
-- do today changes; an admin is unaffected, as `guard_columns` steps aside for one.
--
-- The list is otherwise exactly the one `20260929000000` set.

drop trigger merchants_guard_columns on public.merchants;
create trigger merchants_guard_columns before update on public.merchants for each row
  execute function public.guard_columns(
    '{name,phone,description,logo_media_id,cover_media_id,opening_hours,paused_until,min_order,prep_minutes,landmark_id,landmark_name,street,lat,lng}');
