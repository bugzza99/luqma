# لقمة (Luqma)

Local food-ordering marketplace for the city of **Edku** (إدكو), Beheira, Egypt.
Restaurants plus home kitchens. Three Flutter Android apps on one **Supabase** backend.

> **The Firebase → Supabase migration is complete** (see `docs/17-supabase-migration.md`
> and `supabase/migrations/`). Every repository, auth and remote config now run on
> Postgres/GoTrue/Realtime; the `firebase/` and `functions/` directories are gone.
> **Google Sign-In is gone too** — a customer signs in with a phone number and a password,
> so there is no OAuth client, no web client id and no SHA-1 to register. See
> "Customer accounts are a phone number" below.

## The cloud project

**Project `luqma-edku` — ref `vqcivwdoekyfqhfmnuos`, Frankfurt (eu-central-1), free tier.**
Linked from `supabase/`; the dashboard is at
`https://supabase.com/dashboard/project/vqcivwdoekyfqhfmnuos`. The database password is in
`supabase/.temp/db-password.txt` (gitignored) — move it to a password manager.

Production builds are one script, because three dart-defines typed by hand three times is
three chances to drop one — and a dropped one is silent. A build with no
`LUQMA_SENTRY_DSN` reports nothing and looks identical to one that has it:

```
powershell -ExecutionPolicy Bypass -File tool\build-apks.ps1
```

It fetches the anon key from the linked project rather than having it pasted, carries the
Sentry DSN, builds arm64-only split APKs for all three apps, and drops them in `apks/`.
Both values are public by design — the anon key is what every phone carries and RLS is
what protects the data, and a Sentry DSN can only *send* events, never read them.
flutter build apk --dart-define=LUQMA_SUPABASE_URL=https://vqcivwdoekyfqhfmnuos.supabase.co \
  --dart-define=LUQMA_SUPABASE_PUBLISHABLE_KEY=<sb_publishable_..., supabase projects api-keys>
```

Three things the migrations alone cannot carry to a new project — each bit hard:

- **The custom access token hook is config, not schema.**
  `[auth.hook.custom_access_token]` in `supabase/config.toml` copies each staff record
  into the JWT at sign-in; without it every policy that reads a role sees nothing and an
  admin is an ordinary customer. Land it with `supabase --experimental config push`.
- **Realtime publication**: `supabase db push` creates tables but the hosted Realtime
  needs them in `supabase_realtime` (the realtime migrations do this).
- **pg_cron schedules** land in `20260824130000_scheduled_jobs.sql` — verify with
  `select jobname from cron.job` after any restore.

### The test project — `luqma-test`, ref `letdxuiypazbcfxbafab`

**The two suites that need a real Postgres run against their own cloud project, and
Docker is not part of the loop any more.** `luqma-test` is the same region, the same
thirty migrations and the same access-token hook; nothing about it is a reduced copy.

It exists because **both suites are destructive**. One full run leaves roughly thirteen
staff rows, nine auth users, seven merchants, five cities and four orders behind, and
`tool/cleanup-cloud-test-residue.sql` is in this repository because they were once
pointed at `luqma-edku` and somebody had to clean it out by hand afterwards. A suite that
has to be run carefully is a suite that gets run less often.

Credentials live in `supabase/.temp/` (gitignored) and are written by:

```
powershell -ExecutionPolicy Bypass -File tool\setup-cloud-test.ps1 `
    -ProjectRef letdxuiypazbcfxbafab -DbPassword '<the project database password>'
```

After that `tool\run_tests.ps1` runs everything, both cloud suites included. A clone with
no credentials **skips** them and says so in the summary rather than reporting a clean
sweep it did not earn.

A project that has never had the migrations needs `db push` **and** `config push` — the
second is not optional, for the reason in the bullet above: the hook is configuration.

233 live tests and 156 stack tests passed against `luqma-test` on 2026-08-30.


**The design is finished and verified. Read `docs/` before changing anything.**
Those documents are the specification, not notes — every decision in them was argued through
with the owner and cross-checked. If something here seems arbitrary, the reason is written down.

## Status

> **Phases 0–8 below are a record, not instructions.** They were written as each phase
> closed and they describe the product as it stood on Firebase — so "waits on Blaze",
> "Cloud Function" and "Firestore" appear in the present tense throughout. All five of
> those blockers are gone: the migration replaced them with Postgres functions and
> `pg_cron`, and nothing is waiting on a credit card. Read this section for *why* a thing
> is the way it is; read everything from "Infrastructure" down for what is true today.

**Phase 0 done.** Brand tokens, both themes, `LuqmaLockup`, `LuqmaSplash`, generated logo
assets and the Android resource tree.

**Phase 1 in progress.** Done and verified:

- `Result` / `Failure` — repositories return a classified failure instead of throwing, so
  offline, permission-denied and conflict reach the customer as three different sentences.
- Models: `Merchant` (with the derived `acceptsOrdersAt`), `Order`, `OrderPricing`,
  `Coupon`, `Zone`, `Landmark`, `Address`, `City`. Money is **integer piastres** everywhere.
- `MerchantRepository` — interface, Firestore implementation, and a fake that re-applies
  the same visibility rules and can be told to fail.
- `LuqmaConfig` — compiled-in defaults, with out-of-range remote values rejected per key.
- Firestore security rules, with 34 emulator tests.
- Arabic localization with all six plural categories.

- Riverpod providers, code-generated, with the repository seam proven by tests that
  never touch Firebase.
- `AddressPicker` — zone, then landmark, then detail.
- The media pipeline: `planMediaProcessing` and the `onMediaUploaded` Storage trigger,
  plus Storage rules.

- `RemoteConfigService` — the single path from AdminApp to a phone. Never throws; a
  failed fetch keeps the last good values rather than reverting to what shipped months ago.
- `MenuEditor`, shared by MerchantApp and AdminApp. `Money.parse` reads a typed price,
  Arabic-Indic digits included, and refuses anything it cannot read exactly.

**Phase 1 is closed.** 198 Dart tests, 34 rules tests, 16 function tests — all passing,
`flutter analyze` and `tsc` clean.

Order creation and coupon validation are Cloud Functions and wait on Blaze.

**Phase 2 is done**, on branch `phase-2-admin-app`. AdminApp runs on a phone and in a
browser from one codebase — the owner types roughly six hundred menu items during the
launch, and a real keyboard is the difference between an afternoon and a fortnight. It
carries the access gate, the merchants list with menu entry, the places screen with the
landmark suggestion queue, and the media moderation queue.

Two things are outstanding and both are deliberate:

- **`staff` management in AdminApp still has no screen**, but it is no longer blocked:
  `firebase/scripts/staff.js` creates accounts and stamps claims from a laptop. Creating
  a Firebase Auth user and setting a custom claim are ordinary Admin SDK calls and cost
  nothing on Spark — only *deployed* functions need Blaze. `createStaffAccount` is still
  worth building later, so a merchant can add their own couriers without a terminal.
- **The zone and landmark names in `data/edku.json` are placeholders.** They are
  structurally correct but not local knowledge. The owner replaces them; a wrong zone name
  sends a courier to the wrong part of town.

**Phase 3 is done**, on branch `phase-3-customer-app`. CustomerApp runs end to end:
the home composed from `homeSections`, merchant and item browsing, the basket, the
zone-based address flow, cash checkout, live order tracking, order history, the issue
ticket and the rating prompt. Three tabs in one `IndexedStack`, with the basket above all
of them. 501 Dart tests across the workspace; both APKs build.

Two things are outstanding and both are the owner's to do:

- ~~**Google Sign-In is configured, but has never run on a device.**~~ **Removed
  2026-08-27**, and never did run on one. It was the last thing standing between a fresh
  install and its first order, and it depended on a Play Console account, an OAuth client
  keyed on a release fingerprint nobody had generated yet, and the customer having a
  Google account at all. A phone number and a password need none of those. See
  "Customer accounts are a phone number" below.
- **Placing an order needs Blaze.** `OrderRepository.placeOrder` calls a Cloud Function
  that does not exist yet. Everything else about orders — watching, cancelling, issues,
  ratings — is ordinary Firestore and works on Spark today.

**Phase 4 is done**, on branch `phase-4-merchant-app`. MerchantApp runs end to end:
the order inbox with the alarm, accept and reject, the live board and its transitions,
the `pausedUntil` busy toggle, menu editing through the shared `MenuEditor`, and the
private rating feedback. Four tabs, inbox first. 596 Dart tests; all three APKs build.

Two things wait on Blaze, and both are server work by nature:

- **The accept-deadline task.** Nothing moves an unanswered order to `needsAttention`
  yet. The countdown a merchant sees is computed on the device from `acceptDeadlineAt`,
  so the *screen* is already right; what is missing is the task that acts when it runs
  out and tells the admin.
- **Rejection counting and auto-block.** `users.rejectedOrdersCount` has to be written
  by a server — a client that can increment its own refusal count can also reset it.

**Phase 5 is done**, on branch `phase-5-courier`. Courier mode is a second face of
MerchantApp chosen by the role on the token — no driver app, no second APK. The delivery
screen carries four things and nothing else: where to go, who to call, how much cash to
collect, and the one button that is next. Navigation is handed to whatever maps app is
already on the phone.

Two things Phase 5 turned up before a line of courier UI existed, both now fixed:

- The order carries a **copy** of the address and of `deliveryBy`. A courier cannot read
  another person's address collection, so a reference would have rendered as nothing in
  the street; and an address corrected next month must not rewrite where last week's
  order went.
- A merchant's courier carries the **same `merchantId` claim as the owner**, and every
  merchant rule was written on `ownsMerchant()` alone — so a courier could accept
  orders, rewrite prices and close the shop. Acting for a merchant now requires
  `role == 'owner'`.

**Phase 6 is done**, on branch `phase-6-home-kitchens`. `dailyMeals`, the section on the
customer's home, the meal screen, pre-order checkout, and the cook's own publish screen.
685 Dart tests, 56 rules tests.

One thing waits on Blaze, and it is the reason this collection exists at all: **the
transactional decrement of `remainingQty`**. Two people tapping the last portion at the
same moment is a race no client can settle, so the count is the server's — the rules
refuse a client write of either quantity, and `OrderDraft` carries `dailyMealId` for the
function to act on. The screen already says the right thing when it loses that race.

**Phase 7 is done**, on branch `phase-7-monetization`. All three revenue models, per
merchant, driven by a snapshot frozen at order time. Plans and subscriptions, the admin's
billing screen, the merchant's read-only view of it, and the `RevenueEngine` and
`dailyMaintenance` in TypeScript. 738 Dart tests, 33 function tests, 56 rules tests.

**`prepaid` shipped filled in, not as a stub** — the owner's call, taken at the start of
this phase. Wallet, top-up recording, per-order deduction, and intake suspension when the
credit runs out.

The engine exists twice on purpose: `Revenue` in Dart and `engine.ts` in TypeScript. The
phone *shows* the figure and the server *decides* it, and the server's answer is the one
that counts. Both are tested against the same numbers, so a disagreement fails a test
rather than turning up in somebody's till.

**Phase 8 is done**, on branch `phase-8-promotions`. `promotions` across all four
channels, boost ranking, the AdminApp approval queue and home builder, the merchant's own
request flow, and the weekly push cap. 815 Dart tests, 33 function tests, 56 rules tests.

AdMob is **not built**. It ships off behind `admobEnabled` per the spec, and building an
integration nobody can switch on — Google's network would serve competitor ads inside the
app, weakening the pitch to merchants paying for placement — is work with no reader. The
flag exists; the decision stays reversible.

**A pre-launch audit ran on 2026-08-24, and twelve of its fourteen findings are
fixed.** Every fix was written test-first — the test failed, then the code changed. Two
things it turned up are the reason the numbers below moved:

- **The promotions feature was dead in production** and nothing said so. The rules let a
  client read `status == 'active'`; `watchLive` queries for `['approved', 'active']`; and
  nothing anywhere ever writes `active`. Firestore rejects a whole query it cannot prove
  is limited to readable documents, so the ad slot and the boost ranking returned
  *permission-denied*, silently, to every customer in the city. **There were zero rules
  tests on `promotions`** — which is how a feature with 815 green tests behind it shipped
  invisible.
- **Order transitions were enforced only in Dart.** `OrderTransitions` carries the state
  machine and its comment says it is "enforced again in the security rules". It was not:
  the rules checked *which fields* changed, never the value. A courier could move any
  order straight to `delivered`, and `onOrderDelivered` fires on that transition — under
  `prepaid` that empties the merchant's wallet for orders that never existed.

Both got through because **the fakes are more permissive than Firestore plus the rules**.
`FakePromotionRepository.watchLive` happily returns what production refuses. The suite was
testing the fake, not the system. That is the finding behind the finding.

**AdminApp is not finished, and Phase 9 does not come first.**
`docs/13-build-order.md` scheduled Phase 2 as *"AdminApp minimum"*, and four modules from
`docs/06-admin-app.md` — **Customers, Issues, Config, Staff** — were never picked up by any
later phase. The dashboard is still a placeholder, plans are read-only, and a merchant
added by mistake cannot be removed. The owner also asked for a statistics screen and a
**حول لقمة** page carrying their photo, social links and a description, all edited from
AdminApp; and for **creating merchant accounts from AdminApp** rather than from a terminal.

The full list, and the decisions already taken on it, are in
**`docs/16-admin-completion.md`**. Read that file first — it is the agreement, not a wish
list, and every decision in it was the owner's.

**The backend is moving to Supabase.** Agreed 2026-08-24, before any code was written,
and the whole plan is in **`docs/17-supabase-migration.md`** — read it before touching the
data layer.

Two reasons, both the owner's: **Blaze needs a credit card**, which has blocked five
features since Phase 1, and the reporting in `docs/16` wants SQL rather than a counters
collection maintained by a function. And **now**, because there is no production data and
no live merchant — the cost of this migration only ever rises.

What makes it survivable is the seam that already exists: **24 of 108 source files touch
Firebase, and none of them is a screen.** Every screen speaks to one of thirteen
repository interfaces, and those interfaces do not change. Roughly 700 of the 840 Dart
tests never learn that anything happened, because they run against the fakes.

**Each repository is replaced in place, not doubled.** The plan originally ran the two
backends side by side behind a switch; that is the right shape for a live system, and
this is not one — no production data, no live merchant, nothing published. Rolling back is
`git revert`. Firebase leaves progressively, as the last thing importing each piece moves
off it.

Two things it is worth knowing without opening the file:

- **Supabase has no offline cache and Firestore does.** The owner accepted that for the
  customer, who orders from home on wi-fi. It is *not* accepted for the courier, who
  stands in the street and takes cash — a tap on "delivered" that dies with the
  connection is money collected against an order still showing as out. A write queue for
  the courier's actions alone is in the plan from the start.
- **Two Cloud Functions become database features rather than Edge Functions.**
  `onOrderDelivered` becomes a Postgres trigger, running inside the same transaction as
  the status change, so the idempotency guard is deleted rather than trusted. Order
  creation becomes a Postgres function, which puts the `remaining_qty` decrement in that
  same transaction — the race the entire `dailyMeals` design exists to prevent becomes
  `UPDATE … WHERE remaining_qty >= n`.

**Next: the Supabase migration (`docs/17-supabase-migration.md`), then AdminApp completion
(`docs/16-admin-completion.md`), then Phase 9 — Hardening and launch.**

### Phase 9 in progress (2026-08-26)

Both prerequisites are done: the Supabase cutover landed (S1–S6, Firebase gone) and
AdminApp carries every module from `docs/16`. The cloud project `luqma-edku`
(`vqcivwdoekyfqhfmnuos`) has all migrations, the token hook **verified live** — a real
sign-in decoded through `StaffIdentity` rules (`tool/verify-hook.mjs`) — pg_cron jobs,
realtime publications, and clean Edku seed data.

What Phase 9 has shipped so far:

- **Force-update** — `LuqmaForceUpdateGate` wired into all three apps; the owner raises
  `min_supported_version` from AdminApp and out-of-date builds meet a wall, not a bug.
- **Analytics + crash reporting** — Sentry behind `LUQMA_SENTRY_DSN`; empty means off,
  so dev builds send nothing. `LuqmaTelemetry.event` marks order placed/failed.
- **Staff accounts from AdminApp** — the `create-staff-account` Edge Function (deployed,
  proven live by `tool/verify-create-staff.mjs`): GoTrue verifies the caller's JWT, our
  staff table must say active platform admin, and only then does the service role mint
  one Auth user plus one staff row.
- **`merchants.planExpiresAt`** — one current truth; the nightly pass is a bounded range
  query and a payment moves the date in its own transaction.
- **Release signing** — one keystore at `signing/` (gitignored), all three apps' gradle
  files read it when present. SHA-1 is in `signing/README.md`; register it per app id.

- **Push, verified end to end on real handsets (2026-09-03).** All three apps, all four
  roles: a message queued into `push_outbox` reaches a customer, a merchant owner, a
  courier and a platform admin, **with the app closed**. That last part is the whole
  claim — it is what data-only messages could never do, and what nothing before this week
  had actually demonstrated rather than assumed.
  Two things were proven along the way and are worth trusting now: FCM's dead-token
  pruning works (a customer had two tokens, one was reported dead and removed on the next
  send), and the `orders` / `orders_critical` split arrives on the right channel per app.

Still open, none of it code:

- Play Console account, listings, and enrolling Play App Signing with this key.
- Onboarding the first 10–15 merchants at zero commission.
- **Edku's real zone and landmark names**, entered from AdminApp. A wrong zone name sends
  a courier to the wrong part of town.
- The `support_whatsapp` config row exists and is **empty**, so حول لقمة has no number on
  it until somebody types one into AdminApp.

### Images, the customer's home, and the merchant's phone (2026-08-27)

Four things that were agreed and had never been built. All four are done.

**Images had no way in.** Every image column has existed since the first schema — a
merchant's logo and cover, a menu item, a daily meal, a promotion — and the moderation
queue that reviews them was built and tested. **None of it could be reached**: no bucket,
no policy on `storage.objects`, no upload method. The queue reviewed a table nothing wrote
to, and every screen drew a grey box.

- The `media` bucket is **public**, with a uuid path. A private bucket makes each of ~600
  menu photos a signed URL that expires; a pending/approved pair stores every image twice
  and turns "approve" into a copy that can half-fail. What keeps an unapproved image out
  of the product is the `media` row, which `read_media` already hides.
- `upload()` writes twice and means both: **when the row fails, the bytes are removed**.
  A URL with no row is invisible to the product and to the admin.
- `ImageCompressor` is 1600px/85%, **pure Dart**, so what a merchant's phone does to a
  picture is provable in an ordinary `flutter test` rather than only observable on a
  device. A native compressor is faster; the swap is one file.
- One `MediaPicker` for all six surfaces. It does not take `uploadedBy` — the policy
  requires `uploaded_by = auth.uid()`, so there was only ever one correct value, and a
  parameter is somewhere a caller can put a different one.
- **An admin's upload arrives approved, and always could**: `admin_media` is `for all`
  and policies are OR'd. There is a test pinning it now instead of it being a coincidence.

**`LuqmaImage` is the launch-day screen, not an edge case.** On day one there is no
photograph of anything. Twenty identical marks read as a page that failed to load, so the
tint comes from the name — **summed code units, not `hashCode`**, which Dart does not
promise to keep stable across runs and which would repaint the whole city on an upgrade.

**Three things on the customer's home were placeholders**, and each was load-bearing:

- `categoryChips` rendered **four Arabic words compiled into the app** and filtered
  nothing. It is the `cuisines` table now — city-wide kinds of food, admin-only, because a
  merchant tagging itself into a circle it does not belong in is the cheapest promotion in
  the product.
- The search box was `readOnly: true` with `onTap: () {}`. `docs/04` removed the
  categories tab on the grounds that "search covers the rest", so the whole decision
  rested on a control that did nothing.
- `adSlot` showed one banner. It rotates now — and **stops entirely under reduced
  motion**, which is on for people who get motion sick and for people using a screen
  reader.

**The cuisine filter is a provider, not a field.** The circles and the list are different
sections, built independently by the registry in whatever order the admin arranged them.
Neither can reach the other, so `selectedCuisineProvider` is what they share. Null and
empty stay different answers: null is "nothing pressed", empty is "this cuisine has nobody
in it yet".

**AdminApp's home was eleven items in a `NavigationBar`** — a component Material designs
for three to five. It is a grid of all fourteen modules with live counts, and there is no
bottom bar at all on a phone. `admin_attention` is one function, not eleven queries.

**The merchant's phone rings.** FCM alone, in the existing `luqma-edku` Firebase project
(all three apps were already registered there with the right package names). The order
writes a row in `push_outbox` **in its own transaction** and `pg_cron` drains it — not
`pg_net` from inside the trigger, which would let a slow FCM fail an order, and not the
client calling afterwards, because the customer with the weak connection is exactly the
one whose call would not arrive.

The part that decides whether this still works in six months is **`settle_push` pruning
the tokens FCM says it no longer knows**. Without it a merchant who has changed phones
twice keeps dead tokens for ever and the logs fill with errors that read as a broken
integration rather than an old handset.

### Customer accounts are a phone number (2026-08-27)

**Google Sign-In is removed from CustomerApp.** A customer signs up with a name, a phone
number and a password, and signs back in with the number and the password. There is no
email field anywhere in the app. The full reasoning is in `docs/04-customer-app.md`; what
follows is what breaks if it is not known.

- **GoTrue's phone identity is not what carries this, and cannot be.** It needs an SMS
  provider: set `[auth.sms] enable_signup = true` with no Twilio and the CLI answers
  *"no SMS provider is enabled. Disabling phone login"* and refuses to start. So the
  number is folded into a synthetic address — `01012345678@phone.luqma.app`,
  `Phone.toAccountEmail` — and GoTrue holds an ordinary **email** identity, which needs no
  provider. That domain has no mailbox and nothing is ever sent to it.
- **Every spelling of one number must fold to one address.** `Phone.normalize` is that
  one spelling, and it has to be *called* — it is shared with validation and with the
  admin's customer search, and that second one was a claim this file made rather than a
  thing the code did. `SupabaseCustomerRepository.search` had its own copy that stripped
  spaces and left Arabic-Indic digits alone, so an admin on an Arabic keyboard searched
  `٠١٠…` for a row stored as `010…`, found nobody, and told a customer on the phone that
  they had no account — on the one screen that is the only way back from a forgotten
  password. An Arabic
  keyboard produces `٠١٠…` where the account was made with `010…`; two spellings reaching
  two accounts is one person with half their orders on each and no way to see the rest.
- **The synthetic address is never shown.** `_toIdentity` returns a null `email` for one
  ending in the reserved domain, so no screen can leak it by rendering `identity.email`.
- **The real number rides in the signup metadata**, and `ensure_user_profile` copies it —
  with the name — onto the `users` row. That row is where `place_order` reads the number
  it stamps on the order, which is the number the courier calls. A trigger that only
  inserts the id, as it did before, means a courier at the right door with nobody to ring.
- **A forgotten password has exactly one way back, and it is a person.** No mailbox, no
  SMS: the customer calls, and an admin sets a new password from the customers screen
  (`reset-customer-password`). **The admin types it** — something the person can remember,
  read down a phone line — 8 to 72 characters, never stored or logged. It reaches a
  customer, a merchant owner or a courier, and **refuses any `scope = 'platform'` staff
  row**: a support call must not become a way to reset another admin. Since A17 it also
  **ends every session the old password opened** (`end_sessions_of`, service role only),
  because the call is as often «somebody else has my phone» as «I forgot».
- **A customer can delete their own account, and an order that outlives them has no
  customer.** Google Play requires in-app deletion from any app that makes accounts, and
  `orders.customer_uid` made it impossible: `not null` and `on delete restrict`, so
  anybody who had ever ordered could not be removed at all. It is nullable and `set null`
  now. What goes is the person — the profile, the addresses, the ratings, the device
  tokens, the GoTrue user itself, all through cascades that already existed. What stays
  is the money: the order row with its `pricing`, `items`, `revenue` snapshot and any
  `order_settlements`, because that is what the merchant's statement and the platform's
  own accounts are built from. The two frozen contact fields are overwritten with
  **حساب محذوف** rather than emptied — a courier screen with a blank where a name goes
  reads as a bug, and this says which it is. `delete_my_account()` takes no uid and acts
  only on `auth.uid()`; it refuses any account with a `staff` row, because a merchant
  owner or courier removing themselves from the customer app would orphan a shop, and
  that is an administrative act. The screen says all of this in Arabic before the button,
  including that the same number can register again as a new person with no history.

### Infrastructure

**Supabase project `luqma-edku`, Frankfurt (`eu-central-1`).** Everything is there:
schema, policies, the access-token hook, the scheduled jobs, Storage. The details, the
dashboard link and the dart-defines are in "The cloud project" above.

Three Android apps: `com.luqma.customer`, `com.luqma.merchant`, `com.luqma.admin`. Those
are the Gradle `applicationId`s too — an application id is permanent once an app is
published, and it is half of what an OAuth client is keyed on. The Flutter template's
`_app` suffix was wrong and was corrected in Phase 3.

**Nothing is blocked on a credit card any more.** Five features waited on Blaze for eight
phases — server-side order totals, the accept deadline, rejection counting, the
`remaining_qty` decrement and image upload. All five are built: the first four as Postgres
functions and `pg_cron`, and Storage is included in Supabase's free tier. That was the
larger half of why the migration happened; see `docs/17-supabase-migration.md`.

### Running the checks

```
powershell -ExecutionPolicy Bypass -File tool\run_tests.ps1   # the whole suite, with a summary
```

Or run the pieces by hand:

```
cd packages/luqma_core && flutter gen-l10n && flutter analyze && flutter test
npm --prefix supabase test          # schema and seed, on PGlite — no Docker needed
DATABASE_URL=<luqma-test session pooler> npm --prefix supabase run test:stack
cd packages/luqma_core && flutter test test_live -j 1 \
  --dart-define=SUPABASE_URL=https://letdxuiypazbcfxbafab.supabase.co \
  --dart-define=SUPABASE_SERVICE_KEY=<service_role> --dart-define=SUPABASE_ANON_KEY=<anon>
```

**`tool\run_tests.ps1` is the reliable entry point, and the merchant_app tests must run
from PowerShell, not Git Bash.** Git Bash rewrites `PROGRAMFILES` to a POSIX-style path,
and the Android toolchain then fails to resolve it — the same tests pass untouched from a
PowerShell session that inherits the real Windows environment. The script sets no
variable; it simply runs in the shell that already has the right one.

**`-j 1` on `test_live` is not optional.** Those files all talk to the same database, and
`flutter test` runs files concurrently — so in parallel the suite fails somewhere
different every run and none of it is about the code.

**`npm --prefix supabase test` is capped at two files at a time**, and the cap is the
point. Node's test runner defaults to one worker per core and each PGlite instance is a
whole Postgres compiled to WebAssembly; once the suite passed about forty files this
machine ran out of memory and the run came back with a *different* set of a dozen failures
each time, none of which reproduce when the file is run alone. That reads as flaky tests
and is a full disk of RAM. Same family as the `-j 1` on `test_live` and the Gradle daemon
that died mid-build the day somebody ran the schema suite beside it: **if a suite fails
differently every run, count the processes before reading the diff.**

`supabase test` runs on **PGlite**, Postgres compiled to WebAssembly: the real migrations,
the real constraint machinery, no container. `test:stack` and `test_live` need policies,
`auth.uid()` and the claims hook, which only exist in a real Postgres — that is the
`luqma-test` project above, not a local stack.

**Connect to it in session mode (5432), never transaction mode (6543).** The stack tests
hold a transaction open across statements and set a role inside it; a transaction pooler
hands the next statement to a different backend and the role is gone.

`supabase start` still works and nothing here forbids it, but no documented command needs
it any more. **The local stack sits 1000 above the Supabase defaults** — 55321 for the
API, 55322 for the database — because Windows reserves 54084-54683 for Hyper-V on this
machine; check yours with `netsh interface ipv4 show excludedportrange protocol=tcp`.

`gen-l10n` first on a fresh clone, and after any change to `lib/l10n/app_ar.arb`.
The generated `app_localizations*.dart` are gitignored — generated code does not belong
in the repository — and `flutter test` on a *package* does not run the generator itself
the way an app build does. Without it a new string is a compile error that points at the
call site rather than at the missing step.

**~2023 Dart tests · 537 schema tests · 251 stack tests · 273 live-repository tests.**
`flutter analyze` clean.

There are no `function` tests and no `tsc`: the TypeScript Cloud Functions went with
Firebase, and what they did is now Postgres functions covered by `supabase/test/stack`.
The Dart count fell because roughly a hundred tests that existed only to argue with
`fake_cloud_firestore` were replaced by `test_live`, which argues with a real database —
fewer tests proving considerably more.

`kotlin.incremental=false` is set in both apps' `android/gradle.properties`. Kotlin's
incremental compiler cannot close its caches on this drive and fails every plugin module
without it.

The boundary tests need no JDK and no emulator any more. They are `supabase/test/stack`,
run against the `luqma-test` project by `tool\run_tests.ps1`, or by hand:

```
DATABASE_URL=<luqma-test session pooler> npm --prefix supabase run test:stack
```

## Where things are

| Path | What |
|---|---|
| `docs/00-overview.md` | Start here |
| `docs/01-data-model.md` | Firestore collections |
| `docs/02-dynamic-config.md` | The runtime control plane |
| `docs/03-order-lifecycle.md` | Order states and rules |
| `docs/04–06` | CustomerApp, MerchantApp, AdminApp |
| `docs/07-backend-functions.md` | Cloud Functions |
| `docs/08–12` | Notifications, geography, monetization, brand, security |
| `docs/13-build-order.md` | **Nine phases — follow this order** |
| `docs/14-design-system.md` | Colour, type, spacing, components |
| `docs/15-simplifications.md` | What was merged or cut, and why |
| `docs/16-admin-completion.md` | **AdminApp's unbuilt modules, and the owner's decisions on them** |
| `docs/17-supabase-migration.md` | **Moving off Firebase — the plan, and every decision in it** |
| `graphify-out/graph.html` | Dependency graph, open in a browser |
| `brand/identity.html` | Logo, palette, type and screen mockups |
| `brand/README.md` | How the logo assets are generated, and why |
| `supabase/functions/create-staff-account/` | Creates merchant, courier and admin accounts, from AdminApp |
| `supabase/functions/reset-customer-password/` | The only way back from a forgotten customer password |
| `brand/src/build_alarm.py` | The new-order alarm, and why every number in it is what it is |
| `packages/luqma_core/` | Models, repositories, config, theme, l10n, brand widgets, Firebase options |
| `apps/customer_app/` | CustomerApp — home, merchant, basket, checkout, orders, account, أكل بيتي |
| `apps/merchant_app/` | MerchantApp — inbox, live board, menu, shop, courier mode |
| `apps/admin_app/` | AdminApp — merchants, menus, places, media, billing, promotions, home builder |
| `supabase/migrations/*_rls.sql` | **The real security boundary** — read `supabase/test/stack` beside it |
| `supabase/migrations/` | **The Postgres schema, and the boundary.** Argued with by `supabase/test/` |
| `supabase/test/local/` | Schema and constraints, on PGlite. Fast, and needs nothing installed |
| `supabase/test/stack/` | RLS, the claims hook and the order state machine, against the real stack |
| `data/edku.json` | **Edku itself** — zones, landmarks, plans, home sections. Read by both seeds |
| `supabase/seed.mjs` | Edku into Postgres, from that same file |

## Decisions that are settled — do not relitigate

- **No OTP, no SMS provider, and public signup stays open.** Settled 2026-09-22 by the
  owner, closing H-01: they will not build the OTP feature. So the protection is what the
  server can check without one. **GoTrue already caps sign-up and sign-in at 30 per five
  minutes per IP** (`[auth.rate_limit] sign_in_sign_ups`), which is the only layer that
  can see an IP at all — a trigger on `auth.users` is handed a row, not a request — so a
  database-side cap could only be global, and a global cap turns real customers away
  during a launch to slow an attacker who can wait. Not built, deliberately.
  What *was* wrong was not the rate: `ensure_user_profile` copied
  `raw_user_meta_data ->> 'phone'` onto the profile unchecked, and that column is where
  `place_order` reads **the number the courier rings** and where the admin's customer
  search looks when somebody telephones about a forgotten password. The account's real
  identity is the number folded into the synthetic address, and nothing made the two
  agree — so an account held on one number could carry a different one on every order.
  The number is derived from the address now, and the name is bounded at 80 characters
  because signup metadata is client-controlled and unbounded. A staff account on a real
  address keeps its metadata number: an email carries none to derive.
- **There is no self-service password reset, and that is settled.** A customer signs in
  with a phone number folded into a synthetic address on a domain with no mailbox, and
  there is no SMS provider — so an emailed link and an SMS code are both impossible
  without buying one. The owner declined that cost on 2026-09-04: plenty of published
  apps have no self-serve reset. The way back stays a phone call to an admin, who issues
  a new password through `reset-customer-password`. Do not reopen this as a gap.
- **Cash on delivery only.** The model is payment-method aware for later, nothing more.
- **One commission rate for every shop, collected in cash weekly.** Settled 2026-09-19 by
  the owner: 5% of the food (never the delivery fee) to start, set in AdminApp's
  الإعدادات (`default_commission_percent`); changing it moves every shop not marked
  `commission_custom`, and a shop can be given its own rate from its billing screen. A new
  shop starts on the default whatever its row says. The owner collects cash once a week and
  records it (`record_commission_payment`); a Saturday cron reminds shops that owe, and
  crossing `commission_alert_pounds` (500 ج) pushes the shop and the admins once —
  **a notice only, never an automatic suspension**: the owner decides.
- **The complaints assistant is rules, not a model.** «مساعد لقمة» in CustomerApp answers
  from the order itself (`OrderHelper`: status, deadline, bill) and anything it cannot
  settle becomes an ordinary `order_issues` ticket with the topic first. Free and unable to
  invent anything — the owner's choice over a paid AI (2026-09-19).
- **A payment is recorded once.** `top_up_wallet` and `record_subscription_payment` take a
  `p_receipt_id` the screen generates once per payment; a retry after a lost reply returns
  the stored result instead of charging twice (`payment_receipts`).
- **A financial row outlives its subject, and a frozen name is how it stays readable.**
  Settled 2026-09-21 while closing H-06/M-05, and it is one rule where there were three:
  `courier_commission_payments` was `on delete restrict`, `payment_receipts.courier_uid`
  was `set null` under a CHECK demanding NOT NULL, and the shop side was `cascade`. So a
  courier who had ever been charged **could not be deleted at all** — one constraint
  refused and the other nulled a column into a violation — while deleting a shop silently
  threw away its paid subscription terms and the receipts that exist so a payment cannot
  be recorded twice. Every subject FK is `on delete set null` now, the subject columns are
  nullable, and `stamp_payment_subject_name` freezes the name at insert. **The name is
  stamped by a trigger, not by the four functions that write these tables across six
  migrations** — a rule every writer has to remember is a rule the next writer forgets.
- **A receipt's reply says which payment it is.** `record_courier_payment` answered with a
  balance and an amount, neither of which says *which* — so a screen reconciling a pending
  attempt had nothing to check against and could report a success belonging to a different
  payment. The reply carries the receipt, kind, subject, amount, when it was first
  recorded, the balance **as it stands now**, and `repeated`. That last one is not
  decoration: without it «اتسجّل» and «كان متسجّل» are the same sentence, and only one is
  true of the tap in front of somebody holding cash. `CourierCollection.answers()` is
  lenient in exactly one direction — a server that says nothing about the receipt is an
  older one and is trusted, because refusing it would stop collections the day an APK runs
  ahead of the database.
- **The idempotency key is written to disk before the request, or the money does not
  move.** C-01: both AdminApp money paths minted their key in memory and nowhere else, so
  a double tap, or the app being killed between request and reply, produced a *new* key —
  and the server only refuses a repeat of the **same** one. `PendingCollection` now carries
  the kind, the subject and everything the server will be told, and `decode` refuses a
  half-written record, a record belonging to another kind or subject, and a subscription
  attempt that cannot name its plan and months. Single-flight shuts the door **before** the
  dialog opens: a second tap that reaches a second dialog has already made a second key.
- **An installation can take itself off an account without a session.** H-10. Removing a
  device token needed the JWT, which is the wrong shape for the one moment it exists for:
  if that last deletion fails after GoTrue has signed out, the token waits for an auth
  emission that never comes on a phone somebody signed out of and put down, and the old
  account goes on being woken on it. `register_device_token` mints a secret and returns
  it; `revoke_device_token(token, secret)` needs no JWT at all. **`anon` may call it, and
  that is safe because the secret is the authorisation** — the worst its holder can do is
  stop their own device being woken. The secret rotates on every registration, so an
  account that has handed a shared till on cannot take it back off the shop using it now.
- **A deleted customer keeps their zone and nothing else.** H-02: both deletion paths
  scrubbed the two contact fields and left the order's frozen `address` holding the street,
  building, floor, flat and **exact coordinates**, readable by the merchant, the courier
  and every admin. It is `jsonb_build_object('zoneId', zone_id)` now — the zone because the
  delivery fee is a zone's fee and the statements are built from these rows, and a quarter
  of a town is not a doorstep. Nothing is left as an empty string: «we removed this» must
  not look like «this was blank».
- **Every sensitive admin mutation goes through an audited function.** H-09 began with a
  survey whose first finding was structural: `audit_log` has **no table triggers anywhere**
  and is written by fourteen functions — all of them things built as RPCs for money or
  identity reasons — so *every* PostgREST write AdminApp made was unaudited, without
  exception. Staff creation, media moderation, merchant status and deletion, coupons and
  `setRevenueModel` now go through functions that write the row and its evidence together,
  and the table grants were taken away, because a write that skips the function skips the
  audit with it.
- **A moderator is an admin except money, deletion, and who anybody is.** Decided and
  built 2026-09-21 (`20261024000000_a_moderator_is_an_admin_except.sql`). The role has
  been in the schema, in `StaffRole` and on the admin's own staff form since Phase 2, and
  the gate only ever asked `is_admin()` — so creating one produced an account that opened
  nothing and said nothing about it. It **does** give a moderator courier ID documents and
  customer numbers, and the owner chose that knowingly.
  **It is granted, then excepted, and that shape is the decision.** `is_admin()` widens to
  answer for both roles, so all 47 policies and 44 functions that ask it keep working
  untouched; widening them one at a time is 91 judgements, and the ones that get missed
  fail silently in the direction of «this screen is empty for no reason». What is taken
  back is taken back in three narrow places: a strict `is_platform_admin()` that 14 money
  and deletion functions ask instead, a `refuse_moderator_delete` trigger on 25 tables,
  and `refuse_moderator_privilege_write` on `staff`, `courier_merchants`, `config` and
  `plans`. A second migration (`20261024010000`) narrows the four that *mint* an identity
  — `approve_staff_application`, `create_staff_profile`, `attach_courier_by_phone`,
  `admin_set_config` — because a function that asks the wide question and then trips the
  trigger refuses at the wrong depth: after it has agreed to the write and logged it.
  **Rejecting an application is not narrowed, and that is the role.** It mints nothing, so
  a moderator triages the queue and an admin closes it; AdminApp puts a sentence where the
  قبول button would be rather than offering one the database will refuse.
  Two exceptions the owner's sentence does not name and plainly does not mean: **`staff`
  carries a `for all` policy**, so a moderator with an admin's reach writes
  `role = 'admin'` onto their own row — a permission that can grant itself is not a
  permission; and **`config`** holds `default_commission_percent`, which is money by
  another name, and `min_supported_version`, which walls every customer out with no back
  door.
  Reading is not taking: a moderator can still read the receipts and the roster. That is
  what the role is for.
- **A new table keyed on an order needs a line in every teardown.** `courier_settlements`
  is `on delete restrict` for the same reason `order_settlements` is, and adding it without
  touching `test_live/harness.dart` killed **eighteen tests** in teardown — where the
  symptom names whatever the file was testing rather than the cleanup that threw. Nothing
  else could catch it: PGlite builds its own fixtures and deletes no cities, the stack
  tests roll back so no delete is real, and a release build runs no queries. This is what
  `test_live` is for.
- **A courier shows their papers, and the papers belong to the person.** Settled
  2026-09-20 with the owner, after a structural review parked an earlier attempt
  (`park/courier-papers-and-commission`, still parked). A courier applicant hands in three
  photographs — ID front, ID back, and a selfie holding the ID — and **a courier cannot be
  approved without them**, enforced by a trigger on `staff_applications` rather than inside
  `approve_staff_application`, so an admin on an older APK meets the same rule.
  Three decisions, all the owner's:
  *the papers are kept while the person is working or waiting to hear, and purged
  `staff_docs_grace_days` (30) after neither is true* — not for ever, and not at approval;
  *a courier's commission debt survives their account*, the same rule as an order surviving
  a deleted customer; and *documents ship first, the per-delivery commission separately* —
  **a platform courier works at zero commission until that half is designed**, and nothing
  in the schema implies otherwise.
  The papers hang off `auth.users`, never off the application. The earlier attempt hung
  them off `staff_applications` and swept anything no application row pointed at, so an
  approved courier's national ID was one deleted row away from vanishing.
- **`refresh_staff_documents_retention` is the only writer of `purge_after`, and
  `staff_documents` grants SELECT to nobody else.** A retention rule the person it counts
  down for can edit is not a rule — and neither is one a second writer can disagree with,
  which is exactly the fault that parked the earlier attempt: *who is a platform courier*
  was asked by `is_courier_for_order` and answered differently by
  `apply_courier_settlement`, which then **returned silently**. A courier dropped from the
  platform roster could deliver all week and accrue nothing, with no error anywhere. So
  every path — hiring, dismissal, reinstatement, removal, a rejected application — goes
  through that one function, and the nightly sweep **recomputes before it deletes** so a
  clock left wrong by a path nobody thought of is corrected rather than acted on. An admin
  is refused the direct write too, and `supabase/test/stack/staff_documents.test.js` says
  so out loud.
- **There is no deletion queue for storage, and there never needed to be.** The parked
  attempt built `staff_docs_deletions` plus a drain worker plus a cron because objects
  looked undeletable from SQL. `20260828040000` had already found the door:
  `storage.allow_delete_query`, transaction-local, which `sweep_orphan_media` goes through
  and `sweep_staff_documents` now does too. **The stack teardowns need it as well** — a
  test that deletes its own uploads without naming it fails on `protect_delete` and leaves
  the bucket filling up every run.
- **A platform courier keeps the delivery fee and pays the platform a share of it.**
  Settled 2026-09-20 with the owner, and it is the half a structural review had parked.
  `courier_commission_percent` (10, guarded 0..50 on the `config` table) of the fee **less
  its discount**; free delivery costs the courier nothing, because a percentage of a fee
  nobody received is charging for money nobody received. Collected in cash weekly, exactly
  as a shop's commission is. **A shop's own rider hands the shop everything** and what
  they are paid is between them — there is still no column anywhere for a shop's wage to
  its courier and the app does not invent one. **A courier's debt survives them leaving.**
- **There is a `courier_settlements` row for every delivered order, including the zeros.**
  This is the fix for what parked the feature, and it is the shape rather than the
  arithmetic. The old `apply_courier_settlement` asked at settlement time whether the
  courier was eligible and **returned silently** when the answer was no — while
  `is_courier_for_order` had already let that same courier mark the order delivered on
  `auth.uid()` and an active staff row alone. Two questions, two answers, money in the
  gap: a rider dropped from the platform roster worked all week, accrued nothing, and
  nothing anywhere said so. Now `ground` records which of three answers applied
  (`platform`, `merchantDelivery`, `notPlatformCourier`), eligibility is asked **once**
  inside the delivery transaction and frozen, and a reversal reads the frozen figures back
  rather than recomputing — so a rate changed next month cannot refund an amount nobody
  was charged. Same rule as `order_settlements`: "an audit trail with the uninteresting
  entries left out is one nobody can count."
- **The courier's cut is computed twice, and that is deliberate.** `CourierCut` in Dart
  and `apply_courier_settlement` in Postgres, tested against the same numbers by
  `courier_money_test.dart` and `what_the_courier_keeps.test.js`. The phone *shows* the
  figure and the server *decides* it. `~/` on an integer bps, because Postgres truncates
  `(basis * bps) / 10000` — rounding on the phone would put it a piastre above the server
  on half the orders in the city. The same arrangement `Revenue` and `engine.ts` had.
- **Courier mode is no longer one screen, and the original reason still stands.** Amended
  2026-09-21 by the owner: a rider could not see what they delivered, what was charged, how
  much they owed, or whether last week's cash had been credited. The decision that was
  reversed was about the *delivery* page — sized to be read one-handed at a junction — and
  the eleven screens declined with it were a queue, a pickup flow, availability and a
  problem sheet. A statement is none of those. The delivery page is untouched; كشف الحساب
  is a page of its own reached from the summary card, the same shape as the merchant's
  `StatementScreen`. Every charge carries the sum behind it («توصيل ٢٠ ج · عمولة ١٠٪») and
  every zero carries its reason, so "why is it this much" is answered on the line rather
  than by a telephone call.
- **`PendingCollection` is the frozen pair, and both collection screens use it.** A
  receipt id and an amount are one thing, set before the first request, written to disk
  before it is sent, never edited afterwards, and read back only when **both** halves are
  there. The merchant screen learned why: an id minted when the dialog opened and an
  amount read from the box at every press meant a retry sent the original id with a new
  figure — the server answered with the first receipt and moved nothing, and the screen
  said «اتسجّل ٢٠٠ ج». A false receipt in a cash business, produced by the path built to
  prevent one. The half-written record is the same bug reassembled, which is why `decode`
  is both-or-neither. It lives in `admin_app/src/billing/pending_collection.dart` and the
  key it builds is the one the merchant screen always used, so a pending record already on
  a phone survives the move.
- **A courier is paid outside the app, and the app's job is the facts.** Settled
  2026-09-11 when the earnings screen was specified and it turned out nothing in the
  product knew what a courier earns — no table, no column, no rule, only a colour note in
  a design pack. There is no courier pay model and none is being built. The screen counts
  what the app already knows: deliveries made, cash in hand, and which shop each belongs
  to. That is what a rider and a shop argue over at the end of a shift, and the app can
  settle it without inventing a wage.
- **A delivery that came back is recorded, counted on its own, and carries no money.**
  The customer refused, or was not there. Today that is an ordinary `cancelled` with a
  reason and `cancelled_by = 'courier'`, so the data already exists; what was missing is
  counting it apart from an order the customer cancelled before it ever left. **Whether
  the courier is paid for that trip is the shop's decision, made between them** — the
  owner's call, and deliberately not a rule in here. Sales figures exclude it; the
  courier's own count shows it beside the deliveries that landed.
- **Arabic RTL only**, with i18n scaffolding so English is a file, not a rewrite.
- **Western numerals** for prices (`150 ج`), not Eastern.
- **Multi-city data model, Edku-only launch.** Everything carries `cityId`.
- **No driver app.** Courier is a mode inside MerchantApp, driven by `staff.role`.
  Reaffirmed 2026-09-11 against the September design handoff, which ships eleven screens
  as a dedicated Courier App and says in its own README that the owner approved it. The
  owner did not: asked directly, they kept the mode. The handoff is amended on this point
  and `design/design_handoff_luqma_apps/README.md` says so at the top.
  **Courier mode also stays one screen.** The handoff's eleven — a filtered queue, a
  five-step pickup flow, earnings, availability, a problem sheet — are a richer product
  than somebody can read one-handed at a junction, which is what the existing screen was
  deliberately sized for. It gets modifications, not a shell of its own.
- **A courier works for several merchants, and that is new.** Agreed 2026-09-11 from the
  same handoff, and it is the one part of that divergence the owner kept. Edku's couriers
  freelance across shops; a one-merchant scope either leaves capacity unused or forces
  platform scope on everybody.
  It is not a UI change. `staff.merchant_id` is a scalar, and the access-token hook copies
  it into the JWT as a single `merchant_id` claim that `belongs_to_merchant`,
  `is_merchant_owner` and `is_courier_for` all read. Three merchants do not fit in that
  field. **An owner stays bound to one merchant** — only the courier relationship becomes
  many-to-many — so `is_merchant_owner`, which guards the money, does not move.
- **AdminApp never goes on Google Play.** Direct APK.
- **Dynamic means values plus home-screen composition** — never full server-driven UI.
  The section registry is a fixed map of widget builders; the server picks and orders them.
- **AdMob ships off** behind `admobEnabled`. Merchant-sold promotions come first.
- **A customer signs in with a phone number and a password.** No Google, no email field
  anywhere in CustomerApp. OTP stays built and off behind `otpEnabled`, so the number is
  captured rather than verified and the password is what protects the account.
- **The brand name is never a text widget.** It is `LuqmaLockup`, backed by SVG. Lemonada is
  not a bundled font. Cairo renders everything else.
- **The owner enters merchant menus and shoots photos personally.**
  **Amended 2026-09-11: there is a way in, and it is an application rather than an
  account.** MerchantApp gains a signup page asking one question — courier, restaurant, or
  home kitchen — and what it writes is a row in `staff_applications`: a name, a phone, a
  kind, and whatever the applicant typed about themselves. **That row has no privileges of
  any sort.** The owner reads it in AdminApp, telephones, and approves; approval is what
  mints the `staff` row. The reason for that shape: `staff` is what every policy in the
  database reads to decide who you are, so a screen writing it directly would give that
  boundary an anonymous writer, and anybody who installs the APK a row in it.
  **Amended again 2026-09-18, by the first real merchant.** He applied, was approved, and
  vanished — and the three faults behind that are the shape of it now
  (`20261005000000_an_application_becomes_an_account.sql`):
  *the applicant makes their own account when they apply.* The form asks for a password and
  creates the ordinary phone account a customer has — which carries nothing at all — and
  the application names it in `applicant_uid`. Without one there is nothing for approval to
  turn into a merchant, which is precisely what happened: the row said `approved` and no
  account, no shop and no `staff` row existed anywhere.
  *Approval creates the account, in one transaction.* `approve_staff_application` writes the
  `staff` row, and for a shop the `merchants` row too — `pending`, in the zone the admin
  picked, at zero commission — and pushes «حسابك اتفعّل». `review_staff_application` refuses
  `approved` now, because an admin handset carrying an older APK would otherwise reproduce
  the whole incident with one tap.
  *An application is signed, and for the number the account holds.* `anon` cannot insert at
  all, and a trigger requires the applicant's account address to be that number folded into
  the reserved domain. Otherwise the theft is cheap: file a real restaurant's name and
  number against your own uid, let the owner ring the restaurant and agree terms, and
  approval hands you the shop.
  `create-staff-account` stays, and is still how «الفريق» makes an account by hand — which is
  why MerchantApp's sign-in takes an address *or* a number.
  A merchant **does** fill in their own details now, and the owner checks them on the call
  and corrects what is wrong from AdminApp. The zone, the hours, the delivery fee, the
  plan and the menu stay the owner's to settle — a shop that describes its own zone wrongly
  sends couriers to the wrong part of town, which is why this was closed in the first
  place.
  **A courier's attachment is granted, never claimed.** An applicant may not name the shops
  they carry for: a rider who could attach themselves to every shop in Edku would read
  every customer's address and telephone number in the city.
  This replaced a decision taken an hour earlier the same day — that a merchant owner could
  create courier accounts for their own shop. With an approval queue nobody needs to, and
  the narrower privilege is the one not granted.
- **Edku's zone and landmark names are entered from AdminApp, not from a file.** The names
  in `data/edku.json` are structurally correct placeholders and were never meant to ship
  as they are; the places screen edits both, and that is the path. So this is data entry
  by somebody with local knowledge, not a code task and not a launch blocker — but it is
  a real one: a wrong zone name sends a courier to the wrong part of town.
- **Commission is charged on the food, never on the bill.** `commissionBasis` in
  `engine.ts` and `Revenue.basisFor` in Dart both return `pricing.subtotal`. The delivery
  fee is not the platform's to take a share of: when the platform delivers, the fee is
  already the platform's and the merchant never sees it, so charging a percentage of it
  too is charging for money they did not receive. It survives one sentence in a shop —
  *"العمولة على الأكل. التوصيل مش بناخد منه حاجة."* — which in a cash market is worth
  more than the piastres.
- **A merchant who delivers their own food needs a courier account.** Only `role ==
  'courier'` may mark an order delivered, because that is the transition that moves money.
  The merchant's live board never offered the control; since the audit the rules agree.
- **Errors are never a dead end.** `LuqmaErrorView` in `luqma_core` is the only error
  state in all three apps, and it takes an `onRetry`. It replaced seventeen private
  `_Error` copies that had drifted into fifteen different versions, none with a way out.
- **Every `IconButton` carries a `tooltip`.** It is the accessible name as well as the
  long-press label. `packages/luqma_core/test/icon_labels_test.dart` scans the source and
  fails the build otherwise.
- **Motion is set on the theme, never per screen.** `luqmaPageTransitionsTheme` is what
  makes every push in all three apps 300ms easeOutCubic, and `LuqmaEntrance` is the
  40ms-per-row stagger `docs/14` §4 has asked for since Phase 0. Both were published
  numbers that nothing read until 2026-08-30 — screens ran on Material's platform
  defaults, which on Android is a slower vertical fade belonging to no design system here.
  A transition a screen has to remember to ask for is one that gets forgotten on the
  twenty-sixth screen.
- **Reduced motion is answered in two places, and both are needed.** `buildTransitions`
  has a `BuildContext` and reads `MediaQuery`; a route's `transitionDuration` is asked for
  before any context exists and reads the binding. Doing only the first skips the
  *painting* while still holding the screen for 300ms, which leaves somebody who asked for
  less motion staring at a frozen screen — worse than the slide.
- **The build number is not the owner's.** It lives on حسابي, read from
  `appVersionProvider` which `main()` fills from `PackageInfo`. It used to be a hardcoded
  `1.0.0` on حول لقمة, directly under the owner's photo and description — a technical
  detail presented as part of who they are, and a second source of truth that would
  eventually disagree with the store.
- **The apps are `0.9.0` until they are on Play, and nothing builds `--split-per-abi`.**
  Two decisions taken together on 2026-09-11, both about the number a customer reads out
  on a support call. `1.0.0` is reserved for the first build anybody can download; before
  that it would be claiming a release that has not happened. And `--split-per-abi` adds
  1000 × the architecture's index to the version code, so build 9 shipped as **2009** —
  which the owner read as a year, reasonably. That offset exists so several architectures
  of one release can coexist on Play and we ship exactly one, so it bought nothing. The
  output is a single `app-release.apk` now and the version code is the build number in
  `pubspec.yaml`.
  The build number **never repeats and only ever rises**; it starts at 10 because 1 and 9
  have both been on a handset, and Android refuses a code lower than one it has seen. A
  repo whose version sat at `+1` while a phone carried `2008` is how that was discovered.
- **`min_supported_version` is compared against the version *name*, not the code.**
  `LuqmaConfig._requiresUpdate` parses three dotted integers, so setting it to `1.0.0`
  from AdminApp while the apps are `0.9.0` walls every customer out of the product with
  no back door — the gate is deliberately un-bypassable. It is unset in production today,
  which is the only reason changing the version name was safe. Raise it to a version that
  actually exists, and never above what is installed.

## Rules that are easy to break by accident

- Orange `#D67F2B` fails contrast on the cream background (2.58:1). Prices sit on **white
  cards at 18sp+**; anything smaller or on cream uses `priceStrong #995A1D`.
- Orange badges carry **dark text `#130B07`**, never white (3.03:1 fails).
- Interactive outlines use `borderStrong #A5794F`. `#D6BFA9` is decorative hairlines only.
- Cards are **white with a soft shadow**, never `Surface #E5D3C1` — it is invisible on cream.
- No colour is written in a screen. Everything comes from tokens in `luqma_core`.
- Minimum body text is **15sp**, not 14. Arabic loses legibility faster than Latin.
  **Settled 2026-09-11: the token moved.** `bodySmall` was 13sp across a hundred call
  sites in the three apps — merchant and dish descriptions, the secondary row under every
  card — so the published rule and the token set disagreed from Phase 0 until the
  customer redesign closed. It is 15 now, the same size as `body`, differing from it in
  colour and role rather than in size. `caption` stays at 12 and is deliberately outside
  the rule: it is a label, not body text.
  `theme_test` asked the question of `body` alone, which is how a rule about body text
  passed for nine phases while the token most of it used sat two points under. It now
  asks it of every style used for body text.
  It cost one layout: the admin billing screen's record button sits below the fold on a
  360x780 phone with the larger text, and its test had been tapping where the button
  happened to be. The body is a `ListView`, so the fix is to scroll to it — but a screen
  that is *not* scrollable would have been a real defect, and that is what to look for
  when this bites again.
- Minimum touch target 48×48dp with 8dp between targets.
- Every uploaded image becomes a `media` document and is invisible until an admin approves it.
  There is no second path for images.
- Whether a merchant can take an order is **derived** from `workingHours` + `pausedUntil`.
  Never store it.
- The merchant's accept countdown is shown on **instant orders only**. Pre-orders have no deadline.
- A pre-order **never goes in the basket**. The basket is one restaurant's food to be
  cooked now; a daily meal is dated and collected in a window, and mixing them produces
  an order nobody can fulfil.
- `dailyMeals.date` is a **`yyyy-MM-dd` day key**, not a timestamp: "today's meals" is an
  equality query, and equality against a timestamp matches one microsecond.
- Time comes from `clockProvider`, never `DateTime.now()` in a widget. Whether a meal can
  still be reserved depends on the day *and* the collection window, and a test that
  cannot move the clock can only be written by waiting for a Tuesday afternoon.
- **Never match `AsyncError()` after `AsyncLoading()`.** A stream that fails before it has
  ever emitted stays `AsyncLoading` with the error hanging off it, so the error arm never
  fires and the screen spins for ever. Every switch tests `hasError` first. On the
  merchant inbox that bug reads as a quiet evening.
- **A merchant asks; only an admin approves.** `PromotionRepository.request()` forces the
  status whatever the document says, and the rules refuse anything else.
- **And an admin can put one up themselves** — `createApproved`, added 2026-08-30. The
  screen was an approve/reject queue only, so the owner could act on what merchants asked
  for and had no way to announce anything of their own; putting up "التوصيل مجاني
  النهارده" meant signing into a merchant account to ask themselves for it first. The
  `admin_promotions` policy always allowed the write — only the UI was missing.
- **Approved is not live.** `startAt` decides that — a campaign signed off today for next
  week must not appear the moment somebody approved it.
- A promotion with **no zones reaches the whole city.** A merchant who did not narrow
  their campaign meant everybody, not nobody.
- The **push cap is on the city, not the merchant.** What is being rationed is a
  customer's patience, and it does not care which shop the third notification came from.
- The merchant is derived from the **`merchant_id` claim on the token**, never from a
  column the client can write. The access-token hook copies it out of `staff` at sign-in,
  so only the server can issue one, and `is_merchant_owner()` reads it from
  `auth.jwt()`.
- **`ownsMerchant()` is not "runs this merchant".** An owner and their courier carry the
  same claim. Anything that acts for a merchant uses `isMerchantOwner()`.
- **A policy that allows less than the query asks for returns nothing, not less.**
  Postgres filters rows silently, so a query the policy cannot satisfy comes back empty
  rather than refused — and an empty list reads as "there is nothing here", which is a
  sentence the product says for real. Every query in a repository needs a live test that
  runs *that query* through a real token, not a test that reads one row: the two fail
  differently and only one of them resembles production.
- **`for all` covers delete, and a delete has no `with check`.** A policy written only
  as `with check` refuses every delete and lets nobody through; one written only as
  `using` lets a row be *changed* into something the writer could not have created.
  `using` judges the row as it is, `with check` the row as it will be, and a write that
  needs both must say both.
- **`on delete set null` is an ordinary update, and the column guards fire on it.**
  `delete_my_account` scrubs the two frozen contact fields on a departing customer's
  orders and then deletes the GoTrue user; the foreign key nulls `orders.customer_uid`,
  which is a column *no* role is ever allowed to write. So the guard refuses the
  cascade as readily as it refused the scrub, and `security definer` does not help —
  `guard_order_columns` asks whether a trusted server function has **declared** itself,
  never who owns the function. Server mode has to cover the delete as well as the
  update, and be put back: the setting is transaction-local inside the caller's
  transaction. Same lesson as `apply_order_settlement`, reached from the other end.
- **After the scrub, the order is nobody's to read — including in the test.** Every read
  policy on `orders` matches `customer_uid = auth.uid()`, and a null customer matches
  nobody, so a stack test asserting through the deleted customer's own role reads an
  empty set and proves nothing. `delete_my_account.test.js` switches to the owner with
  `set local role postgres` after the call, still inside the transaction `as()` rolls
  back.
- **On an update, judge the row that is already there as well as the one arriving.** A
  policy whose `using` clause reads only ownership lets the writer change the columns that
  decide ownership: `correct_own_rating` checked that a rating was yours and not that it
  still pointed at an order you received, so a customer could move their stars onto a shop
  they had never bought from.
- **`Result.guard` said `ok` for a write that changed nothing, and every repository
  write went through it.** PostgREST does not throw when a policy filters a write down to
  zero rows — that is a successful request — so the screen said تم الحفظ over an
  unchanged database. `Result.guardWrite` asks the write for what it changed and refuses
  an empty answer, across the 33 call sites in the 14 repositories that write rows. The
  other nine read or call an RPC, where the function's own `raise` is the failure path and
  a row count means nothing. The failure is `NotFoundFailure` on purpose: PostgREST cannot
  tell a row hidden by policy from a row that is gone, and calling it permission-denied
  would claim more than the server said.
- **A contract test with one party is not a contract.** `repository_contract_test.dart`
  states what a write means once, as a function taking the repository, and is called from
  both `test/` with the fakes and `test_live/` with the real ones. Stating it twice is
  exactly how a fake and a server drift; running it only against fakes proves the screens
  work against the fake, which is the finding behind half the bugs in this file.
- **The courier's queue is keyed on the account, and what it stores carries a version.**
  It was one global key, so a shared shop handset changing couriers replayed the first
  courier's "delivered" taps under the second's name — and `load()` swallows every decode
  failure by design, so the day the JSON shape changed every queued write on every phone
  would have gone silently. That queue is cash collected in the street; it is the only
  local storage here whose loss is money. The bare list already on phones is claimed once,
  with a durable owner marker so an interrupted migration cannot hand it to whoever signs
  in next.
- **The fakes are not the system.** They are more permissive than Postgres plus the
  policies, so a green suite proves the screens work against the fake and nothing more.
  Anything that depends on a policy needs a live test beside the widget test — that is
  what `test_live` and `supabase/test/stack` are for.
- **A rating was collected, stored, and never counted.** `merchants.rating_avg` and
  `rating_count` existed from the first schema and **nothing ever wrote them** — the
  customer rated, the row landed in `ratings`, the merchant read the comment on their
  shop screen, and the number on the card stayed 0.0 for ever. Every shop in the city
  showed the same zero, which reads as "nobody has rated this" rather than as a column
  with no writer. `refresh_merchant_rating` is that writer, and it recomputes from the
  rows rather than nudging an average that can only drift. Dishes have their own stars
  now too (`item_ratings`), which is what makes "الأكتر طلباً" answerable.
- **`security definer` on the trigger *and* on what it calls.** Both refresh functions
  are revoked from `authenticated` and the trigger runs as whoever ran the statement —
  the customer — so without it on both, rating a shop fails with "permission denied for
  function". Same trap as the delivery settlement, found the same way: by rating through
  a real customer token instead of a service key.
- **`as()` in the stack tests rolls back.** That is what keeps them from leaving residue,
  and it means an assertion *after* a write through a real token reads a database where
  the write never happened. Anything that checks a trigger's effect has to read it inside
  the same `as()` block.
- **The section named after ordering was ranked by review count.** `mostOrdered` sorted
  *merchants* by `ratingCount`, with a comment admitting it stood in for an order count
  that did not exist — so on a launch with no reviews it was every shop in arbitrary
  order under a heading promising otherwise. It is `popular_items` now: dishes, counted
  from delivered orders' `items` jsonb, with a LEFT join to rating so the shelf is full
  on day one instead of empty.
- **Two `media_id` columns still had no foreign key.** `merchants` got theirs on
  2026-08-30; `menu_items` and `daily_meals` are the same omission and the same
  `PGRST200`, and they are the two that matter most — the dish and the meal are the
  things being sold. Six hundred photographs the owner will shoot personally had nowhere
  to arrive.
- **`'2026-08-25 10:00' at time zone 'Africa/Cairo'` is not zone-proof without a cast.**
  The literal is untyped, and Postgres resolves it against the session's own `TimeZone`:
  as a naive `timestamp` on a Cairo session, where `at time zone` *interprets* it as Cairo
  local, and as a `timestamptz` on a UTC one, where the same operator *converts* it and
  the instant lands three hours out. The daily-meal test read 10:00 as 13:00 and the
  window had closed. It passed on every developer's machine and failed only in CI, which
  runs in UTC. `::timestamp` before the operator settles it. Run `TZ=UTC npm --prefix
  supabase test` before trusting anything that builds an instant from a literal.
- **The release gate was red on every push, and not because of the pushes.** `.g.dart`,
  `.freezed.dart` and `app_localizations*` are gitignored, so a fresh checkout has none of
  them — and CI's first Dart step ran before anything generated them. Every freezed type
  resolved to `dynamic`, and the first thing to notice was an exhaustive `switch` over an
  enum failing to compile in a file nobody had touched. Nothing in the repo ran
  `build_runner` at all: `run_tests.ps1` does `gen-l10n` and stops there. A gate that
  fails identically whatever you push is a gate nobody reads, which is worse than none.
- **`for update skip locked` protects the claim, not the work.** The lock ends when
  `claim_push_batch` returns, and the drain then makes one HTTPS call to FCM per token
  before it settles — so a batch slower than the one-minute cron was claimed again and the
  same alarm rang twice. `claimed_at` and `claim_token` hold a lease; `settle_push` matches
  the token and silently ignores a stale one, because a late completion is crash recovery
  working rather than an error worth failing the drain over.
- **A lease's clock cannot go in a partial index.** `now()` is not immutable, so the
  expiry stays in the query and the index predicate keeps only `sent_at is null and
  attempts < 5` — which is what stops the queue's sent history growing without bound.
- **A dismissal is a boundary change, not a claim change.** Every staff-shaped predicate —
  `is_admin`, `belongs_to_merchant`, `is_merchant_owner`, `is_courier_for` — read
  `auth.jwt()` and nothing else, and the access-token hook only checks `is_active` when it
  *stamps* the claims. So a dismissed courier went on marking orders delivered — the
  transition that moves money — until their token expired on its own. Each of those now
  also requires an active `staff` row for `auth.uid()`. An Edge Function bans the GoTrue
  user so sign-in and refresh stop, and its comment is honest that **a stateless JWT
  already issued cannot be recalled**, which is exactly why the database check is the real
  closure rather than the revocation.
- **An assigned courier used to skip every role helper**, because `courier_uid =
  auth.uid()` matched directly in the order policies. `is_courier_for_order` folds the
  whole delivery identity into one predicate so that shortcut cannot outlive the job.
- **A staff fixture built from claims alone is no longer an identity.** `as()` /
  `openAsStaff` tests that conjure an owner out of `{role, scope, merchant_id}` now fail
  the active-row check, and RLS answers by filtering the row away — so the write is still
  refused, silently and by the wrong layer. Give the fixture a real `staff` row; every
  such account has one in production.
- **A push token names an installation, not a person.** It lived on `users.fcm_tokens`,
  and `register` only ever appended to the signed-in row — so a shared merchant phone
  that went from owner to courier left the token on *both*, and each one's alerts rang on
  the other's handset. `device_tokens` keys on the token, so two owners are structurally
  impossible and registering is an upsert that **moves** the device. The array is still
  read for now: an APK already on a phone writes nothing else. **A device row wins over a
  legacy array entry** — without that the stale copy under the previous account recreates
  the bug for a half-updated fleet.
- **postgrest-dart's `.order()` defaults to *descending*.** Nearly every other API
  ascends. A bare `.order('token')` sorted backwards, and the test failure read as "the
  second device replaced the first" rather than as a sort direction. Spell out
  `ascending: true`.
- **One checkout is one order, even when the reply never arrives.** `place_order` takes an
  optional `client_order_id` and a partial unique index on
  `(customer_uid, client_order_id)` settles two requests that arrive together — the index
  is the authority, not a `select` before the insert. A losing race rolls back inside a
  PL/pgSQL subtransaction, so the order **and** its coupon redemption, meal decrement and
  push row go with it. The parameter defaults to null because an APK already on a phone
  cannot learn a new argument.
- **`place_order_priced` declared `app.server_mode` and never put it back**, and that
  setting is transaction-local rather than function-local — so it stood for the rest of
  the caller's transaction with every column guard down behind it. It is the rule
  `apply_order_settlement` already follows and this older function never did, and it is
  why a customer could rewrite `client_order_id` immediately after placing: the guard that
  refuses it had been switched off by the placement itself. The wrapper restores it.
  Nothing reachable from a phone could exploit it — PostgREST gives each RPC its own
  transaction — which is exactly why it survived a year. A **function-level `SET` is the
  right tool and hosted Supabase refuses it**: `permission denied to set parameter`.
- **A `main` that throws is an app that vanishes, not one that reports.** An async `main`
  whose body throws never reaches `runApp`: Android draws the launch theme for an instant
  and the process ends, which is indistinguishable from tapping the icon and nothing
  happening. All three now run through `luqmaBootstrap`, which owns the binding and puts
  the whole start-up in a `try` — on a failure it draws `LuqmaStartupFailure`, with the
  exception on it, because the person who can act is whoever the customer telephones and
  "التطبيق مش بيفتح" alone is unactionable. **No retry button**: re-running Sentry and
  Supabase initialisation in a half-started process is a control that might do nothing.
- **`restore()` had no floor under it.** It completes on GoTrue's first
  `onAuthStateChange`, and the customer's splash, the merchant's gate and
  `currentIdentityProvider` all wait on it — so an event that never arrives is a burgundy
  splash for ever, with no exception and nothing in Sentry. `resolveWithin` (8s) gives up
  to **signed out** rather than staying unknown, and a session arriving late still signs
  the person in through `auth.changes`, so the worst case is a signed-out home for a
  moment instead of a wall.
- **An argument is evaluated at the call site, and `main` is the worst place to learn
  that.** `keepPushTokenRegistered(refreshes: LuqmaPush.tokenRefreshes)` reads that getter
  *eagerly*, in the first lines of `main`, and the getter was an expression body over
  `FirebaseMessaging.instance` — which throws `[core/no-app]` until the
  `Firebase.initializeApp()` inside the deliberately un-awaited `LuqmaPush.start()` has
  finished. All three release APKs died on launch; Sentry caught it as `fatal` from
  `PlatformDispatcher.onError`. It is `async*` now, so the body runs on the first listen
  and waits for `start()`. `_starting` had been added days earlier for exactly this, and
  the getter written next to it did not use it.
- **`unawaited(f())` where `f` can throw is a fatal crash in these builds.** Sentry's
  `PlatformDispatcher.onError` reports unhandled async errors as fatal, so anything
  `main` fires and forgets must be incapable of throwing. `LuqmaPush.start()` guarded
  only `Firebase.initializeApp()` and left the permission request, the local-notification
  init and the launch-details reads outside the `try` — every one a platform channel on
  an OEM Android build. `_wire()` exists so the guard covers all of it rather than
  whichever lines somebody remembers to keep inside the block.
- **`push.dart` is testable for the one thing that matters.** A `flutter test` process
  has no Firebase, which is precisely the condition that broke launch — so
  `push_startup_test.dart` asserts that reading *and listening to* `tokenRefreshes`, and
  calling `token()` and `start()`, all survive it. That test failed with the exact
  production exception before the fix.
- **A data-only FCM message displays nothing by itself.** It needs the Flutter
  background isolate to wake and render, and that isolate does not run when the app has
  been swiped away, in battery saver, or on most OEM Android builds — so the merchant's
  alarm arrived only while the app was already open, which is the one case needing no
  notification. Every message carries a `notification` block now, with
  `android.notification.channel_id`. **The alarm never came from the app drawing it** —
  it comes from the channel, created natively at MAX importance with the sound, so a
  system-drawn alert on `orders_critical` sounds identical. `luqmaBackgroundMessage`
  returns early when `message.notification != null`, or the same order is drawn twice.
- **The FCM default channel was never in any manifest**, though the merchant's Kotlin
  said it was since Phase 4. Harmless while messages were data-only; the day Android
  started drawing them, a channel the device has not created yet means a silent
  "Miscellaneous" notification instead of the alarm.
- **Who may act and who to address are different questions.** Policies read
  `auth.jwt()`; the push triggers read `staff`. A courier with a valid token and no
  active `staff` row passes every policy in the app and is sent nothing — which is why
  `supabase/test/stack` had to grow staff rows it had never needed.
- **Push was built for one message and is general.** `push_outbox`, the drain, the token
  pruning and the channels were never merchant-specific; what was missing was rows. The
  customer is told three things — accepted, out for delivery, cancelled — on the `orders`
  channel, and the admin gets `needsAttention` on `orders_critical`. **Not every status**:
  a phone that buzzes at six steps is a phone whose owner turns notifications off, taking
  the two that matter with them. `LuqmaPush` lives in `luqma_core` now; each app supplies
  only its own native channel.
- **A banner is a picture or it is words, never both.** `imageWithText` laid the
  headline over the artwork, and it is the one mode nobody can design for: the
  merchant's photograph decides where its own dark parts are, so white text is legible
  on the picture it was tested against and invisible on the next one. Removed
  2026-08-31. A text banner carries `background_color` instead — eight swatches, and the
  ink is **computed from the ground** (`PromotionPalette.inkOn`) rather than stored, so
  there is no combination of columns that holds pale words on a pale colour.
- **`BoxFit.cover` is a crop, and a crop of somebody else's photograph throws away the
  part they cared about.** Every picture in the product used it: merchant covers, menu
  items, meals, banners, and the *moderation queue* — where an admin approving the
  middle of an image lets whatever is at its edges reach the city unseen. `LuqmaImage`
  defaults to `contain` on a warm mat now, and a caller framing something deliberately —
  a face in a circle — passes `cover` and means it.
- **A banner's picture needs an embed, and for two phases it had none.** The ad slot
  drew `SizedBox.shrink()` where the image belongs — a placeholder from before Storage
  existed — and `Promotion` had no url field for it to draw anyway. A merchant who paid
  for a banner, uploaded artwork and had it approved got the burgundy gradient, which is
  a real render mode and so looked deliberate rather than broken. The query embeds
  `media(url, status)` now and `imageUrl` is null unless the row says `approved`: an
  unapproved image must never reach a home screen, and that rule belongs in the mapper
  rather than in whichever screen happens to draw it.
- **An edit is a fresh ask.** `merchant_edits_unstarted_promotion` lets a merchant
  correct a placement they asked for, and `with check` forces it back to `requested` —
  so nobody approves their own words by editing something already signed off. It is
  refused once `start_at` has passed, because an edit sends it back to the queue and
  that would take a running campaign dark to fix a typo. `Promotion.isEditableAt` is the
  same pair of conditions, so no screen offers a button the database will refuse.
- **Nothing writes `PromotionStatus.active`.** Whether a campaign is running is a
  question about `startAt`/`endAt` — use `isLiveAt`, never the status alone.
- **An empty `zone_ids` is the whole *city*, not the whole world.** The `push` channel
  had no sender for two phases; the first one written read the empty array as "no filter
  at all" and queued a notification for **every customer in the database** — 1394 of
  them in `luqma-test`, against a fixture expecting two. During an Edku-only launch that
  is invisible, and on the day a second city opens it is an Edku restaurant's offer
  mailed to strangers. The city is the floor and the zones narrow *within* it.
- **A marketing notification has its own Android channel, and that is not decoration.**
  `push_outbox.channel` has allowed `'marketing'` since the table existed, with a comment
  saying operational alerts must not be silenced by the switch somebody flipped for
  marketing — but no channel existed on the phone, so the offers would have arrived on
  `orders`. Somebody tired of the advertising reaches for Android's own notification
  settings long before they find حسابي, and sharing a channel means they stop being told
  where their food is because they turned off an ad. `users.marketing_push` is the switch
  inside the app; the channel is what makes the promise true outside it.
- **The tap on a notification is a feature with a writer and, for four releases, no
  reader.** `LuqmaPush.tappedOrder` was written in four places and read nowhere, so the
  merchant tapped the alarm and the app came forward on whatever screen it was last on.
  `LuqmaTappedOrder` takes it — clearing as it reads — because a shell rebuilds on every
  tab switch and an order that reopens itself each time is a screen nobody can leave.
- **`addPostFrameCallback` from an idle phase schedules no frame of its own.** A tap that
  arrives during a build must wait for the frame to finish; a tap that arrives between
  frames must not, because deferring it means the callback is never called at all.
  Branch on `SchedulerBinding.instance.schedulerPhase`. Deferring unconditionally looks
  correct, passes the launch-path test, and silently does nothing for every tap while the
  app is running.
- **Android asks for the notification permission once, and remembers a refusal for
  ever.** It used to be requested inside `LuqmaPush._wire()` — in the first seconds of
  the first launch, over the splash, with no explanation — and the answer was thrown
  away. A merchant who tapped "Don't allow" had a phone that never rang and an app that
  never mentioned it: a quiet evening and a broken alarm look identical. The ask lives
  next to the sentence explaining it now, and a refusal gets a route through Settings
  rather than a button that asks again, which does nothing.
- The nightly billing pass has **no memory except `subscriptions.settledAt`**. Downgrading
  writes `planId` onto the *merchant*; without marking the row, the same expired term
  comes back every night, with a fresh `auditLog` entry each time.
- **Backticks inside a JavaScript template literal end it.** `tool/seed-demo.mjs` carried
  a SQL comment reading ``-- Guarded by name rather than by `on conflict`:`` inside a
  `` sql(`…`) `` template, and the file **had not parsed since that comment was written** —
  it survived review because two backticks are balanced and the script was never re-run.
  The same mistake broke `supabase/test/local/harness.mjs`. Prose in an embedded SQL
  string quotes nothing: write `ON CONFLICT`, not `` `on conflict` ``. `node --check
  <file>` catches it in a second and is worth running on any `.mjs` that embeds SQL.
- **Two migrations must never share a version prefix.** The CLI records an applied
  migration by the timestamp in its filename, so two files starting `20260826020000`
  are one version to it — and the second silently never runs. It cost a whole Phase 9
  feature here: `plan_expires_at` and the push-cap fix sat unapplied and untested until
  the collision was found. `ls supabase/migrations | sed 's/_.*//' | sort | uniq -d`
  must print nothing.
- **`ConvertFrom-Json` on Windows PowerShell hands the pipeline one object, not a row
  each.** `tool/build-apks.ps1` read the project's API keys with
  `… | ConvertFrom-Json | Where-Object { $_.name -eq 'anon' }`. `$_` there is the *whole
  array*, `$_.name` is an array of every name, `-eq 'anon'` filters that array rather
  than testing it, and the result is truthy — so nothing was selected and `.api_key`
  returned **every key the project has, joined into one value**.
  Two things followed, and connecting them took a night. The three release APKs carried
  the production **`service_role`** and **`sb_secret_`** keys — which bypass every policy
  in the database, inside a file anybody can unzip. And the apps could not reach Supabase
  at all: no home, no sign-up, no sign-in, while `flutter run` worked perfectly and
  `curl` with the real key returned 200 on every endpoint — because the key the release
  binary authenticated with was four keys in a trench coat.
  The parse is forced to enumerate now (`@(… | ForEach-Object { $_ })`) and the result is
  checked for being one string of the right shape. Downstream, the build reads its own
  APK and fails on any JWT whose payload says `service_role`, because a wrong key in a
  build is invisible until somebody installs it.
- **A PowerShell function cannot `+=` a variable in its caller's scope.** `$results +=`
  inside `Invoke-Check` wrote to a *local* copy, so `tool/run_tests.ps1` finished with an
  empty result table and printed **"All suites passed."** however many suites had failed —
  and its `$root` pointed at `tool/` rather than the repository, so every path it built
  was wrong. The documented entry point for the whole suite reported success
  unconditionally. Both fixed 2026-08-27 (`$script:results`); if a runner ever claims a
  pass, check that its summary table actually lists the suites.
- **`ensure_user_profile` makes the `users` row.** It fires on every insert into
  `auth.users`, so a fixture that also inserts one collides on the primary key, and
  "no such customer" is unreachable through a real account.
- **`alter database … set app.whatever` is refused on hosted Supabase.** Setting a custom
  parameter needs superuser and the hosted `postgres` role is not one — it answers
  `42501: permission denied to set parameter`. Anything a scheduled job needs to read goes
  in **Vault** (`vault.create_secret`, read back through `vault.decrypted_secrets`), which
  is encrypted at rest rather than readable by every session through `current_setting`.
  A function that reads vault must build the lookup with `execute`: a `language sql` body
  is parsed at creation and fails on PGlite, which has no vault at all.
- **An Edge Function verifies a JWT unless you say otherwise.** `pg_net` from a cron job
  sends no Authorization header, so the gateway answers `401
  UNAUTHORIZED_NO_AUTH_HEADER` **before the function runs** — its own logs stay empty and
  its own auth never fires. Deploy anything cron-driven with `--no-verify-jwt` and let the
  function's own secret be the gate. That is least privilege too: a purpose-built secret
  that can only trigger a drain beats sending the service-role key every minute.
- **PostgREST cannot embed across a foreign key that does not exist.**
  `merchants.logo_media_id` and `cover_media_id` were plain `uuid` columns with no
  `references media` — `cuisines.media_id` got one when it was added and merchants never
  did. So `cover:cover_media_id(url, status)` is not a slow query or an empty result, it
  is `PGRST200` and the whole merchants query fails. The customer app could not fetch a
  shop's picture at all, and `merchant_card.dart` passed a literal `LuqmaImage(url: null)`
  because there was nothing else to pass: the bucket, the upload, the moderation queue and
  the approval all worked, and every card in the city drew the tinted placeholder anyway.
  Added in `20260830010000_merchant_media_foreign_keys.sql`, `on delete set null` to match
  cuisines.
- **`watchRows` selects `*` unless told otherwise.** An embedded relation is fetched only
  if the caller passes `columns:` — so a repository that adds a join to `_readColumns` and
  forgets the watch fixes `getMerchant` and leaves the *customer's home list* with no
  picture, which is the screen that mattered.
- **An admin approving a future-dated promotion is asked which date is meant.** The
  merchant's form asks for a week from now; a request dated ahead is approved *into* that
  date, which is right and is also exactly what looked broken — the owner approved a
  banner and watched nothing happen. Starting it now keeps the length the merchant asked
  for rather than ending on the original date, which would shorten a campaign for the
  crime of being approved. The rule itself is unchanged: keep the date and it stays dark
  until then.
- **A promotion that starts tomorrow is invisible today, and nothing could move it.**
  The merchant's request form set `startAt` to `now + 1 day` on the reasoning that "the
  admin moves it when they approve" — and the admin screen has no date control, so nobody
  ever could. The owner approved a banner and watched nothing happen: correct by
  `isLiveAt`, wrong as a product. It starts `now` now. **`isLiveAt`'s rule is untouched** —
  a campaign genuinely meant for next week must still not go live early; what is missing
  is a way to *ask* for next week, which is a date picker neither screen has.
- **A merchant id is not a person, and both are uuids.** `promotions.requested_by` is
  `references auth.users`, and MerchantApp sent the *merchant's* id — so every promotion a
  merchant ever asked for was refused with `23503`, and the screen showed them the
  sentence for "somebody got there first". Nothing caught it because both values are
  uuids and every test on that path supplied a valid uid of its own instead of the app's:
  the live test passed `customerUid`, and the widget test asserted `merchantId` and never
  `requestedBy`. When a column references `auth.users`, the value is a *person* — assert
  which one, not merely that it is a uuid.
- **Never ask anybody to type a uuid.** The staff form's shop field was a free-text box
  labelled `رقم المطعم (UUID)`, and no screen in AdminApp displays a merchant's uuid or
  lets anyone copy one — so it could not be filled correctly and **no merchant or courier
  account could be created at all**. It is a picker of shop names now. The same rule holds
  for the promotions form: an id is something the app knows and a name is something the
  owner knows, and the form asks for the second.
- **A `test_live` failure that names a different test each run is the network, not the
  code.** The suite talks to a hosted project over the internet, and a request
  occasionally stalls and dies with `ClientException: Connection closed before full header
  was received`. Caught in the act on 2026-08-30: a test that began at `00:16` failed at
  `25:03` — a twenty-five minute hang on one request, against a file that passes on its
  own every time. Two settlement tests failed the same way an hour earlier and passed on
  three consecutive re-runs.
  Before hunting a bug: **re-run the file alone.** If it passes, and the failing name
  moves between runs, it is this. A real regression fails the same test every time. (In
  the app that same exception is classified as `OfflineFailure` and reaches somebody as
  "مفيش نت" — which is correct, and is why nothing in the product needs changing for it.)
- **`test_live` residue eventually breaks the suite at 1000 rows, not gradually.**
  PostgREST caps a response at `db-max-rows` (1000 by default) and `watchStaff()` asks for
  every row with no limit — so once accumulated test accounts pushed `staff` past 1098,
  `staff_repository_test` started failing because the account it had *just created* fell
  outside the returned page. Nothing about the code had changed; one run passed and the
  next did not. `tool/cleanup-cloud-test-residue.sql` took it back to 54 staff and 999
  auth users, from 1098 and 6410.
  **That script has to be kept current with new tables.** It predated `order_settlements`
  and `commission_payments`, both `on delete restrict` on `merchant_id`, so it would have
  failed on `23503` partway through and left the residue half-cleared — worse than not
  running. Run it inside a transaction, and add the delete for any new table that
  references a merchant or an order.
- **A tab switch is not a route, and Android back does not care.** All three shells show
  the next tab in place — an `IndexedStack`, which is what keeps scroll position and the
  inbox's live subscription — so once somebody is off the first tab the Navigator still
  holds exactly one entry. Back finds nothing to pop and the OS closes the app, which
  reads as a crash to whoever meant to step back one tab. `LuqmaTabPopScope` wraps each
  shell and returns to the first tab first; only from there is back let through.
  AdminApp had the same symptom by a different route: the module grid opened modules with
  `context.go`, which *replaces* the stack, so back from any module exited. It is
  `context.push` now. The rail on wide layouts still uses `go` on purpose — switching
  destinations there is lateral, and the rail is always on screen to get back with.
- **A test window is not a phone.** `flutter test` defaults to 800x600 — wider than it is
  tall, and unlike any device this ships on. Once merchant cards carried a picture the
  first card's name fell below 600 and every tap on it landed outside the render tree,
  which reads as "the card does not open" rather than "the window is the wrong shape".
  Size the view (`tester.view.physicalSize`) to what the app actually runs at. Doing so
  immediately surfaced a real overflow on the merchant screen that had been live on every
  narrow phone.
- **`test_live` needs the anon key too, not just the service key.** The harness defaults
  all three defines to the *local stack's* demo values, so a cloud run that passes only
  `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` silently keeps the demo anon key — which
  GoTrue on a real project rejects. Only `phone_auth_test` uses it, because it signs up
  the way a phone does rather than with the service key ("can an administrator make an
  account" is a different question), so the whole thing reads as *signup is broken* in
  exactly one file while the other 132 tests pass. `tool\run_tests.ps1` passes all three.
- **`opening_hours` had no editor anywhere, and it decides whether a shop trades.**
  The column has existed since the first schema; no screen in any of the three apps could
  write it. So a merchant whose hours were wrong — or empty — was shut with nothing on any
  screen that changed it, and `BusyToggle` correctly offered nothing, because a pause is a
  decision made two minutes ago and a schedule is not something a pause may override.
  `HoursScreen` in MerchantApp is the editor, and the closed bar now links to it: it still
  offers no "open now", which would silently rewrite the schedule, but it is no longer a
  dead end. **It writes 1..7 and can never emit a 0** — see the bullet below for why that
  matters.
- **A weekday is 1..7 on the server, and `generate_series(0,6)` is the wrong seven.**
  `merchant_open_at` maps Sunday to 7 exactly as `DateTime.weekday` does, so a fixture
  built from `generate_series(0, 6)` covers Monday to Saturday and leaves the shop **shut
  on Sundays**. `option_pricing.test.js` carried that from the day it was written and
  `tool/seed-demo.mjs` still does: nine tests failed with "merchant not accepting orders"
  on a Sunday and had passed every other day for weeks. Six runs in seven are green, so
  the seventh reads as a flake rather than as the bug it is.
- **Three tests failed on a date this week, all for different reasons, all the same
  mistake:** a fixture pinned to a fixed date read against a clock that moved. The
  promotions fake answered the push cap from `DateTime.now()` while its test pinned `now`;
  the merchant fixture above was shut one day in seven; and a daily-meal window once
  passed all morning and failed after four. If a suite fails and nothing changed, look at
  the calendar before looking at the diff.
- **A before/after delta is not immune to midnight.** `admin_today` counts from
  `date_trunc('day', now())` across the whole database, and the live suite takes sixteen
  minutes — so a run that starts before midnight and reaches that file after it reads
  `before` on one day and `after` on the next, and two tests fail on a delta that was
  written precisely to be robust against other rows. The file passes alone every time.
  Same lesson as the fixtures pinned to a fixed date, reached from the other end: when a
  suite fails and nothing changed, look at the clock as well as the calendar.
- **A live test cannot reach `clockProvider`.** The clock there is Postgres's. A daily-meal
  fixture with a 13:00–16:00 collection window passed all morning and failed after four —
  the rule it tripped was right, the fixture was asserting the hour. Seed windows that are
  open whenever the suite runs, and let the tests that are *about* the window move the
  clock themselves.
- **`scrollUntilVisible` loops until it finds the thing.** Pointed at something that is
  not in the scrollable it is scrolling, it does not fail — it hangs, and the suite looks
  like a slow machine rather than a broken test.
- Rules read claims with **`token.get('x', default)`**. A bare `token.admin` errors on a
  token with no custom claims — every customer — and fails the branch it sits in for a
  reason unrelated to access.

- **`luqma-test` fell 34 migrations behind production, and that hid a real bug for a
  week.** Nothing pushed migrations to it after 2026-09-11, so the stack and live suites
  kept passing against an old schema. When it was brought up to date on 2026-09-19 they
  found `hold_prepaid_credit` releasing a prepaid hold without declaring server mode — so
  no prepaid order could be delivered, refused or cancelled by the person doing it — and a
  coupon guard that refused the service key. **Push every migration to `luqma-test` before
  production** (`npx supabase db push --db-url <luqma-test session pooler>`), and run
  `tool\run_tests.ps1`; a green suite against a stale schema proves nothing.
- **A function that writes a table nobody is granted must be `security definer`.**
  `payment_receipts` grants no insert, by design; `top_up_wallet` ran as the caller and so
  every receipt-bearing payment from a real admin token failed, while every owner-run test
  passed. Test money paths through `set role authenticated`.
- **Rewriting a function in place beats listing its signature.** The moderator migration
  narrows 14 money and deletion functions, which live across eight migrations and have
  had their argument lists changed twice — `top_up_wallet` alone has four versions in the
  history. Naming each signature by hand is where a typo leaves a door open and nothing
  says so. It reads `pg_get_functiondef`, swaps `public.is_admin()` for
  `public.is_platform_admin()`, and executes the result, so overloads and defaults come
  along and the grants and the owner survive a `create or replace`. **Verify by reading
  the functions back**, not by trusting the loop: the dry-run against a real Postgres
  counts all fourteen before anything is pushed.
- **Grant on `isPlatformAdmin`, take away on `isModerator`, and they are not one question
  asked twice.** `StaffIdentity.none` is neither — so asking "is this a strict admin?"
  in order to *hide* something hides it from an identity that has not resolved yet, and
  AdminApp's rail shed six modules for the moment a token spends refreshing. A widget
  test that granted access without supplying an identity is what caught it, and it was
  a real defect rather than a test artefact.
- **A channel the phone has never created is not dropped — it falls back, and on a staff
  app the fallback is the alarm.** `commissionDue` and `promotionRequest` are written on
  the `orders` channel deliberately, and neither MerchantApp nor AdminApp had ever created
  one, so FCM used the manifest default: `orders_critical`, which bypasses Do Not Disturb
  and in MerchantApp plays the looping alarm on the **alarm stream**. The Saturday
  commission reminder rang the kitchen. The trigger's own comment had warned that sharing
  the alarm teaches somebody to ignore it — the intent was right and the effect was the
  thing it warned against. `push_channels_test.dart` scans the Kotlin and the manifests,
  because nothing in Dart can observe this and the failure only shows up on a handset
  weeks later.
- **A comment that says "settled rather than retried" is not a settlement.** `send-push`
  reports a recipient with no registered device as an error; `settle_push` records the
  error and never sets `sent_at`, so the row came back on the next minute's cron and died
  five attempts later — about five minutes after it was written. Seven rows on production
  went that way, five of them join applications to the owner. **The count was never the
  problem, the spacing was**: `next_attempt_at` and `push_retry_delay` now spread the same
  five attempts over roughly seven hours, which is long enough for somebody to install the
  app that evening and short enough that nothing stale ever lands.
- **An index is earned, not assumed — and the plan is how it is earned.** M-12's first
  draft added `orders (merchant_id)`. `orders_merchant_status_idx` has led with
  `merchant_id` since the first schema, and `EXPLAIN` against `luqma-test` showed the
  planner using it: a second index would have been a write on every order placed, buying
  nothing. Twenty-one foreign keys in this schema have no covering index
  (`node supabase/fk-index-audit.mjs prod` lists them) and exactly five were given one.
  The rule: **index the key when the child table grows without bound and the parent is
  deleted by a path somebody is waiting on.** `app_opens` is the case in point — a row per
  device per app per day, and `delete_my_account` nulls `uid` across all of it while a
  customer watches a spinner.
- **A count on a list and a count on a delete button are different queries.** The
  merchants list asks `admin_merchant_order_counts` once for the whole city; the detail
  pane keeps its own exact per-shop count, because `orders.merchant_id` is
  `on delete restrict` and a figure fetched when the list was built would offer a delete
  the database then refuses with `23503`, after the admin has confirmed. One is a label
  and one is a decision.
- **Widening a predicate reaches every policy that reads it, including ones in a schema
  you did not enumerate.** `refuse_moderator_delete` went on 25 tables in `public`, chosen
  by reading the `for all` policies in the migrations. `storage.objects` is in another
  schema, and two policies on it are gated on `is_admin()` — so widening that function for
  H-08 handed a moderator the delete on **every courier's national ID photograph and every
  image in the product**, for the hour between the two migrations. Nothing was exposed
  (production had no moderator, and still has none), which is luck rather than design.
  The fix is the method: enumerate with a catalogue query, never by reading migrations.
  `pg_policy` joined to `pg_class` and `pg_namespace`, asking which delete-capable
  policies mention the predicate and which of those tables carry the guard. That query
  found both, and it is an assertion in `supabase/test/stack/staff_documents.test.js` now
  rather than a note here.
- **On hosted storage a direct SQL delete never reaches RLS.** `storage.protect_delete()`
  raises 42501 first unless the caller names `storage.allow_delete_query`, so a stack test
  that asserts a policy by attempting a delete is testing Supabase's guard and not ours —
  and the path a client really takes is the Storage HTTP API, which consults the policy
  expression. Assert the expression.
- **Removing a courier's papers is an act with a name on it.** H-03: an admin could delete
  the objects straight from the client and nothing recorded it, which breaks the rule H-09
  settled. `admin_delete_staff_documents(uid, reason)` is the only way now — a **required**
  reason, the bytes and the row and the audit entry in one transaction, and
  `storage.allow_delete_query` put back afterwards. It removes **all three**, because the
  three paths are `not null`, written as a set, and the approval trigger asks whether the
  row exists at all: there is no state in the product for "two papers on file", so an
  unacceptable photograph means the papers are handed in again. The first draft nulled one
  column and the test refused it — bending the schema to fit the API first imagined would
  have rippled a nullable column through the approval guard, the queue and the sheet.
- **A trigger is the safe way to take back a verb that `for all` handed out.** Twenty-five
  tables carry a `for all` policy gated on `is_admin()`, so widening that function opened
  the delete on every one of them at once. Splitting twenty-five policies into
  select/insert/update is twenty-five chances to widen something by accident; a trigger
  only ever refuses, so the worst a mistake in it can do is stop an admin deleting
  something — which is loud. It lets `app.server_mode` through, because cascades and
  scheduled work declare it and a guard that stopped those would break account deletion
  for everybody.

## Coupons

Added after the design pass. One code per order, never two. Three types — percentage,
fixed amount, free delivery. A percentage **must** carry a maximum discount or it is
refused: uncapped, a 15% code on a 2000 EGP order costs the merchant 300 against the 30
they had in mind.

`fundedBy` decides who pays. This matters more here than elsewhere because the money is
cash: a discount is simply less cash reaching the merchant, so a platform-funded campaign
is a debt from the moment the order is placed, accrued as `pricing.platformOwesMerchant`.

Coupon documents are **unreadable by any client** — a readable collection is one anyone
can enumerate. The app calls a function that returns the discount for one basket.

## Revenue settlement, built 2026-08-29

For eight phases the platform recorded what it would charge and charged nothing:
`wallet_balance` was only ever added to, `commission_owed` had never been written by
anything, and `pricing.platformOwesMerchant` was computed by `place_order`, frozen onto
the order, and read by no statement anywhere. `onOrderDelivered` left with Firebase.

`20260829000000_settle_delivered_orders.sql` is the replacement. The table is
`order_settlements`, one row per delivered order; `docs/10-monetization.md` has the
model-by-model table and `docs/17` the design note.

Four things that are easy to undo by accident:

- **`order_id` is the primary key, and that is the guard.** A trigger inside the status
  transaction cannot be *missed*; it can still run twice — a retry, a second write of the
  same status, an admin touching a neighbouring column with `status` in the `set` list.
  Atomicity is not idempotence. The `when (old.status is distinct from new.status)` clause
  is the other half.
- **Both functions are `security definer`, and each for a different reason.**
  `apply_order_settlement` writes `merchants`, which a courier has no rights on;
  `settle_on_delivery` is the *trigger*, which runs as whoever ran the statement — the
  courier — and calls a function revoked from `authenticated`. Without the second one,
  marking an order delivered fails outright from the street with "permission denied for
  function". Granting the settlement to `authenticated` would make the same symptom go
  away by letting anybody charge any merchant.
- **`apply_order_settlement` declares `app.server_mode` and puts it back.**
  `security definer` does not satisfy `guard_columns`, which asks whether a trusted server
  function has declared itself, not who owns the function. And the setting is
  transaction-local inside somebody else's transaction, so leaving it standing would stand
  every guard down for whatever that transaction did next.
- **`order_settlements.order_id` is `on delete restrict`.** A settlement is evidence of a
  charge, and the order must not be able to take it with it. Nothing in the product deletes
  an order; the teardowns in `test_live/harness.dart` and `supabase/test/stack/` delete
  settlements first, and a new one that forgets fails on `23503`.

**Both defects above were found by one test** — delivering as a real courier token rather
than with `app.server_mode` on, which every other test in the suite used. Twenty-three
tests passed against a settlement that would have failed for every courier on every
delivery. The suite was testing the path nobody takes.

**Both sides can read it now.** `StatementScreen` in MerchantApp is كشف الحساب — two tabs
under one summary, الشحنات and المدفوعات — reached from the billing card and drawn only
when something is actually taken per order — under a
subscription it would be a page of zeroes, and a screen that says nothing every time is
one somebody stops believing when it finally has something to say. AdminApp's billing
screen carries the same figures per merchant, because collecting `commission_owed` is a
person with a receipt and the person needs a number to ask for.

What the platform *owes* stays its own figure on both screens rather than being netted
against the commission. They are two different conversations, and collapsing them into one
number is how a merchant stops being able to check either.

**Collection landed 2026-08-30** — `20260830000000_collect_commission.sql`.
`record_commission_payment` writes a `commission_payments` receipt, lowers
`commission_owed`, and logs who took it; the admin records it from the billing screen.

Three things in it that look like details and are not:

- **`commission_payments` has no write policy at all, and the function is
  `security definer`.** An insert policy for admins would let one write a receipt without
  moving the balance — paper saying money changed hands while the account says otherwise,
  which is what a receipt exists to rule out. The function does both halves or neither.
- **The actor is `auth.uid()`, never a parameter.** Same lesson as the audit's finding on
  `record_subscription_payment`: a log that can be lied to is not evidence.
- **The amount is not capped at what is owed**, so the balance can go negative. That is
  credit, and both screens say so in words rather than printing a minus sign.

## Known debts from the audit

Deliberately deferred rather than fixed in this pass; each one is the smaller, safer
choice against the risk of touching a live boundary without being able to prove it here:

- **L2** — `subscriptions.settled_at` and its partial index are left alone. Dropping a
  column in a migration for a system with no production data would be safe, but the
  nightly pass still reads it, and removing it is churn with no reader.
- **L3** — `markDelivered` stamps `delivered_at` from the client clock. Making it server
  time needs a `SECURITY DEFINER` RPC plus a repository and fake change; that is more
  than the finding is worth right now, and the client clock is the courier's own device.
- **L5 — done, 2026-08-26.** The staff read policy tested `belongs_to_merchant`, which
  is true for an owner *and* their courier: a rider could read every account under the
  shop, the owner's phone number included. It reads `is_merchant_owner` now, and six
  tests in `supabase/test/stack/rls.test.js` say so — the policy had none before.
- **L1 / L4 / L6 / L8** — recorded, not fixed: low-severity findings whose only correct
  home is a stack or a design pass, not a PGlite-only change.

## Deferred, deliberately

**AdMob.** It ships off behind `admobEnabled`, and building an integration nobody can
switch on — Google's network would serve competitor ads inside the app, weakening the
pitch to merchants paying for placement — is work with no reader. The flag exists; the
decision stays reversible. See `docs/15-simplifications.md`.

**The audit's L1 / L3 / L4 / L6 / L8.** Recorded, not fixed: low-severity findings whose
only correct home is a stack or a design pass.

`prepaid` shipped filled in — that decision is closed.

## Stack

Flutter (Android first, iOS and Web later from the same code) · Firebase Auth, Firestore,
Storage, FCM, Remote Config, Cloud Functions · `luqma_core` shared package holds models,
repositories, `RemoteConfigService`, theme, l10n, and the shared `MenuEditor`,
`AddressPicker` and `LuqmaLockup` components.
