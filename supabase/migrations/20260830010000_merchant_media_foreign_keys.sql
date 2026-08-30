-- The merchant's pictures get the foreign keys they never had.
--
-- `merchants.logo_media_id` and `cover_media_id` have been plain `uuid` columns since the
-- first schema — no reference, no constraint. `cuisines.media_id` got
-- `references media on delete set null` when it was added and the customer's home has
-- drawn cuisine pictures ever since; the merchant's own photograph never could.
--
-- What that cost, and it is the whole of the bug: PostgREST embeds a related row only
-- across a declared foreign key. Without one, `cover:cover_media_id(url, status)` is not
-- a slow query or an empty result — it is `PGRST200`, "could not find a relationship",
-- and the entire merchants query fails. So the customer app could not fetch a merchant's
-- picture at all, and `merchant_card.dart` passed `LuqmaImage(url: null)` because there
-- was nothing else it could pass. A merchant uploaded a cover, an admin approved it in
-- the moderation queue, and every card in the city went on drawing the tinted placeholder.
--
-- `on delete set null`, matching cuisines: a picture removed from the library leaves the
-- merchant without one, rather than taking the shop down with it. That is also what keeps
-- `sweep_orphan_media` honest — it deletes media nothing points at, and with the
-- constraint in place "nothing points at it" is a fact the database enforces rather than
-- a condition the sweep has to get right on its own.

alter table merchants
  add constraint merchants_logo_media_id_fkey
  foreign key (logo_media_id) references media (id) on delete set null;

alter table merchants
  add constraint merchants_cover_media_id_fkey
  foreign key (cover_media_id) references media (id) on delete set null;

-- Both columns are looked up by the sweep and now by every merchant read, and a foreign
-- key does not index the referencing side on its own.
create index if not exists merchants_logo_media_idx
  on merchants (logo_media_id) where logo_media_id is not null;
create index if not exists merchants_cover_media_idx
  on merchants (cover_media_id) where cover_media_id is not null;
