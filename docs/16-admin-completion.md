# AdminApp — what is still missing

Not a new phase. `docs/13-build-order.md` scheduled Phase 2 as **"AdminApp minimum"**, and
four modules listed in `docs/06-admin-app.md` were never picked up in any phase afterwards.
This document is the outstanding list, plus the decisions the owner has already taken on it.

Written down rather than remembered: the work was agreed in one session and will be built
in another.

## Audit — spec against what exists

| Module in `06-admin-app.md` | State |
|---|---|
| Merchants, Menu entry, Media queue, Zones & landmarks | built |
| Subscriptions, Promotions, Home builder | built |
| **Dashboard** | **placeholder** — 36 lines of static text |
| **Customers** | **not built** |
| **Issues** (`orderIssues`) | **not built** — a customer can raise a ticket nobody can read |
| **Config** | **not built** |
| **Staff** | **not built** — was blocked on Blaze, unblocked by `firebase/scripts/staff.js` |
| **Plans** — editing prices and limits | **not built** — read-only, seeded from `edku.json` |

Two additions the owner asked for that are not in `06`:

- **Statistics**, wider than the daily dashboard.
- **About Luqma**, with the owner's own photo, links and description.

## Decisions already taken

### Deleting a merchant — real delete, only when it has no orders

Chosen deliberately over both alternatives. A merchant that has taken orders cannot be
deleted: those orders carry `merchantId`, and removing the merchant leaves every past
invoice and report pointing at nothing. But a merchant added by mistake, before it ever
traded, is not history — it is a typo, and refusing to remove it means the list carries
it for ever.

So: **delete is offered only while the merchant has zero orders.** Once it has one, the
control becomes suspend, and the reason is said on screen rather than the button quietly
disappearing.

The security rules already allow `delete` for an admin. The order check is the app's, and
it must be a real query — not a count field that can drift.

### About Luqma — a screen, with its content in Firestore

Everything on it is edited from AdminApp; nothing is compiled in. The owner fills it in
after the screens exist.

- A place for **the owner's photo**.
- **Facebook, WhatsApp and Instagram** icons, each with a link set from AdminApp. An icon
  with no link set is not drawn — an icon that goes nowhere is worse than no icon.
- A **description** block, free text, also set from AdminApp.
- App version and build number, which the app knows about itself.

Stored on `config/appConfig`, which already exists and already holds `supportWhatsapp`,
and whose rules are already `read: true` / `write: isAdmin()`. The photo goes through the
same `media` collection and moderation gate as every other image — there is no second path
for images.

### Merchant accounts, from AdminApp

Explicitly asked for a second time, so it is written here on its own line: **AdminApp must
create merchant accounts.** `firebase/scripts/staff.js` does this from a terminal today,
which is fine for the owner and useless to anybody else. The screen does the same three
things the script does — create the Auth user, stamp the `merchantId` and `role` claims,
write the `staff` document — which needs `createStaffAccount` on the server, and therefore
Blaze. Until then the screen can list and deactivate; creating stays in the script.

## The list, in the order it should be built

1. **Dashboard** — today's orders, the `needsAttention` queue, open issues, today's money.
   The four things the owner opens the app to see.
2. **Statistics** — customers, merchants, orders, average order value, growth by week and
   month. Wider than today, and read-only.
3. **Customers** — search, order history, `rejectedOrdersCount`, block and unblock.
4. **Issues** — the ticket queue raised from CustomerApp: read, reply, close.
5. **Staff** — merchants, couriers, moderators. List and deactivate now; create when Blaze
   is on.
6. **Config** — feature flags, limits, support WhatsApp, force-update settings.
7. **Plans** — edit prices and feature limits, so a price change is not a seed script.
8. **Delete a merchant** — under the rule above.
9. **About Luqma** — photo, links, description, version.

## Notes for whoever builds it

- `orderIssues` and the `users` collection have **no model and no repository** in
  `luqma_core` yet. Both need building first, with fakes, like everything else.
- Blocking a customer sets a field on `users` that only a server may write — the same
  shape as `rejectedOrdersCount`. Check the rules before assuming the client can do it.
- Every mutation in AdminApp writes to `auditLog`. `BillingRepository` already does this;
  follow it.
- The statistics screen must not read every order in the city to count them. Aggregates
  belong in `counters`, written by a function — until Blaze, the screen shows what it can
  read cheaply and says plainly what it cannot.
