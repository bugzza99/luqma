-- Indexes on the foreign keys, which Postgres does not create for you.
--
-- Twenty-two of them had none. Without one, a JOIN across the key is a sequential scan,
-- and so is every `on delete cascade` and every `on delete restrict` check — the second
-- of which runs on *every* attempt to delete a parent row, whether or not it succeeds.
--
-- At Edku's size the tables are small and none of this is felt today. It is here anyway
-- because the fix is one line each and the cost of not having it only ever grows, and
-- because "we will add indexes when it hurts" means adding them while it hurts.
--
-- Named for the column rather than the constraint, so the next person grepping for
-- `merchant_id` finds them.

-- ---------------------------------------------------------------- addressing
create index if not exists addresses_zone_idx      on addresses (zone_id);
create index if not exists addresses_landmark_idx  on addresses (landmark_id);
create index if not exists merchants_zone_idx      on merchants (zone_id);
create index if not exists merchants_plan_idx      on merchants (plan_id);
create index if not exists orders_zone_idx         on orders (zone_id);
-- `users.default_address_id` points back at a row that cascades from the same user, so
-- the check runs on every address delete.
create index if not exists users_default_address_idx on users (default_address_id);

-- ---------------------------------------------------------------- supply
create index if not exists menu_items_category_idx on menu_items (category_id);
create index if not exists orders_daily_meal_idx   on orders (daily_meal_id)
  where daily_meal_id is not null;

-- ---------------------------------------------------------------- people
-- Every one of these is read when an account is deleted, and `auth.users` cascades.
create index if not exists audit_log_actor_idx           on audit_log (actor);
create index if not exists media_reviewer_idx            on media (reviewed_by);
create index if not exists coupons_creator_idx           on coupons (created_by);
create index if not exists subscriptions_recorder_idx    on subscriptions (recorded_by);
create index if not exists promotions_requester_idx      on promotions (requested_by);
create index if not exists promotions_approver_idx       on promotions (approved_by);
create index if not exists ratings_customer_idx          on ratings (customer_uid);
create index if not exists order_issues_customer_idx     on order_issues (customer_uid);
create index if not exists coupon_redemptions_customer_idx
  on coupon_redemptions (customer_uid);

-- ---------------------------------------------------------------- the rest
-- The issues queue joins straight through this one.
create index if not exists order_issues_order_idx      on order_issues (order_id);
create index if not exists coupons_merchant_idx        on coupons (merchant_id)
  where merchant_id is not null;
create index if not exists subscriptions_plan_idx      on subscriptions (plan_id);
create index if not exists promotions_media_idx        on promotions (media_id)
  where media_id is not null;
create index if not exists promotions_category_idx     on promotions (category_id)
  where category_id is not null;
