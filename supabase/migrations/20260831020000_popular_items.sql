-- What the city actually orders.
--
-- The home screen's "الأكتر طلباً" section sorted *merchants* by `rating_count`, with a
-- comment admitting it stood in for an order count that did not exist. So the section
-- named after what people order was ranked by how many of them left a review — two
-- different things, and on a launch with no reviews it was every merchant in arbitrary
-- order under a heading that promised otherwise.
--
-- This is the real answer, and it is about dishes rather than shops: what a customer
-- wants from that heading is food they can tap, not a second copy of the merchant list.

-- Counted from `orders.items`, which is a frozen jsonb snapshot rather than a join table.
--
-- That snapshot is deliberate — a menu edited tomorrow must not rewrite what somebody
-- ordered today — and it means the count has to be unnested rather than grouped. Each
-- line carries the `itemId` it was ordered from, so the aggregate can find its way back
-- to a dish that still exists; one whose menu row has since been deleted simply drops out
-- of the join, which is correct, because it cannot be put in a basket either.
--
-- Delivered only. An order that was placed and then rejected is not evidence that anybody
-- wanted the food, and counting cancellations would let a shop rank itself by failing.
create or replace function public.popular_items(p_city_id text, p_limit integer default 12)
returns table (
  id uuid,
  merchant_id uuid,
  merchant_name text,
  category_id uuid,
  name text,
  description text,
  price integer,
  media_id uuid,
  image_url text,
  rating_avg numeric,
  rating_count integer,
  ordered_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with counted as (
    select (line ->> 'itemId')::uuid item_id,
           sum((line ->> 'quantity')::int) n
      from public.orders o
      cross join lateral jsonb_array_elements(o.items) line
     where o.city_id = p_city_id
       and o.status = 'delivered'
       and (line ->> 'itemId') is not null
     group by 1
  )
  select mi.id,
         mi.merchant_id,
         m.name,
         mi.category_id,
         mi.name,
         mi.description,
         mi.price,
         mi.media_id,
         -- Null unless approved, the same rule every other picture in the product
         -- follows: an unreviewed image must never reach a home screen.
         case when md.status = 'approved' then md.url end,
         mi.rating_avg,
         mi.rating_count,
         coalesce(c.n, 0)
    from public.menu_items mi
    join public.merchants m on m.id = mi.merchant_id
    left join counted c on c.item_id = mi.id
    left join public.media md on md.id = mi.media_id
   where m.city_id = p_city_id
     and m.status = 'approved'
     and mi.is_available
   -- A left join, not an inner one, and this is the whole reason: on launch day nothing
   -- has been delivered, so an inner join returns an empty section under a heading the
   -- admin deliberately put on the home screen. Falling back to the best-rated available
   -- food means the shelf is full from the first customer and fills with what actually
   -- sells as the orders arrive.
   order by coalesce(c.n, 0) desc, mi.rating_avg desc, mi.rating_count desc, mi.name
   limit greatest(p_limit, 1);
$$;

grant execute on function public.popular_items(text, integer) to anon, authenticated;

comment on function public.popular_items(text, integer) is
  'Dishes ranked by delivered quantity, falling back to rating so the shelf is never '
  'empty. security invoker: every row it returns is already publicly readable, and '
  'inheriting the caller''s rights keeps it that way when the policies change.';
