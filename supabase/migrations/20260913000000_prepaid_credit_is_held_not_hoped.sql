-- Prepaid credit is held when an order is placed, not hoped for until it is delivered.
--
-- `place_order_priced` refused a prepaid merchant whose `wallet_balance` was under one
-- order's fee, and `apply_order_settlement` took that fee **on delivery**. Between those
-- two moments the credit was promised to nobody: an accepted order reserved nothing, so
-- the same five pounds funded as many orders as arrived before the first one landed.
--
-- Two placements against one order's worth of credit both succeeded, and delivering both
-- left the wallet at minus one fee. No concurrency needed — sequential is enough, which is
-- what makes it ordinary rather than exotic.
--
-- The fix is a held figure beside the balance, so "what is left" and "what is already
-- spoken for" are two numbers instead of one hopeful one.
--
-- **Not a `check (wallet_balance >= 0)`.** That would move the failure to the worst
-- possible place: a courier who has already collected cash at a door, unable to record the
-- delivery because settling it would overdraw an account the customer has nothing to do
-- with. The refusal belongs at placement, where nothing has been cooked yet.

alter table merchants
  add column if not exists wallet_held integer not null default 0
    check (wallet_held >= 0);

comment on column merchants.wallet_held is
  'Prepaid fees for orders placed and not yet settled. Spendable credit is '
  'wallet_balance - wallet_held; the balance itself does not move until delivery.';

-- ---------------------------------------------------------------- holding

-- What one order costs this merchant under its frozen terms.
--
-- Read off the order rather than off the merchant, for the reason the reversal path
-- already gives: terms change, and an order must release exactly what it held.
create or replace function public.prepaid_hold_for(p_order public.orders)
returns integer
language sql
immutable
set search_path = public, pg_catalog
as $$
  select case
           when coalesce(p_order.revenue ->> 'model', '') = 'prepaid'
           then greatest(coalesce((p_order.revenue ->> 'value')::integer, 0), 0)
           else 0
         end;
$$;

-- The hold follows the order's life, in one place rather than at every call site that
-- moves a status. A trigger cannot be forgotten by a new screen the way a repository
-- method can.
create or replace function public.hold_prepaid_credit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_hold integer;
begin
  if tg_op = 'INSERT' then
    v_hold := public.prepaid_hold_for(new);
    if v_hold > 0 then
      update public.merchants
         set wallet_held = wallet_held + v_hold
       where id = new.merchant_id;
    end if;
    return new;
  end if;

  -- Released once, on the first move out of a live state. `delivered` releases it because
  -- `apply_order_settlement` takes the money from the balance at that moment; `cancelled`
  -- and `rejected` release it because nothing will ever be taken.
  if old.status not in ('delivered', 'cancelled', 'rejected')
     and new.status in ('delivered', 'cancelled', 'rejected') then
    v_hold := public.prepaid_hold_for(new);
    if v_hold > 0 then
      update public.merchants
         set wallet_held = greatest(wallet_held - v_hold, 0)
       where id = new.merchant_id;
    end if;
  end if;

  return new;
end;
$$;

create trigger orders_hold_prepaid_credit
  after insert or update of status on orders
  for each row
  execute function public.hold_prepaid_credit();

-- ---------------------------------------------------------------- spending it

-- Placement now measures against what is actually free.
--
-- This is `place_order_priced` with one condition changed: `wallet_balance` became
-- `wallet_balance - wallet_held`. Everything else is the function as it stands.
do $migrate$
declare
  v_src text;
  v_new text;
begin
  select prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'place_order_priced';

  v_new := replace(
    v_src,
    'and v_merchant.wallet_balance < v_merchant.revenue_value then',
    'and v_merchant.wallet_balance - v_merchant.wallet_held < v_merchant.revenue_value then'
  );

  if v_new = v_src then
    raise exception
      'place_order_priced no longer contains the prepaid balance check this migration '
      'edits. Re-read the function and port the change by hand rather than leaving a '
      'prepaid merchant able to spend the same credit twice.';
  end if;

  execute format(
    'create or replace function public.place_order_priced(p_draft jsonb) '
    'returns jsonb language plpgsql security definer set search_path = '''' as %L',
    v_new);
end;
$migrate$;
