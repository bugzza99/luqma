# Notifications

Two categories that must be separated technically from day one, because conflating them
is what makes users disable notifications entirely.

## Operational — cannot be muted in-app
- **New order to merchant** — FCM high priority, custom repeating sound, full-screen intent,
  Android notification channel `orders_critical` with max importance. Must fire with the app
  closed and must survive battery optimisation, which requires an explicit
  "ignore battery optimisations" prompt during merchant onboarding.
- **Order status changes to customer** — accepted, out for delivery, delivered.
- **`needsAttention` alert to admin.**

## Marketing — mutable and capped
- Sent from AdminApp via `sendPromotionPush`.
- Merchant-requested campaigns enter `promotions` with `channel = push`, `status = requested`, and require
  admin approval before send; unmoderated merchant push is the fastest way to make customers
  disable notifications and lose the operational channel with them.
- Hard cap `marketingPushPerWeek`, default 3, admin-tunable.
- Customer opt-out switch applies to this category only.

Channels are separate Android notification channels so the OS-level controls a user changes
for marketing never silence operational alerts.
