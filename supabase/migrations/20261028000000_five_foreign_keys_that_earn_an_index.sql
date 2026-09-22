-- L-03: five foreign keys that earn an index, out of twenty-one that lack one.
--
-- Postgres indexes the *referenced* side of a foreign key automatically — it has to, it is
-- a unique constraint — and never the referencing side. So deleting a parent row scans the
-- child table whole to enforce the key, and twenty-one foreign keys in this schema have no
-- index that starts with their columns (`tool/fk-index-audit.mjs` lists them).
--
-- Indexing all twenty-one would be the mistake the finding itself warns against: every
-- index is a write on every insert into that table, paid for ever, and most of these are
-- on tables that will hold tens of rows for the life of the product. A foreign key on
-- `dismissed_landmark_suggestions` is not worth a byte.
--
-- The rule used here, and it is the whole of the reasoning:
--
--   **index the key when the child table grows without bound AND the parent is deleted by
--   a path somebody is waiting on.**
--
-- Both halves are needed. A big table nobody deletes a parent from does not care; a
-- frequent delete against a table of twelve rows is instant either way.
--
-- What is deliberately NOT indexed, with the reason: `staff_applications` (three keys),
-- `courier_merchants.attached_by`, `merchants.landmark_id`, `subscription_requests` (four),
-- `payment_receipts` (three), `commission_payments.recorded_by`,
-- `courier_commission_payments.recorded_by`, `dismissed_landmark_suggestions.dismissed_by`,
-- `item_ratings.merchant_id`. Every one of those is either a table that stays small for
-- the life of a city, or a column read only inside a policy predicate — where the row is
-- already in hand and an index buys nothing.
--
-- The plan measured for M-12 is the evidence for the other half of this rule: the
-- merchants-list count needed no new index because `orders_merchant_status_idx` leads with
-- `merchant_id`, and the planner used it. An index is earned, not assumed.

-- The fastest-growing table in the product: one row per device, per app, per day. A
-- thousand customers is roughly a hundred and thirty thousand rows a year.
--
-- `uid` is `on delete set null`, so **every account deletion scans it whole** — and that
-- deletion is `delete_my_account`, which a customer triggers from their phone and then
-- waits in front of. Google Play requires that button to exist; nothing requires it to be
-- fast, but a customer watching a spinner decides the app is broken.
create index if not exists app_opens_uid_idx
  on public.app_opens (uid)
  where uid is not null;

-- Grows with every notification the product sends, and keeps its sent history — that is
-- what the partial index on the unsent rows exists to work around. Scanned by the same
-- account deletion.
create index if not exists push_outbox_uid_idx on public.push_outbox (uid);

-- One row per rated dish, so it grows with orders rather than with shops. Scanned when a
-- customer deletes their account.
--
-- `merchant_id` on this table is deliberately left alone: it appears only in the RLS
-- policy, where the row is already being examined and an index on it changes nothing.
create index if not exists item_ratings_customer_idx
  on public.item_ratings (customer_uid)
  where customer_uid is not null;

-- These two are for the nightly sweep rather than for a person. `sweep_orphan_media` asks
-- `not exists (select 1 from menu_items where media_id = m.id)` — and the same of
-- `daily_meals` — once per candidate image. `menu_items` holds the six hundred dishes the
-- owner types in by hand, and `daily_meals` gains rows every day a kitchen cooks.
--
-- They are also the two `media_id` columns that took until 2026-08-30 to get a foreign key
-- at all, which is why they are the two easiest to forget.
create index if not exists menu_items_media_idx
  on public.menu_items (media_id)
  where media_id is not null;

create index if not exists daily_meals_media_idx
  on public.daily_meals (media_id)
  where media_id is not null;
