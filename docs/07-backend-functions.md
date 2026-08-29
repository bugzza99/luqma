# Cloud Functions

## Triggers
- `onOrderCreate` — assigns `orderNumber` from `counters`, writes `revenueSnapshot` from
  `merchants.revenueModel`, sets `acceptDeadlineAt`, **enqueues one delayed task** for the
  accept deadline, sends the high-priority merchant notification, flags `isNewCustomer`.
- `onOrderStatusChange` — notifies the customer, and on `delivered` invokes `RevenueEngine`.
- `onOrderCancelled` — when cancelled at the doorstep, increments `users.rejectedOrdersCount`
  and auto-blocks at `rejectionBanThreshold`.
- `onRatingCreate` — recomputes `merchants.ratingAvg` and `ratingCount`.
- `onMediaUpload` — compresses to WebP, generates a thumbnail, writes the `media` document
  with `status = pending`. One trigger covers logos, covers, menu photos, meal photos and
  promotion banners, because they are all `media`.
- `onDailyMealReserve` — transactional decrement of `dailyMeals.remainingQty`; prevents overselling.

## Deferred task
- `checkAcceptDeadline(orderId)` — enqueued once per order at creation, fires after
  `acceptTimeoutMinutes`. If the order is still `placed`, it moves to `needsAttention` and
  alerts the admin.
  This replaces a one-minute cron. A cron would run about 43,000 times a month to service
  perhaps fifty orders a day; one task per order runs exactly as often as there are orders.
  The countdown the merchant sees is rendered from `acceptDeadlineAt` on the client and needs
  no server tick at all.

## Scheduled (daily, one function)
- `dailyMaintenance` — expires subscriptions and downgrades those merchants to the Free plan,
  ends promotions past `endAt`, and closes yesterday's daily meals.
  These were three separate daily schedulers doing three independent passes at the same hour.

## Callable
- `sendPromotionPush` — admin-only; sends an approved `promotions` document whose channel is
  `push`, and enforces `marketingPushPerWeek`.
- `recordSubscriptionPayment` — admin-only; writes the subscription and the audit entry.
- `createStaffAccount` — creates the Firebase Auth user and the matching `staff` document in
  one server-side step, then returns a one-time sign-in code. An admin may create any staff
  role; a merchant owner may create only a `courier` scoped to their own `merchantId`, which
  the function verifies rather than trusting the caller. Clients cannot create auth accounts
  safely, so both AdminApp's Staff screen and MerchantApp's Couriers screen go through here.
- `setStaffActive` — activates or deactivates a staff account and revokes its refresh tokens,
  so a deactivated courier loses access immediately rather than at token expiry.

## RevenueEngine
A pure module invoked by triggers, not a collection. Reads `revenueSnapshot` and applies:
`subscription` → no per-order accounting; `commission` → accrue `commissionAmount`;
`prepaid` → decrement `merchants.walletBalance` and suspend order intake at zero balance.
Keeping it pure and snapshot-driven is what makes the revenue model safely switchable at runtime.

**Build note:** the switch, the snapshot and the `subscription` and `commission` branches are
cheap and ship in Phase 7. The `prepaid` branch carries the real cost — a wallet balance,
top-up recording, and intake suspension — and nothing uses it until online payment exists.
It is the one branch worth leaving as a stub behind the same switch.
