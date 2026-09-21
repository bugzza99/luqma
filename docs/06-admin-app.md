# AdminApp

> **Written for the Firebase backend, which is gone.** The product decisions in this
> document still stand — they were argued through with the owner and none of them were
> reversed by the move. What is stale is the *machinery*: Firestore collections are
> Postgres tables, security rules are RLS policies, Cloud Functions are Postgres
> functions and `pg_cron` jobs, and Firebase Auth is GoTrue. Read
> `docs/17-supabase-migration.md` for the mapping and `CLAUDE.md` for what is true today;
> where this file and those two disagree, they win.

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

**Amended 2026-09-21: what `moderator` means, now that it means something.** For nine
phases the role existed here, in `StaffRole` and on the staff form, and the gate asked
only whether somebody was an admin — so a moderator account opened nothing at all. The
owner's decision is that a moderator is **an admin except money, deletion, and who
anybody is**: they moderate photographs, work the ticket queue, correct a shop's details,
approve banners and read whatever an admin reads — including courier ID documents and
customer telephone numbers, which the owner accepted knowingly.

They may not record a payment, top up a wallet, move the commission rate, write a coupon,
delete anything anywhere, or edit `staff`, `courier_merchants`, `config` or `plans`.
Reading those is still allowed; reading the till is not taking from it.

The boundary is the database
(`supabase/migrations/20261024000000_a_moderator_is_an_admin_except.sql`), never the app.
AdminApp hides the six modules that are nothing but those, so a moderator is not offered
a door that will shut — but a refusal reaches any screen as an ordinary
`PermissionFailure` whatever was drawn, and that is what actually holds.
