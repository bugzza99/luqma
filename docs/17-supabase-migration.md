# Moving off Firebase, onto Supabase

Agreed 2026-08-24. Written before any code, because a migration decided in one session
and executed over three weeks is a migration nobody remembers the reasons for.

**This is not a swap. It is a rewrite of the data layer with the rest of the product held
still.** What makes it survivable is that the product does not talk to Firebase — it
talks to thirteen repository interfaces, and Firebase lives behind them.

## The measurement this rests on

**24 of 108 source files touch Firebase. None of them is a screen.**

| Untouched | Rewritten |
|---|---|
| Every screen in all three apps | 13 repository implementations — **2,736 lines** |
| Every model, and all the pure logic: `Revenue`, `Coupon`, `OrderTransitions`, `Money`, `DailyMeal` | 320 lines of `firestore.rules` → RLS |
| All thirteen repository **interfaces** | All **98** rules tests |
| Every fake | `AuthService`, `RemoteConfigService`, `converters.dart` |
| **~700 of the 840 Dart tests** | The data model itself: documents → tables |
| Theme, l10n, brand, providers | The 19 live streams |

That table is the whole argument. If the screens spoke to Firestore this would be a
rewrite; because they speak to interfaces, it is a swap behind a seam that already exists
and is already proven by the fakes.

## Why, and why now

Two reasons, both the owner's:

- **Blaze needs a credit card.** The project has sat on Spark for eight phases because of
  it, and five things have been blocked the whole time: server-side order creation, the
  accept-deadline task, rejection counting, the transactional `remainingQty` decrement,
  and image upload. Supabase's free tier includes Edge Functions and Storage with no card.
- **SQL, and reports that are real.** `docs/16-admin-completion.md` wants a statistics
  screen. On Firestore that means a `counters` collection and a function to maintain it.
  In Postgres it is a `SELECT`.

**Now, because there is no production data and no live merchant.** The cost of this
migration only ever rises. Today it is the cheapest it will ever be.

### What stops being the app's problem

Three findings from the pre-launch audit stop being code and become constraints in the
database, which is a better place for them:

| | Before | After |
|---|---|---|
| A coupon with a negative value | a check in `evaluate` | `CHECK (value >= 0)` |
| Deleting a merchant that has orders | counted by the app first | a foreign key refuses it |
| Two people taking the last portion | a Cloud Function transaction | `UPDATE … WHERE remaining_qty >= n` |

And `F5` — the nightly pass reading the whole `subscriptions` collection, deferred to
Phase 9 in `CLAUDE.md` — stops existing. `pg_cron` with a `WHERE` clause and a join is
the whole of it.

## What we lose, and what we are doing about it

**Firestore has an offline cache. Supabase has none.** This is the real cost and it is
not recovered by being clever.

The owner's call: acceptable, because customers order from home on wi-fi. That is right
about the customer and only about the customer. Two other people use this product:

- The **merchant** sits in a shop all day on mobile data.
- The **courier** stands in the street outside a building, marks an order delivered, and
  takes cash for it.

The courier is the one where money is lost. A tap on *"delivered"* that dies with the
connection is cash collected against an order the system still thinks is out.

**Decision: build a write queue for the courier's actions only.** Not a general offline
cache — the smallest thing that covers the only case where the loss is money. Reads
elsewhere may fail and say so, as they do today. This is in the plan from the start
rather than bolted on later, which is why it is written here.

## Decisions taken

### Region: `eu-central-1` (Frankfurt)

Matching `europe-west3`, which is where Firestore already is and cannot be moved from.
Same reasoning as the original choice: latency to Egypt, and data that stays in Europe.

### Column names are `snake_case`; the models do not change

Unquoted identifiers in Postgres fold to lower case, so `merchantId` silently becomes
`merchantid`, and quoting every identifier for ever poisons every RLS policy and every
query typed by hand.

So the database is `snake_case` and the Dart models keep their camelCase JSON. One shared
mapper in the repository layer does the translation — about fifteen lines, written once,
and the models, the fakes and the tests never learn that anything changed.

### Identifiers are `uuid`, and stay `String` in Dart

`Model.fromJson` takes a string id today and will tomorrow.

### Money stays integer piastres

`integer`. It was always the right shape and Postgres agrees.

### Statuses are `text` with a `CHECK`, not Postgres `enum`

Adding a value to a Postgres enum needs `ALTER TYPE`; removing one is close to
impossible. A `CHECK` constraint is edited like any other.

The client keeps its unknown-value fallback — `PromotionStatus` reading as `requested`
rather than throwing — because a database migrated on Tuesday meets phones that were
installed in March, and a new status must not crash a home screen.

### `dailyMeals.date` becomes a real `date`

The `yyyy-MM-dd` day-key rule in `CLAUDE.md` exists because equality against a Firestore
timestamp matches one microsecond. In Postgres the type does that natively, and the rule
retires.

### Nested data: `jsonb` or a table, decided per case

The rule: **`jsonb` when it is a frozen copy or always read whole; a table when it is
queried, joined, or has a life of its own.**

| | Becomes | Because |
|---|---|---|
| `order.items` | `jsonb` | A copy frozen at order time. Never queried into, never edited. A table would invite editing it, and last week's order must not change when this week's menu does. |
| `order.address` | `jsonb` | Same reason, and it is why the copy exists at all. |
| `order.revenue` | `jsonb` | The terms in force that day. Frozen by design. |
| `menuItem.options` | `jsonb` | Read whole with the item, always. |
| `merchant.openingHours` | `jsonb` | Read whole; `acceptsOrdersAt` is computed in Dart. |
| `homeSection.params` | `jsonb` | Untyped by design — the section registry interprets it. |
| `merchant.menuCategories` | **table** | Menu items reference them; the admin reorders them. Its own lifecycle. |
| `merchant.servedZones` | **table** | This is a relationship, and it is queried from both ends. |
| `promotion.zoneIds` | `text[]` | Membership only, and empty means the whole city — which `= '{}'` says more plainly than a missing join row. |

### Two Cloud Functions become database features instead

This is where the migration pays for itself rather than merely surviving.

- **`onOrderDelivered` becomes a Postgres trigger.** Today it is an eventually-consistent
  function that fires after the write, needs an idempotency guard because it can fire
  twice, and spends a merchant's wallet. As a trigger it runs *inside the same
  transaction* as the status change: it cannot double-fire, it cannot be missed, and the
  guard is deleted rather than trusted.
- **Order creation becomes a Postgres function called over RPC.** The pricing recompute,
  the coupon check, the redemption record and the `remaining_qty` decrement all land in
  one transaction. The race that the entire `dailyMeals` design exists to prevent is then
  `UPDATE daily_meals SET remaining_qty = remaining_qty - $1 WHERE id = $2 AND
  remaining_qty >= $1` — and if it affects no rows, the customer lost the race and the
  screen already knows what to say.

`dailyMaintenance` becomes `pg_cron`. The media pipeline stays an Edge Function, because
it processes images and that is not the database's job.

`engine.ts` is pure TypeScript with no Firebase in it, and ports to Deno unchanged. Its
33 tests come with it.

### Claims move into the JWT, and RLS reads them

The whole security model is `request.auth.token.merchantId` and friends. In Supabase a
**custom access token hook** — a Postgres function — copies `admin`, `role`, `scope` and
`merchant_id` from the `staff` table into the JWT at sign-in, and policies read
`auth.jwt() -> 'app_metadata'`.

The important part is what does not change: **a claim is still something only a server
can issue.** That is the property every rule in the project rests on, and it survives.

## The plan

Six stages. Each one leaves the project working; none of them has a day where it is
broken.

### S0 — the ground

Supabase project in `eu-central-1`. The schema: sixteen collections become tables with
real foreign keys, `CHECK` constraints, and the indexes the queries in the repositories
already tell us we need. A seed that matches `firebase/seed/`.

### S1 — the boundary, first rather than last

Auth (Google, and email/password for staff), the custom access token hook, and RLS
policies mirroring `firestore.rules` line for line — **including everything the audit
fixed**: the order state machine, cross-merchant ownership, delete judged on the row
already there, ratings tied to a delivered order.

The 98 rules tests are rewritten here. This is the riskiest stage in the whole migration,
which is exactly why it comes second and not last.

### S2 — repositories, one at a time, replaced rather than doubled

**Revised 2026-08-24, after S1.** The plan said to build each Supabase repository *beside*
its Firestore one behind a per-repository switch, so the product would never be broken for
a day. That is the right shape for a live system, and this is not one: no production data,
no live merchant, no customer, nothing published. The switch would have been scaffolding
written to be deleted, and the owner's standing instruction is the opposite — no Firebase
left in the project.

So each repository is **replaced in place, and its Firestore implementation deleted with
it**. Same interface, same tests; one file instead of two.

Rolling back is `git revert`, not a flag. Every commit is a restore point, and a flag in
the code cannot do anything git does not already do.

Firebase therefore leaves **progressively** rather than all at S6: the packages, options
and emulator wiring go when the last thing that imports them does. What still has to be
ordered is dependency order — nothing can delete `firebase_options.dart` before the
repositories above it have moved — and that is arithmetic, not caution.

Start with `geography`: read-mostly, and it proves the shape cheaply. Leave `orders` until
the stream helper in S3 exists.

### S3 — the 19 live streams

Firestore streams a *query* and re-evaluates it on the server. Supabase streams *row
changes* and the client keeps the list. The interface does not change; the work behind it
does — fetch, subscribe, merge, and refetch on reconnect, because nothing replays what
was missed while the socket was down.

**Written once as a helper, not nineteen times.** That is where the bugs in this migration
would otherwise live.

The nineteen: merchants ×2, menu categories, menu items, pending media, home sections,
daily meals ×2, one order, my orders, merchant incoming, merchant live, courier ×2,
subscription, feedback, promotions ×3.

### S4 — the server, and the five things that have been blocked since Phase 1

Order creation, the accept deadline, rejection counting, the `remaining_qty` decrement,
and the media pipeline. Some are Postgres functions, some are Edge Functions, one is
`pg_cron` — decided per item above.

### S5 — config, storage, push, and the courier's queue

`RemoteConfigService` becomes a `config` table. This is an improvement worth noting: today
a change takes up to the fetch interval to reach a phone; a table with realtime on it
arrives at once, and `LuqmaConfig`'s per-key validation stays exactly as it is.

Storage with its policies. **FCM stays FCM** — Supabase has no push — called from an Edge
Function instead of a Cloud Function.

And the courier write queue, agreed above.

### S6 — cutover

Migrate what data exists, which is almost none, and delete Firebase: the packages, the
options file, the emulator wiring, `firestore.rules`, and the functions directory.

## What is being kept, deliberately

- **Every repository interface, unchanged.** If a signature has to change to fit
  Supabase, that is a sign the implementation is leaking and the fix belongs in the
  implementation.
- **Every fake.** They are the contract, and they are what keeps 700 tests passing
  through all six stages.
- **The double engine.** `Revenue` in Dart and `engine.ts` on the server, tested against
  the same numbers. The reasoning does not change with the database: the phone shows the
  figure and the server decides it.

## What could still go wrong

Named here so nobody is surprised by them later.

- **Realtime under RLS.** Policies apply to realtime as well as to reads, and a policy
  that is subtly wrong shows up as a stream that is quietly short rather than as an
  error. Every stream needs a test with a signed-in user who should *not* see a row.
- **Reconnection.** Firestore backfills what was missed. Supabase does not. The helper in
  S3 has to refetch on reconnect, and a test has to prove it — a merchant whose phone
  slept through an order is the failure this prevents.
- **Google Sign-In, again.** New OAuth client, new redirect URLs. It has never been run on
  a real device even on Firebase, so it will be genuinely new either way.
- **The `staff` ↔ JWT loop.** Claims are refreshed on token refresh, not instantly. A
  courier promoted to owner keeps the old claim until their token turns over — the same
  property Firebase had, and worth re-testing rather than assuming.

## Estimate

About a week and a half of focused work, plus the courier's write queue.

It was two to three weeks when S2 carried a parallel implementation and a switch. Dropping
those changed the estimate and not the work: the ports themselves — nineteen streams, the
order function, the triggers — are exactly what they were.

It is a phase in its own right, not a change, and it should be measured against what it
unblocks: five features stuck since Phase 1, the statistics screen in `docs/16`, and a
project that no longer waits on a credit card.
