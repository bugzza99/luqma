-- Luqma — the schema.
--
-- Ported from the sixteen Firestore collections in `docs/01-data-model.md`, under the
-- decisions in `docs/17-supabase-migration.md`: snake_case columns, uuid keys, money as
-- integer piastres, statuses as text with a CHECK rather than a Postgres enum, and
-- `jsonb` only where the value is a frozen copy or is always read whole.
--
-- Row level security is deliberately NOT here. It is stage S1 and it gets its own file
-- and its own tests, because it is the boundary and it deserves to be read on its own.

-- ---------------------------------------------------------------- helpers

-- `gen_random_uuid()` is core Postgres since 13 and needs no extension. Requiring
-- pgcrypto here would be a dependency bought for a function the server already has.

-- Every table carries created_at/updated_at, and nothing is trusted to remember to
-- touch the second one.
create or replace function set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------- geography

create table cities (
  id          text primary key,
  name        text not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table zones (
  id                    uuid primary key default gen_random_uuid(),
  city_id               text not null references cities on delete restrict,
  name                  text not null,
  -- Piastres. Zones are the addressing primitive here: map accuracy in Edku is poor
  -- enough that a named zone beats a pin, and the fee follows the zone.
  default_delivery_fee  integer not null default 0 check (default_delivery_fee >= 0),
  is_active             boolean not null default true,
  sort_order            integer not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);
create index zones_city_idx on zones (city_id, sort_order);

create table landmarks (
  id          uuid primary key default gen_random_uuid(),
  city_id     text not null references cities on delete restrict,
  zone_id     uuid not null references zones on delete restrict,
  name        text not null,
  icon        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index landmarks_city_idx on landmarks (city_id);
create index landmarks_zone_idx on landmarks (zone_id);

-- ---------------------------------------------------------------- people

-- One row per customer, keyed by the auth account. The columns a customer may edit and
-- the columns describing how the platform sees them live side by side; RLS in S1 is what
-- keeps the second set out of their hands.
create table users (
  id                     uuid primary key references auth.users on delete cascade,
  name                   text,
  phone                  text,
  is_blocked             boolean not null default false,
  -- Written by the server only. A client that can reset its own refusal count makes the
  -- whole abuse defence decorative.
  rejected_orders_count  integer not null default 0 check (rejected_orders_count >= 0),
  fcm_tokens             text[] not null default '{}',
  default_address_id     uuid,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create table addresses (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references users on delete cascade,
  zone_id        uuid not null references zones on delete restrict,
  landmark_id    uuid references landmarks on delete set null,
  -- Copied beside the reference on purpose: a landmark renamed next month must not
  -- rewrite the address somebody saved today.
  landmark_name  text,
  landmark_note  text,
  street         text,
  building       text,
  floor          text,
  apartment      text,
  label          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index addresses_user_idx on addresses (user_id);

alter table users
  add constraint users_default_address_fk
  foreign key (default_address_id) references addresses on delete set null;

-- ---------------------------------------------------------------- supply

create table merchants (
  id                     uuid primary key default gen_random_uuid(),
  city_id                text not null references cities on delete restrict,
  type                   text not null check (type in ('restaurant', 'homeKitchen')),
  name                   text not null,
  zone_id                uuid not null references zones on delete restrict,
  phone                  text not null,
  status                 text not null default 'pending'
                           check (status in ('pending', 'approved', 'suspended')),
  -- Read whole and interpreted in Dart by `acceptsOrdersAt`; never queried into.
  opening_hours          jsonb not null default '[]'::jsonb,
  -- A timestamp rather than a boolean: a merchant who taps "busy" during a rush recovers
  -- by themselves, where a flag leaves shops shut for days and support calls behind them.
  paused_until           timestamptz,
  logo_media_id          uuid,
  cover_media_id         uuid,
  delivers_self          boolean not null default true,
  owner_uid              uuid references auth.users on delete set null,
  plan_id                text,
  revenue_model          text not null default 'subscription'
                           check (revenue_model in ('subscription', 'commission', 'prepaid')),
  -- Basis points under commission, piastres per order under prepaid, meaningless under a
  -- subscription. Never the wallet — that is `wallet_balance`, and two fields meaning the
  -- same thing is how they come to disagree.
  revenue_value          integer not null default 0 check (revenue_value >= 0),
  wallet_balance         integer not null default 0,
  commission_owed        integer not null default 0,
  -- Mirrored from Remote Config, and enforced here as well: clamping only in the app
  -- leaves the real limit to whoever is holding the phone.
  delivery_fee_override  integer
                           check (delivery_fee_override is null
                                  or delivery_fee_override = 0
                                  or delivery_fee_override between 500 and 2000),
  min_order              integer not null default 0 check (min_order >= 0),
  rating_avg             numeric(3,2) not null default 0 check (rating_avg between 0 and 5),
  rating_count           integer not null default 0 check (rating_count >= 0),
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);
create index merchants_city_status_idx on merchants (city_id, status);
create index merchants_owner_idx on merchants (owner_uid);

-- Its own table rather than an array on the merchant: menu items point at it and the
-- admin reorders it, so it has a life of its own.
create table menu_categories (
  id          uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants on delete cascade,
  name        text not null,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index menu_categories_merchant_idx on menu_categories (merchant_id, sort_order);

-- A relationship, queried from both ends, so a table rather than an array.
create table merchant_served_zones (
  merchant_id uuid not null references merchants on delete cascade,
  zone_id     uuid not null references zones on delete cascade,
  primary key (merchant_id, zone_id)
);
create index merchant_served_zones_zone_idx on merchant_served_zones (zone_id);

create table menu_items (
  id           uuid primary key default gen_random_uuid(),
  merchant_id  uuid not null references merchants on delete cascade,
  category_id  uuid references menu_categories on delete set null,
  name         text not null,
  description  text,
  price        integer not null check (price >= 0),
  media_id     uuid,
  is_available boolean not null default true,
  -- Read whole with the item, always.
  options      jsonb not null default '[]'::jsonb,
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index menu_items_merchant_idx on menu_items (merchant_id, sort_order);

create table daily_meals (
  id                   uuid primary key default gen_random_uuid(),
  merchant_id          uuid not null references merchants on delete cascade,
  city_id              text not null references cities on delete restrict,
  name                 text not null,
  description          text,
  media_id             uuid,
  price                integer not null check (price >= 0),
  -- A real date. The `yyyy-MM-dd` day-key rule existed because equality against a
  -- Firestore timestamp matches one microsecond; the type does that natively here.
  date                 date not null,
  total_qty            integer not null check (total_qty >= 0),
  -- The whole reason this table exists. The constraint is half of it; the other half is
  -- that only the order function may move it, in the same transaction as the order.
  remaining_qty        integer not null check (remaining_qty >= 0),
  pickup_window_start  integer not null check (pickup_window_start between 0 and 1440),
  pickup_window_end    integer not null check (pickup_window_end between 0 and 1440),
  delivery_option      text not null default 'pickup'
                         check (delivery_option in ('pickup', 'platformCourier',
                                                    'sellerArrangement')),
  status               text not null default 'draft'
                         check (status in ('draft', 'published', 'closed')),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint daily_meals_remaining_within_total check (remaining_qty <= total_qty),
  constraint daily_meals_window_ordered check (pickup_window_end > pickup_window_start)
);
create index daily_meals_city_date_idx on daily_meals (city_id, date, status);
create index daily_meals_merchant_idx on daily_meals (merchant_id, date);

-- ---------------------------------------------------------------- media

-- One table for every image in the product, so the moderation gate has exactly one door.
create table media (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null check (kind in ('merchantLogo', 'merchantCover', 'menuItem',
                                            'dailyMeal', 'promotion')),
  url         text not null,
  thumb_url   text,
  status      text not null default 'pending'
                check (status in ('pending', 'approved', 'rejected')),
  owner_id    uuid,
  uploaded_by uuid references auth.users on delete set null,
  width       integer not null default 0 check (width >= 0),
  height      integer not null default 0 check (height >= 0),
  bytes       integer not null default 0 check (bytes >= 0),
  reviewed_by uuid references auth.users on delete set null,
  review_note text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index media_status_idx on media (status, created_at);
create index media_uploader_idx on media (uploaded_by);

-- ---------------------------------------------------------------- demand

-- Shown to customers, so it is a number a person can read back down a phone line rather
-- than a uuid.
create sequence order_number_seq start 1000;

create table orders (
  id                uuid primary key default gen_random_uuid(),
  city_id           text not null references cities on delete restrict,
  order_number      bigint not null unique default nextval('order_number_seq'),

  customer_uid      uuid not null references auth.users on delete restrict,
  -- Copied at order time, like everything else here that decides responsibility.
  customer_name     text not null,
  customer_phone    text not null,
  is_new_customer   boolean not null default false,

  -- `restrict`, deliberately: this is what makes "a merchant with orders cannot be
  -- deleted" a fact rather than a check the app remembers to make. A merchant added by
  -- mistake, before it ever traded, still deletes cleanly.
  merchant_id       uuid not null references merchants on delete restrict,
  merchant_name     text not null,

  zone_id           uuid not null references zones on delete restrict,
  -- A copy, not a reference. A courier cannot read another person's addresses, so a
  -- reference would render as nothing in the street; and an address corrected next month
  -- must not rewrite where last week's order went.
  address           jsonb,
  delivery_by       text not null default 'merchant'
                      check (delivery_by in ('merchant', 'platform')),

  type              text not null check (type in ('instant', 'preorder')),
  -- Frozen at order time. Never queried into, never edited: a menu that changes tomorrow
  -- must not rewrite what somebody ordered today.
  items             jsonb not null,
  pricing           jsonb not null,
  -- The revenue terms in force when the order was placed, so moving a merchant to
  -- commission next month changes future orders and never rewrites what was agreed.
  revenue           jsonb,

  status            text not null default 'placed'
                      check (status in ('placed', 'accepted', 'preparing', 'outForDelivery',
                                        'delivered', 'cancelled', 'needsAttention')),
  status_history    jsonb not null default '[]'::jsonb,

  daily_meal_id     uuid references daily_meals on delete restrict,
  coupon_code       text,
  courier_uid       uuid references auth.users on delete set null,
  cancel_reason     text,
  cancelled_by      text check (cancelled_by is null
                                or cancelled_by in ('customer', 'merchant', 'courier',
                                                    'admin', 'system')),
  prep_minutes      integer check (prep_minutes is null or prep_minutes >= 0),

  placed_at         timestamptz not null default now(),
  -- Instant orders only. A pre-order is dated and collected in a window, and a countdown
  -- on one is a countdown to nothing.
  accept_deadline_at timestamptz,
  delivered_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint orders_preorder_has_no_deadline
    check (type <> 'preorder' or accept_deadline_at is null)
);
create index orders_merchant_status_idx on orders (merchant_id, status, placed_at desc);
create index orders_customer_idx on orders (customer_uid, placed_at desc);
create index orders_courier_idx on orders (courier_uid) where courier_uid is not null;
create index orders_platform_queue_idx on orders (city_id, delivery_by, status)
  where delivery_by = 'platform';

create table order_issues (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references orders on delete cascade,
  customer_uid uuid not null references auth.users on delete cascade,
  merchant_id  uuid not null references merchants on delete cascade,
  reason       text not null,
  status       text not null default 'open' check (status in ('open', 'closed')),
  admin_note   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index order_issues_status_idx on order_issues (status, created_at);
create index order_issues_merchant_idx on order_issues (merchant_id);

-- Keyed by the order, which is what makes "one rating per order" structural rather than
-- a rule somebody has to enforce: rating again corrects the first instead of moving a
-- merchant's average a second time.
create table ratings (
  order_id          uuid primary key references orders on delete cascade,
  merchant_id       uuid not null references merchants on delete cascade,
  customer_uid      uuid not null references auth.users on delete cascade,
  stars             smallint not null check (stars between 1 and 5),
  comment           text,
  is_comment_public boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index ratings_merchant_idx on ratings (merchant_id, created_at desc);

-- ---------------------------------------------------------------- money

-- A natural key: the engine reads `'free'` by name, and a uuid would make every plan
-- comparison a join.
create table plans (
  id            text primary key,
  name          text not null,
  price_monthly integer not null default 0 check (price_monthly >= 0),
  features      jsonb not null default '{}'::jsonb,
  sort_order    integer not null default 0,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table merchants
  add constraint merchants_plan_fk foreign key (plan_id) references plans on delete set null;

create table subscriptions (
  id          uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references merchants on delete cascade,
  plan_id     text not null references plans on delete restrict,
  amount      integer not null check (amount >= 0),
  started_at  timestamptz not null,
  expires_at  timestamptz not null,
  -- The nightly pass's only memory of itself. Without it the same expired term returns
  -- every night, with a fresh audit entry each time.
  settled_at  timestamptz,
  recorded_by uuid references auth.users on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint subscriptions_term_ordered check (expires_at > started_at)
);
create index subscriptions_merchant_idx on subscriptions (merchant_id, expires_at desc);
-- What the nightly pass actually reads: unsettled terms that have run out.
create index subscriptions_due_idx on subscriptions (expires_at) where settled_at is null;

create table promotions (
  id               uuid primary key default gen_random_uuid(),
  city_id          text not null references cities on delete restrict,
  merchant_id      uuid not null references merchants on delete cascade,
  channel          text not null check (channel in ('homeBanner', 'categoryBanner',
                                                    'boost', 'push')),
  status           text not null default 'requested'
                     check (status in ('requested', 'approved', 'active', 'rejected',
                                       'ended')),
  render_mode      text not null default 'text'
                     check (render_mode in ('text', 'image', 'imageWithText')),
  title            text not null default '',
  body             text not null default '',
  media_id         uuid references media on delete set null,
  section_key      text,
  category_id      uuid references menu_categories on delete set null,
  -- Membership only, and an empty array means the whole city — which says it more
  -- plainly than a missing join row would.
  zone_ids         uuid[] not null default '{}',
  start_at         timestamptz not null,
  end_at           timestamptz not null,
  priority         integer not null default 0,
  price            integer not null default 0 check (price >= 0),
  requested_by     uuid not null references auth.users on delete restrict,
  approved_by      uuid references auth.users on delete set null,
  rejection_reason text,
  impressions      integer not null default 0 check (impressions >= 0),
  clicks           integer not null default 0 check (clicks >= 0),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint promotions_run_ordered check (end_at > start_at),
  -- A banner promising an image and carrying none renders as a broken box on the home
  -- screen of every customer in the city.
  constraint promotions_image_has_media
    check (render_mode = 'text' or media_id is not null),
  -- A refusal with no reason gives the merchant nothing to fix, and guarantees they ask
  -- again with the same thing.
  constraint promotions_rejection_has_reason
    check (status <> 'rejected' or nullif(btrim(rejection_reason), '') is not null)
);
create index promotions_city_status_idx on promotions (city_id, status, priority desc);
create index promotions_merchant_idx on promotions (merchant_id, start_at desc);

create table coupons (
  id              uuid primary key default gen_random_uuid(),
  code            text not null,
  city_id         text not null references cities on delete restrict,
  type            text not null check (type in ('percentage', 'fixedAmount', 'freeDelivery')),
  -- Basis points for a percentage, piastres for a fixed amount.
  value           integer not null check (value >= 0),
  max_discount    integer check (max_discount is null or max_discount >= 0),
  min_order       integer not null default 0 check (min_order >= 0),
  merchant_id     uuid references merchants on delete cascade,
  first_order_only boolean not null default false,
  per_user_limit  integer not null default 0 check (per_user_limit >= 0),
  total_limit     integer not null default 0 check (total_limit >= 0),
  used_count      integer not null default 0 check (used_count >= 0),
  is_active       boolean not null default true,
  funded_by       text not null default 'merchant' check (funded_by in ('merchant', 'platform')),
  valid_from      timestamptz,
  valid_until     timestamptz,
  created_by      uuid references auth.users on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- Uncapped, a 15% code on a 2000 EGP order costs the merchant 300 against the 30 they
  -- had in mind. This was a check inside `evaluate`; here it cannot be written at all.
  constraint coupons_percentage_is_capped
    check (type <> 'percentage' or max_discount is not null),
  constraint coupons_valid_window check (valid_until is null or valid_from is null
                                         or valid_until > valid_from)
);
create unique index coupons_code_idx on coupons (city_id, upper(code));

create table coupon_redemptions (
  id           uuid primary key default gen_random_uuid(),
  coupon_id    uuid not null references coupons on delete cascade,
  order_id     uuid not null references orders on delete cascade,
  customer_uid uuid not null references auth.users on delete cascade,
  created_at   timestamptz not null default now(),
  -- One code per order, never two.
  unique (order_id)
);
create index coupon_redemptions_user_idx on coupon_redemptions (coupon_id, customer_uid);

-- ---------------------------------------------------------------- staff

create table staff (
  uid         uuid primary key references auth.users on delete cascade,
  scope       text not null check (scope in ('platform', 'merchant')),
  role        text not null check (role in ('admin', 'moderator', 'owner', 'courier')),
  merchant_id uuid references merchants on delete cascade,
  name        text,
  phone       text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- A merchant-scope account without a merchant is an account that can act for nobody;
  -- a platform-scope account with one is an admin quietly bound to a single shop.
  constraint staff_scope_matches_merchant
    check ((scope = 'merchant') = (merchant_id is not null))
);
create index staff_merchant_idx on staff (merchant_id);

-- ---------------------------------------------------------------- control plane

-- What `RemoteConfigService` used to fetch. A table rather than a product: a change
-- reaches a phone at once instead of at the next fetch interval, and `LuqmaConfig` keeps
-- validating every key exactly as it does now.
create table config (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now()
);

create table home_sections (
  key         text not null,
  city_id     text references cities on delete cascade,
  type        text not null,
  title_ar    text not null default '',
  sort_order  integer not null default 0,
  is_visible  boolean not null default true,
  -- Untyped by design: the section registry in the app interprets it, and the registry
  -- is a fixed map of builders. Dynamic means values and ordering, never server-driven UI.
  params      jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  primary key (key, city_id)
);
create index home_sections_city_idx on home_sections (city_id, sort_order);

-- Append-only, including for an admin. A log its own subject can edit proves nothing.
create table audit_log (
  id          uuid primary key default gen_random_uuid(),
  action      text not null,
  actor       uuid references auth.users on delete set null,
  merchant_id uuid references merchants on delete set null,
  detail      jsonb not null default '{}'::jsonb,
  at          timestamptz not null default now()
);
create index audit_log_at_idx on audit_log (at desc);
create index audit_log_merchant_idx on audit_log (merchant_id, at desc);

-- ---------------------------------------------------------------- updated_at

do $$
declare t text;
begin
  foreach t in array array[
    'cities', 'zones', 'landmarks', 'users', 'addresses', 'merchants', 'menu_categories',
    'menu_items', 'daily_meals', 'media', 'orders', 'order_issues', 'ratings', 'plans',
    'subscriptions', 'promotions', 'coupons', 'staff', 'home_sections'
  ]
  loop
    execute format(
      'create trigger %I_set_updated_at before update on %I
         for each row execute function set_updated_at()', t, t);
  end loop;
end;
$$;
