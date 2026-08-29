-- Revenue settlement on delivery.
--
-- Until now the platform recorded what it would charge and charged nothing. `place_order`
-- freezes the terms onto `orders.revenue`, the phone shows the figure, `Revenue` in Dart
-- and the billing screens agree about it — and no statement anywhere ever moved a
-- piastre. `merchants.wallet_balance` was only ever added to, so a prepaid merchant's
-- credit never ran out and intake was never suspended; `merchants.commission_owed` had
-- been a column since the first schema and had never been written by anything; and
-- `pricing.platformOwesMerchant` — the coupon debt, which is the whole point of
-- `fundedBy` in a cash market — was computed, stored, and read by nothing.
--
-- `onOrderDelivered` was the Cloud Function that did this. It left with Firebase and the
-- trigger `docs/17` describes was never written.
--
-- The arithmetic here is the mirror of `Revenue.takeFrom` and `Revenue.basisFor` in
-- `packages/luqma_core/lib/src/models/revenue.dart`, and the tests pin both to the same
-- figures. The phone *shows* the number; this decides it, and this is the one that counts.

-- ------------------------------------------------------------------ the ledger

-- One row per order that has been settled. It is three things at once, and each of them
-- is load-bearing:
--
-- 1. The idempotency key. `order_id` is the primary key, so a second settlement for the
--    same order collides rather than pays. This is what stands between the product and a
--    double charge, and it is not the transaction: a trigger inside the status
--    transaction cannot be *missed*, but it can still run twice — a retry, a second
--    UPDATE that sets status to the same value, an admin touching a neighbouring column
--    with status in the SET list. Atomicity is not idempotence, and `docs/17` used to
--    say it was.
-- 2. The evidence. When a merchant disputes a figure, the answer has to be a row with a
--    date on it, not a running total that has been added to two hundred times.
-- 3. The reversal record. An admin can move a delivered order back out of delivered, and
--    a merchant left charged for an order that was cancelled afterwards will notice.
create table order_settlements (
  order_id      uuid primary key references orders on delete restrict,
  merchant_id   uuid not null references merchants on delete restrict,

  -- Copied from the order's frozen snapshot rather than joined back to it, so a
  -- settlement can be read and argued about a year later even if somebody has since
  -- corrected the order. The snapshot is already a copy of the merchant's terms; this is
  -- a copy of what was actually done with it.
  model         text not null check (model in ('subscription', 'commission', 'prepaid')),

  -- What the cut was charged on: the food, never the bill. See `Revenue.basisFor`.
  basis         integer not null check (basis >= 0),

  -- What the platform took.
  amount        integer not null check (amount >= 0),

  -- What the platform owes *back*, from a platform-funded coupon. Kept here and nowhere
  -- else on purpose: unlike the wallet, nothing in the hot path has to read it before an
  -- order, so a second denormalised column would exist only to drift from this one. The
  -- total is a sum over the unreversed rows.
  platform_owes integer not null default 0 check (platform_owes >= 0),

  settled_at    timestamptz not null default now(),

  -- Set when the charge was taken back. The row stays: "charged and then returned" and
  -- "never charged" are different answers, and only one of them is something a merchant
  -- should have to be told about.
  reversed_at   timestamptz
);

-- The merchant's own statement, newest first, and the admin's per-merchant view.
create index order_settlements_merchant_idx
  on order_settlements (merchant_id, settled_at desc);

-- ------------------------------------------------------------------ the arithmetic

-- What the platform takes from one order, from the terms frozen onto it.
--
-- The mirror of `Revenue.takeFrom`. Pure, and separate from the statement that applies
-- it, so the numbers can be argued with directly in a test rather than only observed
-- through a wallet balance afterwards.
create or replace function public.order_revenue_take(p_revenue jsonb, p_basis integer)
returns integer
language sql
immutable
as $fn$
  select case
    when p_basis <= 0 then 0
    else least(
      greatest(
        case p_revenue ->> 'model'
          -- The whole point of subscription-first: the money lands in the merchant's
          -- hand and nothing about a single order is negotiable afterwards.
          when 'subscription' then 0
          -- Basis points, rounded down, always. Taking one piastre more than the stated
          -- rate is the sort of thing that gets argued about in a shop, and it can only
          -- ever be argued downwards.
          when 'commission'
            then (p_basis * coalesce((p_revenue ->> 'value')::integer, 0)) / 10000
          -- A flat fee per order. `value` is the fee, not the balance.
          when 'prepaid' then coalesce((p_revenue ->> 'value')::integer, 0)
          else 0
        end,
        0),
      -- Never more than the order was worth. Under commission that is a clamp on a rate
      -- somebody mistyped; under prepaid it is the honest answer for an order smaller
      -- than the flat fee — the merchant made a sale, and a fee that puts them in the
      -- red on it is a fee that stops them taking small orders at all.
      p_basis)
  end;
$fn$;

-- ------------------------------------------------------------------ applying it

-- Makes the ledger agree with whether this order is delivered.
--
-- Written as "reach this state" rather than "do this thing", and that is the whole
-- design. Called with true it charges unless the order is already charged; called with
-- false it reverses unless the order is already not charged. Running it twice does
-- nothing the second time, so idempotence is a property of the shape rather than
-- something every caller has to remember — and the trigger below is then four lines.
--
-- `security definer`: the person doing the update is a courier, who has no rights on
-- `merchants` at all and must not be given any. What moves the money is this function,
-- and the only way to reach it is by moving an order the transition trigger has already
-- allowed you to move.
create or replace function public.apply_order_settlement(
  p_order_id uuid,
  p_charged  boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_order       record;
  v_existing    record;
  v_has_row     boolean;
  v_charged_now boolean;
  v_basis       integer;
  v_amount      integer;
  v_owes        integer;
  v_sign        integer;
  v_model       text;
  v_prior_mode  text;
begin
  -- Declared, and put back.
  --
  -- `security definer` is not enough on its own: `merchants.wallet_balance` and
  -- `commission_owed` are behind `guard_columns`, which asks whether a *trusted server
  -- function* is speaking rather than who owns the function. Without this the settlement
  -- worked only when the caller happened to have declared server mode itself — which the
  -- tests did and a real courier never would, so marking an order delivered from the
  -- street would have failed outright with "column not yours to change on merchants".
  --
  -- Restored rather than left on, because the setting is transaction-local and this runs
  -- inside somebody else's transaction. Leaving it standing would stand every guard down
  -- for whatever that transaction did next, which is a hole opened by a function that
  -- had no business opening one.
  v_prior_mode := coalesce(current_setting('app.server_mode', true), '');
  perform set_config('app.server_mode', 'on', true);

  select id, merchant_id, revenue, pricing
    into v_order
    from public.orders
   where id = p_order_id;

  if not found then
    raise exception 'no such order: %', p_order_id using errcode = 'P0002';
  end if;

  -- `for update` on the settlement row, so two statements racing to settle the same
  -- order serialise here rather than both reading "not settled yet". On the first
  -- settlement there is no row to lock, which is what the primary key is for.
  select * into v_existing
    from public.order_settlements
   where order_id = p_order_id
   for update;

  v_has_row := found;
  v_charged_now := v_has_row and v_existing.reversed_at is null;
  if v_charged_now = p_charged then
    -- The idempotent path, and the most frequently taken one — so it is also the one
    -- that must not leave server mode standing behind it.
    perform set_config('app.server_mode', v_prior_mode, true);
    return;
  end if;

  v_model := coalesce(v_order.revenue ->> 'model', 'subscription');

  if p_charged then
    v_basis  := greatest(coalesce((v_order.pricing ->> 'subtotal')::integer, 0), 0);
    v_amount := public.order_revenue_take(coalesce(v_order.revenue, '{}'::jsonb), v_basis);
    v_owes   := greatest(
      coalesce((v_order.pricing ->> 'platformOwesMerchant')::integer, 0), 0);
    v_sign   := 1;
  else
    -- A reversal returns exactly what was taken, read back off the row rather than
    -- recomputed. Recomputing would quietly use today's answer for a charge made under
    -- terms that have since changed, and hand back the wrong amount.
    v_basis  := v_existing.basis;
    v_amount := v_existing.amount;
    v_owes   := v_existing.platform_owes;
    v_model  := v_existing.model;
    v_sign   := -1;
  end if;

  -- A row for every delivered order, whatever the model and whatever the amount —
  -- including a subscription merchant's zero. The row is the audit trail, and an audit
  -- trail with the uninteresting entries left out is one nobody can count.
  insert into public.order_settlements
         (order_id, merchant_id, model, basis, amount, platform_owes)
  values (p_order_id, v_order.merchant_id, v_model, v_basis, v_amount, v_owes)
      on conflict (order_id) do update
         set reversed_at = case when p_charged then null else now() end,
             settled_at  = case when p_charged then now()
                                else order_settlements.settled_at end;

  -- Running totals on the merchant, because both are read on the hot path: `place_order`
  -- checks the wallet before every single order, and a sum over a table that grows with
  -- each one is not what it should be doing there. The ledger above stays the evidence;
  -- these two are the answer.
  update public.merchants
     set wallet_balance  = wallet_balance
                           - case when v_model = 'prepaid'
                                  then v_sign * v_amount else 0 end,
         commission_owed = commission_owed
                           + case when v_model = 'commission'
                                  then v_sign * v_amount else 0 end
   where id = v_order.merchant_id;

  -- And onto the order itself, where `RevenueSnapshot.amount` has been documented since
  -- Phase 7 as "what was actually taken, once the order was delivered" and has always
  -- been zero.
  update public.orders
     set revenue = coalesce(revenue, '{}'::jsonb)
                   || jsonb_build_object('amount',
                        case when p_charged then v_amount else 0 end)
   where id = p_order_id;

  perform set_config('app.server_mode', v_prior_mode, true);
end;
$fn$;

revoke execute on function public.apply_order_settlement(uuid, boolean)
  from public, anon, authenticated;
grant execute on function public.apply_order_settlement(uuid, boolean) to service_role;

-- ------------------------------------------------------------------ the trigger

-- `security definer` as well, and for a reason that is easy to miss: a trigger function
-- runs as whoever ran the statement, and the statement here is a courier's. Without this
-- the courier reaches `apply_order_settlement`, which is revoked from `authenticated`
-- precisely so that nobody can settle an order by hand — and is refused. Marking an order
-- delivered would fail outright, from the street, with the cash already collected.
--
-- Granting the settlement to `authenticated` instead would have made the same symptom go
-- away by letting any signed-in person charge any merchant. This is the other fix.
create or replace function public.settle_on_delivery()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
begin
  if new.status = 'delivered' then
    perform public.apply_order_settlement(new.id, true);
  elsif old.status = 'delivered' then
    -- Only an admin can move an order back out of delivered — the transition trigger
    -- sees to that — and when they do, the merchant must not stay charged for it.
    perform public.apply_order_settlement(new.id, false);
  end if;
  return null;
end;
$fn$;

-- `after`, not `before`: this writes the very row being updated, which a `before` trigger
-- cannot do without fighting the update in progress.
--
-- The `when` clause is the other half of the guard the primary key provides. It refuses a
-- write that leaves the status where it was — the retry, the second UPDATE, the admin
-- editing a neighbouring column with status in the SET list — so the settlement is not
-- even attempted unless the order actually moved.
create trigger orders_settle_on_delivery
  after update of status on orders
  for each row
  when (old.status is distinct from new.status
        and (new.status = 'delivered' or old.status = 'delivered'))
  execute function public.settle_on_delivery();

-- ------------------------------------------------------------------ who may read it

alter table order_settlements enable row level security;

-- A merchant reads their own statement. Nobody writes this table from a client at all:
-- there is no write policy here and there is not meant to be one, because the only thing
-- that may write it is the function above, running as its definer.
create policy read_own_settlements on order_settlements
  for select to authenticated
  using (public.is_merchant_owner(merchant_id) or public.is_admin());

grant select on order_settlements to authenticated;
