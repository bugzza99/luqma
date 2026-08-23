# CustomerApp

Flutter Android app. Depends on `luqma_core`. Arabic RTL only.

## Navigation — 3 bottom tabs
`الرئيسية` (Home) · `طلباتي` (Orders) · `حسابي` (Account)

There is no Categories tab. Edku will have on the order of thirty merchants, which a
category tab cannot fill; categories become a chip row inside Home, and search covers the
rest. Three tabs give larger targets and one less place to be lost in.

Home Kitchen is a **large prominent section at the top of Home**, not a tab — it is the
differentiator and must be seen without a tap.

## Screens
- **Splash** — single continuous splash. The Android system splash shows the mark on the brand
  background; the Flutter first frame continues from that exact position and the wordmark fades in
  beneath it, forming the stacked lockup. Total ~1.5s, cut short as soon as the app is ready.
- **App bar** — the horizontal `LuqmaLockup` on the right, the selected delivery zone on the
  left. The lockup is the SVG asset, not text.
- **Home** — a fixed search bar, then every remaining block rendered from `homeSections`:
  `categoryChips`, `adSlot`, "أكل بيتي النهارده" (`homeKitchenToday`), `mostOrdered`,
  `merchantList`. Only the search bar is fixed chrome; everything below it is admin-ordered,
  including the category chips.
- **Merchant** — cover, rating (hidden below `minRatingsToShow`), working hours, menu by category.
- **Item detail** — options, quantity, notes.
- **Cart** — merchant-scoped, shows subtotal, delivery fee resolved from zone, minimum order check.
- **Address picker** — one `AddressPicker` component: zone, landmark, free-text note,
  building/floor/apt, optional branded map pin. Zone drives delivery fee and merchant
  availability.
- **Checkout** — cash only, order summary, place order.
- **Order tracking** — status timeline, merchant phone, "في مشكلة في الطلب" button creating an `orderIssue`.
- **Orders history**, **Ratings prompt** after delivery, **Account** with addresses, notification
  preferences (marketing only), WhatsApp support link.

## Auth
Google Sign-In at launch. Phone number collected once at first checkout, stored unverified.
When `otpEnabled` flips on, OTP becomes a verification layer over the same account — no user
loses their history or addresses.

## Promotions surface
Renders `promotions` in `adSlot` sections and boosted merchants in listings, through one
`PromotionBanner` component that switches on `renderMode`: `text` on a burgundy gradient,
`image` full-bleed, or `imageWithText` with a scrim. All three occupy the same 3:1 slot, so a
section's height never jumps as banners rotate. AdMob widgets exist behind `admobEnabled` and
render nothing while it is off.
