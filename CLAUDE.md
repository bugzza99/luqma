# لقمة (Luqma)

Local food-ordering marketplace for the city of **Edku** (إدكو), Beheira, Egypt.
Restaurants plus home kitchens. Three Flutter Android apps on one **Supabase** backend.

> **The Firebase → Supabase migration is complete** (see `docs/17-supabase-migration.md`
> and `supabase/migrations/`). Every repository, auth and remote config now run on
> Postgres/GoTrue/Realtime; the `firebase/` and `functions/` directories are gone.
> Google Sign-In additionally requires the OAuth web client id at build time:
> `--dart-define=LUQMA_GOOGLE_WEB_CLIENT_ID=<id>` (and Google enabled as a provider in
> the Supabase dashboard).

## The cloud project

**Project `luqma-edku` — ref `vqcivwdoekyfqhfmnuos`, Frankfurt (eu-central-1), free tier.**
Linked from `supabase/`; the dashboard is at
`https://supabase.com/dashboard/project/vqcivwdoekyfqhfmnuos`. The database password is in
`supabase/.temp/db-password.txt` (gitignored) — move it to a password manager.

Production builds point the apps at it with dart-defines:

```
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

The live repository suite runs against the cloud exactly as against the local stack:

```
flutter test test_live --dart-define=SUPABASE_URL=https://vqcivwdoekyfqhfmnuos.supabase.co \
  --dart-define=SUPABASE_SERVICE_KEY=<service_role key>
```

All 125 passed against the hosted project on 2026-08-25.


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

- **Google Sign-In is configured, but has never run on a device.** Google is enabled as
  a provider, the debug key's SHA-1 is registered against `com.luqma.customer`, and the
  web client id is in `LuqmaFirebase.googleServerClientId`. `firebase apps:sdkconfig`
  now reports a type-1 (Android) and a type-3 (web) client for that app. What has not
  happened is a real sign-in on a real phone — that is the only thing that proves it.
  AdminApp and MerchantApp sign in with email and password, so neither needs a
  fingerprint. **The release keystore does not exist yet**; its SHA-1 is a different
  fingerprint and must be registered before the first Play Store build. That belongs to
  Phase 9.
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

### Infrastructure

Firebase project **`luqma-edku`**, Firestore in **`europe-west3`** — the location is
permanent and cannot be changed. Three Android apps registered:
`com.luqma.customer`, `com.luqma.merchant`, `com.luqma.admin`. Those are the Gradle
`applicationId`s too — an application id is permanent once an app is published, and it
is half of what an OAuth client is keyed on. The Flutter template's `_app` suffix was
wrong and was corrected in Phase 3.

**Deliberately still on the Spark plan.** Cloud Functions and Cloud Storage both need
Blaze, so neither is deployed. Everything is built and tested against the local emulator
instead, which costs nothing and does not need a card.

That is a decision, not an oversight — Blaze gets enabled when there is something to ship
to real merchants, not before. Two things are blocked until then, and both matter: an
order's total must be computed server-side (a total computed on the phone is a total
anyone can edit, and the courier collects whatever the screen says), and no image can be
uploaded at all without Storage. Neither blocks development.

When the time comes: enable Blaze, then Storage — in that order, because a new project's
default bucket needs Blaze first. Set a small budget alert at the same time; the real risk
is not usage, it is a function that calls itself.

### Running the checks

```
cd packages/luqma_core && flutter gen-l10n && flutter analyze && flutter test
npm --prefix functions test
npm --prefix supabase test          # schema and seed, on PGlite — no Docker needed
npm --prefix supabase run test:stack # the boundary, against a running `supabase start`
```

`supabase test` runs on **PGlite**, Postgres compiled to WebAssembly: the real migrations,
the real constraint machinery, no container. `test:stack` needs `supabase start`, because
policies, `auth.uid()` and the claims hook only exist in the real thing.

**The local stack sits 1000 above the Supabase defaults** — 55321 for the API, 55322 for
the database. Windows reserves 54084-54683 for Hyper-V on this machine and that swallows
every one of them; check yours with
`netsh interface ipv4 show excludedportrange protocol=tcp`.

`gen-l10n` first on a fresh clone, and after any change to `lib/l10n/app_ar.arb`.
The generated `app_localizations*.dart` are gitignored — generated code does not belong
in the repository — and `flutter test` on a *package* does not run the generator itself
the way an app build does. Without it a new string is a compile error that points at the
call site rather than at the missing step.

**840 Dart tests · 45 function tests · 98 rules tests.** `flutter analyze` and `tsc`
clean. The rules count nearly doubled in the audit: it was the thinnest layer in the
project and the one carrying the most weight.

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
| `firebase/scripts/staff.js` | Creates merchant, courier and admin accounts. No Blaze needed |
| `brand/src/build_alarm.py` | The new-order alarm, and why every number in it is what it is |
| `packages/luqma_core/` | Models, repositories, config, theme, l10n, brand widgets, Firebase options |
| `apps/customer_app/` | CustomerApp — home, merchant, basket, checkout, orders, account, أكل بيتي |
| `apps/merchant_app/` | MerchantApp — inbox, live board, menu, shop, courier mode |
| `apps/admin_app/` | AdminApp — merchants, menus, places, media, billing, promotions, home builder |
| `firebase/firestore.rules` | The real security boundary — read its tests beside it |
| `firebase/test/` | Rules tests, run against the emulator |
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
- **OTP is built and off** behind `otpEnabled`. Google Sign-In at launch, phone captured
  unverified at first checkout.
- **The brand name is never a text widget.** It is `LuqmaLockup`, backed by SVG. Lemonada is
  not a bundled font. Cairo renders everything else.
- **The owner enters merchant menus and shoots photos personally.** Merchants never self-onboard.
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

## Deferred, deliberately

**The nightly billing pass reads the whole `subscriptions` collection.** The obvious fix —
querying only expired rows — is *wrong*, not merely narrower: whether an expired term
still counts depends on whether a **later** row exists for the same merchant, and a query
for expired rows cannot see the renewal that makes them irrelevant. It would downgrade
merchants who had just paid.

The real fix belongs to Phase 9 and is a data-model change: put the term's end date on the
merchant — `merchants.planExpiresAt` — so there is one current truth instead of N
historical rows. Then `where('planExpiresAt', '<=', now)` is bounded *and* correct, and
the downgrade **deletes the field**, which removes that merchant from the next night's
query by itself: a document missing the field does not match a range filter. No flag, no
memory. `subscriptions` goes back to being receipts, read when somebody asks about
history rather than every night.

Until then the code is correct and merely wasteful, and Edku is a few dozen rows.

`prepaid` shipped filled in — that decision is closed. See `docs/15-simplifications.md`.

## Stack

Flutter (Android first, iOS and Web later from the same code) · Firebase Auth, Firestore,
Storage, FCM, Remote Config, Cloud Functions · `luqma_core` shared package holds models,
repositories, `RemoteConfigService`, theme, l10n, and the shared `MenuEditor`,
`AddressPicker` and `LuqmaLockup` components.
