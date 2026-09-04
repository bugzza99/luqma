# Build Order

> **Written for the Firebase backend, which is gone.** The product decisions in this
> document still stand — they were argued through with the owner and none of them were
> reversed by the move. What is stale is the *machinery*: Firestore collections are
> Postgres tables, security rules are RLS policies, Cloud Functions are Postgres
> functions and `pg_cron` jobs, and Firebase Auth is GoTrue. Read
> `docs/17-supabase-migration.md` for the mapping and `CLAUDE.md` for what is true today;
> where this file and those two disagree, they win.

Nine phases, each producing something usable and unblocking the next.
The unusual choice is building AdminApp before CustomerApp: the owner enters all merchant data
personally, so data entry must exist before there is anything to browse.

Trust features are no longer a separate late phase. Ratings, issue tickets and rejection
counting each belong to the flow that creates them, and deferring them meant building the
order flow twice.

## Phase 0 — Brand foundation
The mark and the Lemonada wordmark converted to outlines and refined, exported as
`app_icon.svg`, `logo_mark.svg`, `logo_lockup_horizontal.svg` and `logo_lockup_stacked.svg`,
plus the `LuqmaLockup` widget that renders them. Colour tokens including the derived
`priceStrong` and `borderStrong`, the verified dark theme, the typography scale, the single
continuous splash, and launcher icons at every density.
Everything downstream renders through these.

## Phase 1 — luqma_core
Firebase project, models, repositories, `RemoteConfigService` with compiled-in defaults,
theme, RTL localization scaffolding, Security Rules skeleton, the `media` upload and
compression trigger, and the shared `MenuEditor` and `AddressPicker` components.
Building the two shared components here is what stops AdminApp and MerchantApp from growing
two menu editors.

## Phase 2 — AdminApp minimum
Auth with custom claims, cities, zones, landmarks, merchant CRUD, menu entry on behalf of
merchants, the media queue. Ends with real Edku data in the database.

Also here, and not in the original plan: the landmark suggestion queue. Nobody can write
Edku's landmark list in advance, so it is grown from the notes customers type when the
list does not have theirs — every such note is a place a courier has already had to be
told about.

**`staff` management moved out of this phase.** Creating a staff account means creating an
auth user, which only a server can do, which meant Cloud Functions, which meant Blaze.
Everything else in AdminApp worked on the free tier; this one thing did not, and building
half a screen whose main action is disabled would have been worse than waiting.

> **Settled since.** The migration removed the blocker — the account is minted by the
> `create-staff-account` Edge Function, which verifies the caller's JWT and checks that
> their `staff` row is an active platform admin before the service role touches anything.
> `apps/admin_app/lib/src/staff/staff_screen.dart` is the screen it was waiting for.

## Phase 3 — CustomerApp core
Google Sign-In, home rendered from `homeSections`, merchant and item browsing, cart,
zone-based address flow, cash checkout, order tracking, order history, **the issue ticket
button, and the rating prompt after delivery**.

## Phase 4 — MerchantApp core
Order inbox with the critical repeating-sound notification, accept and reject, status
transitions, the `pausedUntil` busy toggle, menu editing, the accept-deadline task,
**rejection counting and auto-block**, and private rating feedback.

## Phase 5 — Courier mode
Courier `staff` accounts, merchant scope and platform scope, minimal delivery screen,
Google Maps intent hand-off, cash collection amount.

## Phase 6 — Home kitchens
Seller vetting flow, `dailyMeals`, transactional quantity reservation, pre-order checkout,
the prominent home-screen section, fulfilment options.

## Phase 7 — Monetization
`plans`, `subscriptions`, `RevenueEngine` with the per-merchant switch, the `revenueSnapshot`,
and the `subscription` and `commission` branches. Cash payment recording, `dailyMaintenance`.
The `prepaid` branch is a stub behind the same switch until online payment exists.

## Phase 8 — Promotions and dynamic home
`promotions` across all four channels, boost ranking, the AdminApp home builder and promotion
queue, the weekly push cap. AdMob integrated behind its flag.

## Phase 9 — Hardening and launch
Force-update, analytics, crash reporting, OTP behind its flag, the public-comments flag,
the rating display threshold, Play Store listing, and onboarding of the first 10–15 merchants
at zero commission.
