# لقمة (Luqma)

Local food-ordering marketplace for the city of **Edku** (إدكو), Beheira, Egypt.
Restaurants plus home kitchens. Three Flutter Android apps on one Firebase backend.

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
- **The zone and landmark names in `firebase/seed/edku.json` are placeholders.** They are
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

**Next: Phase 8 — Promotions and the dynamic home.**

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
cd packages/luqma_core && flutter analyze && flutter test
npm --prefix functions test
```

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
| `graphify-out/graph.html` | Dependency graph, open in a browser |
| `brand/identity.html` | Logo, palette, type and screen mockups |
| `brand/README.md` | How the logo assets are generated, and why |
| `firebase/scripts/staff.js` | Creates merchant, courier and admin accounts. No Blaze needed |
| `brand/src/build_alarm.py` | The new-order alarm, and why every number in it is what it is |
| `packages/luqma_core/` | Models, repositories, config, theme, l10n, brand widgets, Firebase options |
| `apps/customer_app/` | CustomerApp — home, merchant, basket, checkout, orders, account, أكل بيتي |
| `apps/merchant_app/` | MerchantApp — inbox, live board, menu, shop, courier mode |
| `apps/admin_app/` | AdminApp — merchants, menus, places, media queue |
| `firebase/firestore.rules` | The real security boundary — read its tests beside it |
| `firebase/test/` | Rules tests, run against the emulator |

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
- The merchant is derived from the **`merchantId` custom claim**, never from a Firestore
  field — that is what `firestore.rules` checks, and only a server can issue a claim.
- **`ownsMerchant()` is not "runs this merchant".** An owner and their courier carry the
  same claim. Anything that acts for a merchant uses `isMerchantOwner()`.
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

## Open decision

`prepaid` is the third revenue model. The switch and `revenueSnapshot` ship complete;
whether the branch ships filled in or as a stub is the owner's call, due before Phase 7.
See `docs/15-simplifications.md`.

## Stack

Flutter (Android first, iOS and Web later from the same code) · Firebase Auth, Firestore,
Storage, FCM, Remote Config, Cloud Functions · `luqma_core` shared package holds models,
repositories, `RemoteConfigService`, theme, l10n, and the shared `MenuEditor`,
`AddressPicker` and `LuqmaLockup` components.
