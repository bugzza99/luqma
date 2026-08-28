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
powershell -ExecutionPolicy Bypass -File tooluild-apks.ps1
```

It fetches the anon key from the linked project rather than having it pasted, carries the
Sentry DSN, builds arm64-only split APKs for all three apps, and drops them in `apks/`.
Both values are public by design — the anon key is what every phone carries and RLS is
what protects the data, and a Sentry DSN can only *send* events, never read them.
flutter build apk --dart-define=LUQMA_SUPABASE_URL=https://vqcivwdoekyfqhfmnuos.supabase.co \
  --dart-define=LUQMA_SUPABASE_ANON_KEY=<anon key, supabase projects api-keys>
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

137 live tests and 109 stack tests passed against `luqma-test` on 2026-08-28.


**The design is finished and verified. Read `docs/` before changing anything.**
Those documents are the specification, not notes — every decision in them was argued through
with the owner and cross-checked. If something here seems arbitrary, the reason is written down.

## Status

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

Still open, none of it code:

- Play Console account, listings, and enrolling Play App Signing with this key.
- Onboarding the first 10–15 merchants at zero commission.
- Running the three apps on a real handset. They have been built many times and
  installed never, which is its own kind of untested.

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
  one spelling and is shared with validation and with the admin's search. An Arabic
  keyboard produces `٠١٠…` where the account was made with `010…`; two spellings reaching
  two accounts is one person with half their orders on each and no way to see the rest.
- **The synthetic address is never shown.** `_toIdentity` returns a null `email` for one
  ending in the reserved domain, so no screen can leak it by rendering `identity.email`.
- **The real number rides in the signup metadata**, and `ensure_user_profile` copies it —
  with the name — onto the `users` row. That row is where `place_order` reads the number
  it stamps on the order, which is the number the courier calls. A trigger that only
  inserts the id, as it did before, means a courier at the right door with nobody to ring.
- **A forgotten password has exactly one way back, and it is a person.** No mailbox, no
  SMS: the customer calls, and an admin issues a new password from the customers screen
  (`reset-customer-password`, deployed). It is generated server-side from an alphabet with
  no `l`/`1`/`O`/`0`, because it is read down a phone line — and returned once, never
  stored. That function refuses a uid that has a `staff` row: a support call must not
  become a way to reset another admin.

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

**~830 Dart tests · 66 schema tests · 109 stack tests · 137 live-repository tests.**
`flutter analyze` clean.

There are no `function` tests and no `tsc`: the TypeScript Cloud Functions went with
Firebase, and what they did is now Postgres functions covered by `supabase/test/stack`.
The Dart count fell because roughly a hundred tests that existed only to argue with
`fake_cloud_firestore` were replaced by `test_live`, which argues with a real database —
fewer tests proving considerably more.

`kotlin.incremental=false` is set in both apps' `android/gradle.properties`. Kotlin's
incremental compiler cannot close its caches on this drive and fails every plugin module
without it.

The rules tests need JDK 21+, which is not the system default here — Android Studio's
bundled runtime is:

```
JAVA_HOME="C:\Program Files\Android\Android Studio\jbr" firebase emulators:exec --only firestore "node --test firebase/test/*.test.js"
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

- **Cash on delivery only.** The model is payment-method aware for later, nothing more.
- **Arabic RTL only**, with i18n scaffolding so English is a file, not a rewrite.
- **Western numerals** for prices (`150 ج`), not Eastern.
- **Multi-city data model, Edku-only launch.** Everything carries `cityId`.
- **No driver app.** Courier is a mode inside MerchantApp, driven by `staff.role`.
- **AdminApp never goes on Google Play.** Direct APK.
- **Dynamic means values plus home-screen composition** — never full server-driven UI.
  The section registry is a fixed map of widget builders; the server picks and orders them.
- **AdMob ships off** behind `admobEnabled`. Merchant-sold promotions come first.
- **A customer signs in with a phone number and a password.** No Google, no email field
  anywhere in CustomerApp. OTP stays built and off behind `otpEnabled`, so the number is
  captured rather than verified and the password is what protects the account.
- **The brand name is never a text widget.** It is `LuqmaLockup`, backed by SVG. Lemonada is
  not a bundled font. Cairo renders everything else.
- **The owner enters merchant menus and shoots photos personally.** Merchants never self-onboard.
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

## Rules that are easy to break by accident

- Orange `#D67F2B` fails contrast on the cream background (2.58:1). Prices sit on **white
  cards at 18sp+**; anything smaller or on cream uses `priceStrong #995A1D`.
- Orange badges carry **dark text `#130B07`**, never white (3.03:1 fails).
- Interactive outlines use `borderStrong #A5794F`. `#D6BFA9` is decorative hairlines only.
- Cards are **white with a soft shadow**, never `Surface #E5D3C1` — it is invisible on cream.
- No colour is written in a screen. Everything comes from tokens in `luqma_core`.
- Minimum body text is **15sp**, not 14. Arabic loses legibility faster than Latin.
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
- **Approved is not live.** `startAt` decides that — a campaign signed off today for next
  week must not appear the moment somebody approved it.
- A promotion with **no zones reaches the whole city.** A merchant who did not narrow
  their campaign meant everybody, not nobody.
- The **push cap is on the city, not the merchant.** What is being rationed is a
  customer's patience, and it does not care which shop the third notification came from.
- The merchant is derived from the **`merchantId` custom claim**, never from a Firestore
  field — that is what `firestore.rules` checks, and only a server can issue a claim.
- **`ownsMerchant()` is not "runs this merchant".** An owner and their courier carry the
  same claim. Anything that acts for a merchant uses `isMerchantOwner()`.
- **A rule that allows less than the query asks for returns nothing, not less.**
  Firestore rejects a whole query it cannot prove is limited to readable documents. Every
  query in a repository needs a rules test that runs *that query*, not a test that reads
  one document — the two fail differently and only one of them resembles production.
- **`allow write` covers delete, and on a delete `request.resource` is null.** A rule
  written on `request.resource.data.merchantId` refuses every merchant and lets only the
  admin through. Create and update are judged on what is arriving; delete can only be
  judged on what is already there.
- **On an update, check the owner already on the document.** `isMerchantOwner(request.
  resource.data.merchantId)` reads the *incoming* value, so rewriting it to your own id
  passes — one merchant could move another's menu item into their own shop.
- **The fakes are not the system.** They are more permissive than Firestore plus the
  rules, so a green suite proves the screens work against the fake and nothing more.
  Anything that depends on a rule needs a rules test beside the widget test.
- **Nothing writes `PromotionStatus.active`.** Whether a campaign is running is a
  question about `startAt`/`endAt` — use `isLiveAt`, never the status alone.
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
