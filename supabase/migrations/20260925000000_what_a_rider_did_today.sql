-- What a rider did today, per shop.
--
-- The courier is paid outside the app and no wage is modelled — that is settled and
-- recorded in `CLAUDE.md`. What the app can settle is the argument at the end of a shift:
-- how many deliveries, how much cash is in the rider's hand, and which shop each belongs
-- to. Every figure here is something the database already knows.
--
-- **Returns are counted and carry no money.** A delivery that came back — the customer
-- refused, or was not there — is an ordinary cancellation with a reason and
-- `cancelled_by = 'courier'`. It is a trip made, so the rider sees it; nothing was
-- collected, so it adds nothing to the cash. Whether that trip is paid for is between the
-- rider and the shop and is deliberately not a rule in this function.
--
-- Cairo's day, not UTC's. A shift that ends at one in the morning belongs to the evening
-- it started in as far as the rider is concerned, and `date_trunc` on a UTC `now()` would
-- cut it two hours early — the same trap `admin_today` documents from the other end.
create or replace function public.courier_day_summary(p_day date default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $fn$
  with bounds as (
    select (coalesce(p_day, (now() at time zone 'Africa/Cairo')::date)::timestamp
              at time zone 'Africa/Cairo') as from_at,
           ((coalesce(p_day, (now() at time zone 'Africa/Cairo')::date) + 1)::timestamp
              at time zone 'Africa/Cairo') as to_at
  ),
  mine as (
    select o.merchant_id,
           o.merchant_name,
           o.delivery_by,
           o.status,
           -- When the work happened, not when the row was last touched. A delivery is
           -- stamped with `delivered_at`; a return has no column of its own, so
           -- `updated_at` is the moment the courier marked it. Using `updated_at` for
           -- both would let an admin editing a note next week move last night's delivery
           -- into next week's shift.
           coalesce(o.delivered_at, o.updated_at) as happened_at,
           coalesce((o.pricing ->> 'total')::bigint, 0) as total
      from public.orders o, bounds b
     -- The courier's own work and nobody else's. `read_orders` would also show them every
     -- order of every shop they carry for, which is the right answer for a queue and the
     -- wrong one for a count of what *they* did.
     where o.courier_uid = (select auth.uid())
       and coalesce(o.delivered_at, o.updated_at) >= b.from_at
       and coalesce(o.delivered_at, o.updated_at) <  b.to_at
       and (o.status = 'delivered'
            or (o.status = 'cancelled' and o.cancelled_by = 'courier'))
  ),
  per_shop as (
    select merchant_id,
           min(merchant_name) as merchant_name,
           bool_or(delivery_by = 'platform') as any_platform,
           count(*) filter (where status = 'delivered')::int as delivered,
           count(*) filter (where status = 'cancelled')::int as returned,
           coalesce(sum(total) filter (where status = 'delivered'), 0)::bigint as cash
      from mine
     group by merchant_id
  )
  select jsonb_build_object(
    'delivered', coalesce((select sum(delivered) from per_shop), 0),
    'returned',  coalesce((select sum(returned) from per_shop), 0),
    'cash',      coalesce((select sum(cash) from per_shop), 0),
    'shops', coalesce((
      select jsonb_agg(jsonb_build_object(
               'merchantId', merchant_id,
               'merchantName', merchant_name,
               'platform', any_platform,
               'delivered', delivered,
               'returned', returned,
               'cash', cash)
             order by cash desc, merchant_name)
        from per_shop), '[]'::jsonb)
  );
$fn$;

-- `security invoker`, deliberately. The only rows this reads are the caller's own, matched
-- on `courier_uid = auth.uid()`, so there is nothing here a definer would be needed to
-- reach — and a definer that reads `orders` is a function one mistake away from returning
-- somebody else's. `read_orders` already lets a courier see these rows; this counts them.
revoke execute on function public.courier_day_summary(date) from public, anon;
grant execute on function public.courier_day_summary(date)
  to authenticated, service_role;
