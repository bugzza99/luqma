# Dynamic Configuration Layer

The requirement: the owner changes offers, plans, revenue rules, ad slots and home screen
composition **without shipping an app update**. The chosen scope is
**values + home screen composition**, deliberately NOT full server-driven UI.

## Two sources, one service
`RemoteConfigService` in `luqma_core` merges two sources behind a single API:

1. **Firebase Remote Config** — low-frequency global switches and numbers.
   Feature flags: `otpEnabled`, `admobEnabled`, `publicCommentsEnabled`, `onlinePaymentEnabled`.
   Limits: `acceptTimeoutMinutes`, `marketingPushPerWeek`, `rejectionBanThreshold`,
   `minRatingsToShow`, `deliveryFeeMin`, `deliveryFeeMax`, `splashMinMillis`.
   `deliveryFeeMin` and `deliveryFeeMax` are mirrored into Firestore Security Rules, which is
   where a merchant's `deliveryFeeOverride` is actually clamped.
   Force update: `minSupportedVersion`, `updateMessage`.
2. **Firestore `homeSections` + `plans` + `promotions`** — content that changes often and
   needs live propagation and rich structure.

Every app reads flags only through `RemoteConfigService`. No widget reads Remote Config directly.
Defaults are compiled in, so a cold start with no network still renders a correct app.

## Home screen composition
`homeSections` documents define what the customer home screen renders and in what order.
Supported `type` values, each mapped to a registered Flutter widget builder:
`categoryChips`, `homeKitchenToday`, `merchantList`, `topRated`, `mostOrdered`, `adSlot`.

There is one promotional type, not two. An earlier draft had both `banner` and `adSlot`, which
were the same slot with two names and no separate content source once promotions merged into
one collection. `categoryChips` replaces `categoryGrid`: the customer home shows categories as
a scrollable chip row, and making it a section rather than fixed chrome means the admin can
reorder or hide it like everything else on the screen.

The app holds a **section registry**: `Map<String, Widget Function(params)>`. The server picks
which registered types appear, their order, visibility and parameters. It cannot invent a new
widget type — that is the deliberate boundary that keeps this from becoming server-driven UI.
An unknown `type` renders nothing and logs, so a bad admin entry can never crash the app.

## Revenue model switching
`merchants.revenueModel` is per-merchant and admin-editable: `subscription`, `commission`, or `prepaid`.
`RevenueEngine` (a Cloud Function module) reads it at order creation and writes `revenueSnapshot`
onto the order. Changing a merchant's model affects only future orders.

## Feature flags that ship OFF
- `otpEnabled` — phone OTP verification is fully built and disabled at launch.
- `admobEnabled` — AdMob integration is fully built and disabled at launch.
- `publicCommentsEnabled` — rating comments stay private for roughly the first six months.
- `onlinePaymentEnabled` — reserved for the later payment gateway.
