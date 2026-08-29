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

## Collection
Cash, recorded in AdminApp via `recordSubscriptionPayment`, which writes a `subscriptions`
document and an `auditLog` entry.
