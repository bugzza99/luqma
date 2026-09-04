# Order Lifecycle

> **Written for the Firebase backend, which is gone.** The product decisions in this
> document still stand — they were argued through with the owner and none of them were
> reversed by the move. What is stale is the *machinery*: Firestore collections are
> Postgres tables, security rules are RLS policies, Cloud Functions are Postgres
> functions and `pg_cron` jobs, and Firebase Auth is GoTrue. Read
> `docs/17-supabase-migration.md` for the mapping and `CLAUDE.md` for what is true today;
> where this file and those two disagree, they win.

## States
`placed` → `accepted` → `preparing` → `outForDelivery` → `delivered`
Terminal alternates: `cancelled`, `needsAttention`.

## Rules
- On `placed`, a Cloud Function assigns `orderNumber`, writes `revenueSnapshot`,
  sets `acceptDeadlineAt = now + acceptTimeoutMinutes` (default 5), and pushes a
  high-priority repeating-sound notification to the merchant.
- If the merchant does not accept before `acceptDeadlineAt`, a task enqueued at order
  creation moves the order to `needsAttention` and notifies **the admin**, not the customer.
  The countdown the merchant sees is computed on the client from `acceptDeadlineAt`, so no
  server tick is needed to render it.
- The merchant sets a preparation time when accepting; the customer sees it.
- **The customer may cancel only while status is `placed`.** After acceptance, cancelling
  requires calling the merchant, which raises an `orderIssue`.
- Ordering is blocked whenever the derived `acceptingOrders` predicate is false: outside
  `workingHours`, or while `pausedUntil` is in the future. The merchant sets `pausedUntil`
  from MerchantApp when a rush hits, and it lapses on its own rather than waiting to be undone.
- On `delivered`, `RevenueEngine` applies the snapshot: commission accrues, or prepaid wallet
  is decremented, or nothing happens under a subscription model.

## Pricing

`OrderPricing` is a pure computation over the basket, the zone's delivery fee and at most
one coupon. The same function runs on the phone, to show a total before the customer
commits, and in `onOrderCreate`, to decide what the courier actually collects — and the
server's answer is the one that counts.

Two rules that only matter because the money is cash:
- The total is floored at zero. A courier cannot hand money back at the door.
- An empty basket costs nothing, not just the delivery fee.

## Fake order defence (cash-only exposure)
- `users.rejectedOrdersCount` increments when an order is cancelled at the doorstep.
- Auto-block at `rejectionBanThreshold` (default 3), the threshold being admin-tunable.
- Orders from a customer with no delivered history are flagged `isNewCustomer` so the merchant
  can confirm by phone before cooking.
- OTP verification exists behind `otpEnabled` and is the escalation path once volume grows,
  since a blocked user can otherwise register the same number again as a new account.

## Pre-order (home kitchen) variant
`type = preorder` orders reserve quantity against `dailyMeals.remainingQty` in a Firestore
transaction, so a meal can never be oversold. There is no 5-minute accept timer — the seller
publishes the meal in advance, which is itself the acceptance. Fulfilment follows
`dailyMeals.deliveryOption`: customer pickup, platform courier, or direct seller arrangement.
