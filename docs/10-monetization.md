# Monetization

## Why subscription first
Cash-on-delivery means money lands in the merchant's hand, never the platform's. Percentage
commission on cash in a small city degenerates into weekly arguments over cancelled and refused
orders. A flat monthly figure is unambiguous, paid once, and reads to the merchant as paying for
a service rather than being taxed per order. Commission and prepaid are built and available per
merchant; they become attractive once online payment exists and the platform collects directly.

## Plans
| Plan | Price/month | Features |
|---|---|---|
| Free | 0 | Full account, 20 items, normal ranking. Permanent — a marketplace empty of merchants is dead, so unpaid merchants still work in the platform's favour. |
| Basic | ~250 EGP | Unlimited items, verified badge, sales analytics |
| Premium | ~600 EGP | Basic plus rank boost, home banner, one monthly push campaign |

Prices and feature limits live in `plans` and are edited from AdminApp, never hard-coded.

## Promotions
Sold **separately from plans**, so a Free-plan merchant can still buy one.
One collection, four channels: `homeBanner`, `categoryBanner`, `boost` (ranking lift) and
`push`. Every channel shares the same lifecycle — requested, approved, active between two
dates, ended — so they share one document shape, one admin queue and one expiry pass.
Where a banner appears is decided by the `adSlot` home section it runs in.

A banner renders as text on a brand gradient, as a full-bleed image, or as an image with the
text over a scrim. The text mode matters commercially, not just visually: it lets a merchant
who has no artwork and no designer buy a banner on the same day they ask for one, which is
most merchants in Edku.

## Coupons

One code per order — never two. Stacking produces combinations nobody predicted (20% plus
30 EGP plus free delivery on a 40 EGP order leaves the merchant paying the customer) and it
is the first thing anyone probes. A stronger offer is one stronger coupon.

Three types: percentage, fixed amount, and **free delivery — which will do most of the
work**, because the delivery fee is what people hesitate over before tapping order, not the
price of the food. It is also the cheapest offer a merchant can make.

Coupons are created in AdminApp. Merchants request them through the same
request-then-approve flow as promotions, added in Phase 8. Letting a merchant publish codes
freely invites a 50%-off code with no ceiling, and invites one merchant to burn the local
price floor and drag the rest down with them.

**Validation is server-side and not negotiable.** The courier collects the figure the app
computed, so a discount evaluated only on the phone is a discount anyone can edit into a
free meal. The Cloud Function recomputes the coupon at order creation and refuses an order
whose total disagrees with its own.

## AdMob
Built, shipped **off** behind `admobEnabled`. Reasons it is not the launch strategy:
eCPM in Egypt is low and Edku's volume is small, so revenue would be marginal; house ads
undercut the premium look; and Google's network can serve competitor ads inside the app,
weakening the pitch to merchants paying for placement. The switch exists so the decision
stays reversible at any time.

## Settlement

**When an order is delivered, and never before.** Cash reaches the merchant at the door,
so that is the only moment the platform's share is real; charging at order time would bill
for orders that are cancelled, refused, or never answered.

`order_settlements` holds one row per delivered order — every model, including a
subscription merchant's zero, because an audit trail with the uninteresting entries left
out is one nobody can count. `order_id` is its primary key, and that is the guard: a
trigger inside the status transaction cannot be *missed*, but it can still run twice, and
the difference between those two sentences is a merchant charged twice for one order.
Atomicity is not idempotence.

| Model | What is taken | Where it lands |
|---|---|---|
| Subscription | Nothing | A row at zero, and nothing else |
| Commission | Basis points of the **food**, rounded down | `merchants.commission_owed` |
| Prepaid | The flat fee, capped at what the order was worth | Out of `merchants.wallet_balance` |

Everything is read off the snapshot frozen onto the order, never off the merchant, so
moving somebody to commission next month changes future orders and rewrites nothing.
The two merchant columns are running totals because both are read on the hot path —
`place_order` checks the wallet before every single order — and the ledger stays the
evidence behind them. `platform_owes` lives only in the ledger, because nothing has to
read it before an order and a second denormalised column would exist only to drift.

**A charge can be taken back.** An admin can move a delivered order back out of delivered,
and a merchant left billed for one that was cancelled afterwards will notice. The row
stays, marked `reversed_at`: "charged and then returned" and "never charged" are different
answers. The reversal hands back what the row says was taken, not what would be taken
today — a rate corrected since would otherwise return the wrong money.

**Both sides read it.** MerchantApp's كشف الحساب is two tabs under one summary —
**الشحنات** and **المدفوعات**, what was taken and what was handed over — and AdminApp's
billing screen carries the same figures per merchant. The receipts tab shows the note the
admin wrote, because "دفع ٤٧٠ والباقي الأسبوع الجاي" is what decides an argument three
weeks later and the merchant should be reading it rather than remembering it. A payment
reads as money coming *off*, with the sign, which is the whole point of putting charges
and collections in one statement.

The second tab appears only where there can be collections. A prepaid merchant pays by
topping up a wallet, which is not a commission receipt and never lands in that table — so
the tab would be permanently empty, and a tab that is always empty teaches somebody the
screen has nothing to say. Neither is offered under a
subscription, where nothing is taken per order. What the platform owes back is shown as its
own figure rather than netted against the commission: they are two different conversations,
and one number that mixes them is a number nobody can check.

**Collection** is `record_commission_payment`: an admin, a figure, a receipt in
`commission_payments`, and a line in the audit log — the same shape as
`recordSubscriptionPayment`, because the money is cash and the act is a person handing
over notes. The admin records it from the billing screen and the merchant's own statement
shows the balance fall.

Three decisions in it worth keeping:

- **The amount is not capped at what is owed.** An admin standing in a shop takes what is
  on the counter, and a merchant who rounds up by five pounds must not meet an error with
  the cash already handed over. The balance goes negative, which is credit the next
  delivery eats into — and the screen says "رصيد للمطعم عندنا" rather than showing a minus
  sign, which on a screen about money reads as a fault.
- **The button is offered only where something is owed.** Handing money *back* is a
  different act with a different conversation behind it, and one control that can do both
  without saying which is one nobody can audit.
- **The receipts table has no write policy at all.** Granting inserts to admins would let
  one write a receipt without moving the balance — a piece of paper saying money changed
  hands while the account says it did not, which is the exact thing a receipt rules out.
  The function does both halves or neither.

## Collection
Cash, recorded in AdminApp via `recordSubscriptionPayment`, which writes a `subscriptions`
document and an `auditLog` entry.
