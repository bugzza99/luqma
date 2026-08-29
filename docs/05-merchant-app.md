# MerchantApp

One Flutter app, two modes chosen by the signed-in account's `staff.role`.

## Merchant mode (role = owner)
- **Order inbox** — the core screen. New orders arrive with a loud, repeating sound that keeps
  playing until opened; this is the single most important feature in the app. Accept with a
  preparation time, or reject with a reason. A countdown to `acceptDeadlineAt` is shown on
  **instant orders only** — pre-orders were accepted the moment the seller published the meal,
  so they carry no deadline and must not display a timer.
- **Live orders board** — accepted, preparing, out for delivery.
- **Menu management** — categories, items, prices, availability. Rendered by `MenuEditor`,
  the shared widget in `luqma_core` that AdminApp also uses; only the source of `merchantId`
  differs. Photo uploads create a `media` document with `status = pending` and stay invisible
  to customers until an admin approves them.
- **Busy toggle** — sets `pausedUntil` to a chosen time (30 / 60 / 120 minutes, or until
  closing). It expires on its own, so no merchant stays invisible because they forgot to
  reopen.
- **Daily meals** (home kitchen accounts only) — publish today's meal, quantity, pickup window,
  fulfilment option.
- **Couriers** — create and deactivate courier accounts belonging to this merchant, through
  `createStaffAccount` and `setStaffActive`. The function enforces that a merchant owner can
  only ever create a courier scoped to their own merchant.
- **Plan & promotions** — current plan, features, expiry, request an upgrade, and request any
  promotion: banner, boost, or push. One screen and one flow, because they are one thing.
- **Analytics** — orders, revenue, top items. Gated by plan features.
- **Private feedback** — rating comments from customers, visible to this merchant only.

## Courier mode (role = courier)
Deliberately minimal, no maps SDK, no live tracking:
order details · zone and address with landmark · customer phone with a call button ·
**cash amount to collect** · two buttons: `خرجت` and `تم التسليم` ·
`توجّه للعميل` hands off to the installed Google Maps app for voice navigation, which is free
and more accurate than anything built in-app.

Courier scope comes from the courier's `staff` document: `scope = merchant` sees only that
merchant's orders; `scope = platform`, created by the admin, sees home-kitchen orders and
orders from merchants where `deliversSelf = false`.
