-- The last two picture columns that could not be joined.
--
-- `merchants.logo_media_id` and `cover_media_id` were plain uuids with no reference to
-- `media` until 2026-08-30, and the consequence was not a slow query — it was `PGRST200`
-- on the whole merchants read, so every shop in the city drew the tinted placeholder
-- while the bucket, the upload, the moderation queue and the approval all worked
-- perfectly.
--
-- `menu_items` and `daily_meals` are the same column with the same omission, and they are
-- the two that matter most to a customer: the dish and the meal are the things being
-- sold. Six hundred photographs the owner is about to shoot personally have nowhere to
-- arrive without these.
--
-- `on delete set null` throughout, matching the four that already have it: deleting a
-- rejected image should leave the dish on the menu without its photograph, never take
-- the dish with it.
alter table menu_items add constraint menu_items_media_id_fkey
  foreign key (media_id) references media (id) on delete set null;

alter table daily_meals add constraint daily_meals_media_id_fkey
  foreign key (media_id) references media (id) on delete set null;
