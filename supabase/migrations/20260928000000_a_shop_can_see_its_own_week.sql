-- What a shop sold, counted once and in one place.
--
-- The merchant app has a statement — what the platform took — and nothing that answers
-- "how did this week go". The owner has been counting orders by scrolling the live board.
--
-- Three decisions inside it, because each could reasonably have gone another way:
--
-- **Sales are the food, not the bill.** `pricing.subtotal`, the same figure commission is
-- charged on, for the same reason: when the platform delivers, the delivery fee was never
-- the merchant's to see, and a headline that silently includes it on some orders and not
-- others is a number the owner cannot check against their own till. It survives one
-- sentence in a shop — «ده بيع الأكل» — which in a cash market is worth more than being
-- comprehensive.
--
-- **A cancelled order is not a sale, and is counted anyway.** Excluding it entirely would
-- hide the thing an owner most needs to see; folding it into sales would be a lie. It has
-- its own figure, split by who cancelled — a customer changing their mind and a courier
-- coming back from the door are different problems.
--
-- **The day is Cairo's.** A shop that closes at one in the morning would otherwise have
-- its evening cut in half by UTC, which is the trap `admin_today` documents.
create or replace function public.merchant_sales(
  p_merchant_id uuid,
  p_days        integer default 7
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $fn$
  with bounds as (
    select greatest(least(coalesce(p_days, 7), 90), 1) as days,
           ((now() at time zone 'Africa/Cairo')::date + 1) as after_day
  ),
  window_at as (
    select b.days,
           b.after_day,
           ((b.after_day - b.days)::timestamp at time zone 'Africa/Cairo') as from_at,
           (b.after_day::timestamp at time zone 'Africa/Cairo') as to_at
      from bounds b
  ),
  mine as (
    select o.status,
           o.cancelled_by,
           o.items,
           coalesce((o.pricing ->> 'subtotal')::bigint, 0) as subtotal,
           ((o.placed_at at time zone 'Africa/Cairo')::date) as day
      from public.orders o, window_at w
     where o.merchant_id = p_merchant_id
       and o.placed_at >= w.from_at
       and o.placed_at <  w.to_at
  ),
  sold as (select * from mine where status = 'delivered'),
  -- Every day in the window, joined to what happened on it. A bar chart built from the
  -- orders alone has holes where the quiet days were, which reads as missing data rather
  -- than as a Tuesday nobody ordered on.
  per_day as (
    select d::date as day,
           count(s.day)::int as orders,
           coalesce(sum(s.subtotal), 0)::bigint as sales
      from window_at w
      cross join generate_series(
             w.after_day - w.days, w.after_day - 1, interval '1 day') d
      left join sold s on s.day = d::date
     group by d::date
  ),
  -- One row per dish across the window, from the frozen lines rather than from today's
  -- menu: an item renamed or withdrawn last week still sold what it sold.
  items as (
    select line ->> 'itemId' as item_id,
           line ->> 'name'   as name,
           sum((line ->> 'quantity')::int) as quantity
      from sold, lateral jsonb_array_elements(sold.items) as line
     group by 1, 2
     order by sum((line ->> 'quantity')::int) desc, line ->> 'name'
     limit 5
  )
  select jsonb_build_object(
    'days',   (select days from window_at),
    'orders', (select count(*) from sold),
    'sales',  coalesce((select sum(subtotal) from sold), 0),
    -- Integer division deliberately: piastres, and an average of a half-piastre is not a
    -- number anybody can hand over.
    'average', case when (select count(*) from sold) = 0 then 0
                    else coalesce((select sum(subtotal) from sold), 0)
                         / (select count(*) from sold) end,
    'cancelledByCustomer',
      (select count(*) from mine where status = 'cancelled' and cancelled_by = 'customer'),
    'cancelledByMerchant',
      (select count(*) from mine where status = 'cancelled' and cancelled_by = 'merchant'),
    'returned',
      (select count(*) from mine where status = 'cancelled' and cancelled_by = 'courier'),
    'byDay', coalesce((
      select jsonb_agg(jsonb_build_object(
               'day', to_char(day, 'YYYY-MM-DD'), 'orders', orders, 'sales', sales)
             order by day) from per_day), '[]'::jsonb),
    'topItems', coalesce((
      select jsonb_agg(jsonb_build_object(
               'itemId', item_id, 'name', name, 'quantity', quantity))
        from items), '[]'::jsonb)
  );
$fn$;

-- `security invoker`, and that is what keeps this narrow: `read_orders` already decides
-- who may see a merchant's orders — the owner, their couriers, an admin — and this
-- counts what the caller can already read. A definer would have to re-implement that
-- decision, and a definer over `orders` is one mistake away from counting somebody
-- else's takings.
--
-- It follows that a courier calling this sees the shop's sales. That is the same
-- disclosure `read_orders` already makes to them order by order, so it discloses nothing
-- new — and the screen is the owner's.
revoke execute on function public.merchant_sales(uuid, integer) from public, anon;
grant execute on function public.merchant_sales(uuid, integer)
  to authenticated, service_role;
