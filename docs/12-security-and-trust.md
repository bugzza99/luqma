# Security, Trust and Legal Posture

> **Written for the Firebase backend, which is gone.** The product decisions in this
> document still stand — they were argued through with the owner and none of them were
> reversed by the move. What is stale is the *machinery*: Firestore collections are
> Postgres tables, security rules are RLS policies, Cloud Functions are Postgres
> functions and `pg_cron` jobs, and Firebase Auth is GoTrue. Read
> `docs/17-supabase-migration.md` for the mapping and `CLAUDE.md` for what is true today;
> where this file and those two disagree, they win.

## Firestore Security Rules
- `users` — a user reads and writes only their own document and addresses.
- `merchants` — public read of `approved` merchants; writes restricted to the owner
  and to admin custom claims. A merchant owner may write only their own presentation and
  operations fields — never `status`, `planId`, `revenueModel`, `walletBalance`, `servedZones`
  or `ratingAvg`. `deliveryFeeOverride` is writable by the owner but the rule clamps it to
  `deliveryFeeMin … deliveryFeeMax`, so the range the admin sets is enforced on the server
  rather than only in the merchant's UI.
- `menuItems` — public read; a `mediaId` resolves to a visible image only when that `media`
  document is `approved`, so one rule on `media` gates every image in the product.
- `orders` — readable by the owning customer, the order's merchant, the assigned courier,
  and admins. Status transitions are validated server-side; clients cannot jump states.
- `plans`, `homeSections`, `config`, `zones`, `landmarks` — public read, admin-only write.
- `staff`, `auditLog` — admin-only, and `auditLog` is append-only. A merchant owner may read
  and write only `staff` documents whose `merchantId` matches their own.

Admin identity is a Firebase custom claim, never a client-side role field, so a compromised
client cannot promote itself.

## Home kitchen vetting
Sellers are approved manually: national ID plus kitchen photos, reviewed in AdminApp.
Terms of service state explicitly that Luqma is an intermediary and the seller bears
responsibility for food safety. The pre-order model with published quantities and pickup
windows also limits exposure, since nothing is cooked speculatively.

## Abuse and integrity
Rejection counting with auto-block, new-customer flagging, OTP behind a flag, admin-only
push approval, and image moderation together form the trust layer. Each one exists because
cash-on-delivery and public content both create abuse surface that a small merchant cannot absorb.

## Ratings policy
Stars are public; comments are private to merchant and admin. No rating displays until a
merchant has at least `minRatingsToShow` (default 10) ratings, so a single bad review cannot
sink a new merchant in a city where everyone knows everyone. `publicCommentsEnabled` opens
comments later once trust is established.
