-- A cancelled order gives back what placing it took (A4).
--
-- `place_order_priced` takes two things inside the placement transaction: a home
-- kitchen's portions (`daily_meals.remaining_qty`, the conditional decrement the whole
-- `dailyMeals` design exists for) and a coupon's use (`coupons.used_count`, plus a
-- `coupon_redemptions` row that `alreadyUsed` and `per_user_limit` read). Nothing ever
-- gave either back. So one account could reserve a kitchen's last ten portions and
-- cancel a second later, and the meal read «خلصت» for the rest of the day — the column
-- guard refuses the cook a write of `remaining_qty`, so nobody could put them back — and
-- a customer whose order the shop refused found their one-use code already spent on an
-- order that never happened.
--
-- One trigger, on the status reaching `cancelled`, whoever moved it: the customer, the
-- shop, a courier returning it, the escalation, an admin. It runs once per order because
-- `cancelled` is terminal — `enforce_order_transition` refuses every move out of it for
-- anybody but a platform admin — and the `when` clause fires only on the move *into* it.
--
-- The portions go back capped at `total_qty`: the count may have moved while the order
-- lived, and giving back more than was ever published would sell portions that do not
-- exist. The coupon's redemption row is removed rather than marked: it is the thing the
-- limits count, and the order keeps its `coupon_code` and `pricing`, so what was
-- discounted on it is still on record.

create or replace function public.give_back_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_prior  text;
  v_qty    integer;
  v_coupon uuid;
begin
  -- Server mode because the column guards on `daily_meals` and `coupons` refuse these
  -- columns to everybody else, and the trigger runs as whoever cancelled. Put back
  -- afterwards: it is transaction-local, inside the caller's transaction.
  v_prior := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  if new.type = 'preorder' and new.daily_meal_id is not null then
    select coalesce(sum((line ->> 'quantity')::int), 0)
      into v_qty
      from pg_catalog.jsonb_array_elements(new.items) as line;

    if v_qty > 0 then
      update public.daily_meals
         set remaining_qty = least(total_qty, remaining_qty + v_qty)
       where id = new.daily_meal_id;
    end if;
  end if;

  delete from public.coupon_redemptions
   where order_id = new.id
  returning coupon_id into v_coupon;

  if v_coupon is not null then
    update public.coupons
       set used_count = greatest(used_count - 1, 0)
     where id = v_coupon;
  end if;

  perform pg_catalog.set_config('app.server_mode', v_prior, true);
  return null;
end;
$fn$;

revoke all on function public.give_back_on_cancel() from public, anon, authenticated;

drop trigger if exists orders_give_back_on_cancel on public.orders;
create trigger orders_give_back_on_cancel
  after update of status on public.orders
  for each row
  when (new.status = 'cancelled' and old.status is distinct from 'cancelled')
  execute function public.give_back_on_cancel();
