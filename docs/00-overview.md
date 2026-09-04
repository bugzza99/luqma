# لقمة (Luqma) — Project Overview

> **Written for the Firebase backend, which is gone.** The product decisions in this
> document still stand — they were argued through with the owner and none of them were
> reversed by the move. What is stale is the *machinery*: Firestore collections are
> Postgres tables, security rules are RLS policies, Cloud Functions are Postgres
> functions and `pg_cron` jobs, and Firebase Auth is GoTrue. Read
> `docs/17-supabase-migration.md` for the mapping and `CLAUDE.md` for what is true today;
> where this file and those two disagree, they win.

## What it is
Luqma is a local food ordering marketplace for the city of **Edku** (إدكو), Beheira, Egypt.
It covers two supply types in one marketplace:
1. **Restaurants** — instant orders, restaurant delivers with its own courier.
2. **Home Kitchens** (أكل بيتي) — pre-ordered daily meals with limited quantity and a pickup window.

Home Kitchens are the differentiator. Restaurants are table stakes.

## System shape
Three Flutter Android apps sharing one Firebase backend and one shared Dart package.

| App | Users | Distribution |
|---|---|---|
| `customer_app` | End customers | Google Play |
| `merchant_app` | Restaurant owners, Home Kitchen sellers, Couriers | Google Play |
| `admin_app` | Owner / operators | Direct APK, never published |

`luqma_core` is a shared Dart package holding models, repositories, Firebase services,
`RemoteConfigService`, theme tokens, localization, and the components more than one app needs —
`MenuEditor`, `AddressPicker`, and the design-system widgets. All three apps depend on it.

## Non-negotiable constraints
- **Payment is cash on delivery only.** Data model is payment-method aware for later online payment.
- **Arabic only, RTL.** i18n infrastructure exists from day one so English can be added as a file.
- **Multi-city data model, single-city launch.** Every merchant, order, zone and plan carries `cityId`.
- **Android first.** iOS and Web reuse the same Flutter codebase later.
- **No driver app.** Courier is a mode inside `merchant_app`.
- **Dynamic configuration** covers values AND home screen composition, not full server-driven UI.

## Revenue
The platform supports three revenue models, selectable per merchant from AdminApp:
`subscription` (launch default), `commission`, and `prepaid wallet`. The switch and the
per-order `revenueSnapshot` ship complete; whether the `prepaid` branch ships filled in or as a
stub is an open decision recorded in `15-simplifications.md`.
Plus merchant-sold promotions (banner, boost, push) and an AdMob switch that ships off.

## Launch plan
Onboard 10–15 restaurants at zero commission for 3 months. The owner enters menus and shoots
photos personally via AdminApp. Merchants are never asked to self-onboard.
