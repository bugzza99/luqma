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

- **`staff` management waits on Blaze.** Creating a staff account means creating a Firebase
  Auth user, which only a server can do. Nothing else in AdminApp needs Cloud Functions.
- **The zone and landmark names in `firebase/seed/edku.json` are placeholders.** They are
  structurally correct but not local knowledge. The owner replaces them; a wrong zone name
  sends a courier to the wrong part of town.

**Next: Phase 3 — CustomerApp core.**

### Infrastructure

Firebase project **`luqma-edku`**, Firestore in **`europe-west3`** — the location is
permanent and cannot be changed. Three Android apps registered:
`com.luqma.customer`, `com.luqma.merchant`, `com.luqma.admin`.

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
```

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
| `packages/luqma_core/` | Models, repositories, config, theme, l10n, brand widgets |
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
