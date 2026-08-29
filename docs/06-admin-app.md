# AdminApp

Flutter Android app, distributed as a direct APK and never published to Google Play.
Because it is Flutter, the same codebase becomes the future web dashboard with minimal change.
Every mutation writes to `auditLog`.

## Modules
- **Dashboard** — today's orders, `needsAttention` queue, open `orderIssues`, revenue snapshot.
- **Merchants** — approve or suspend, edit profile, set `revenueModel` per merchant,
  set plan, set served zones, set `deliversSelf`.
- **Menu entry** — full CRUD over categories and items **on behalf of merchants**, using the
  same `MenuEditor` widget the merchant sees. This exists because the owner onboards menus
  personally; merchants are never asked to self-onboard.
- **Media queue** — one queue over the `media` collection: approve or reject every uploaded
  image before it becomes visible, whatever it belongs to — logo, cover, menu photo, meal
  photo, or promotion banner. This gate is what protects the premium look, and it is far
  easier to keep from day one than to impose later.
- **Home builder** — create, reorder, show and hide `homeSections`. Live-controls the customer home.
- **Plans** — edit the three plans, their prices and feature limits.
- **Subscriptions** — record cash payments, see expiry, renew.
- **Promotions** — one queue for every paid placement: approve or reject merchant requests,
  schedule banners, boosts and push campaigns, view impressions and clicks, and enforce the
  weekly push cap. Where a banner appears is set by choosing the `adSlot` home section it runs in.
- **Zones & landmarks** — define Edku's zones, default delivery fees, and the named map points
  couriers navigate by.
- **Customers** — search, view order history, view rejection count, block and unblock.
- **Issues** — work the ticket queue raised from CustomerApp.
- **Config** — feature flags, limits, support WhatsApp number, force-update settings.
- **Staff** — create and manage platform couriers, moderators and merchant owner accounts
  through `createStaffAccount` and `setStaffActive`; one screen over the `staff` collection.

## Access control
`staff` documents with `scope = platform` and `role = admin|moderator` are mirrored to a
Firebase custom claim. Firestore Security Rules check the claim; no client-side-only gating
is trusted.
