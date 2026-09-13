-- An order from a shop is not permission to rate its whole menu.
--
-- The policies on `item_ratings` checked four things and never the fifth: the customer is
-- the caller, the order is theirs, the order is delivered, and it belongs to the same
-- merchant. Nothing asked whether the dish being rated was on it. So one real order from
-- a shop let a customer put a single star on every other item that shop sells, and
-- `refresh_item_rating` wrote each of those into `menu_items.rating_avg` — which is what
-- every dish card and «الأكتر طلباً» are built from. A vote on the whole menu, for the
-- price of one delivery.
--
-- Matched against the **frozen `itemId` on the order** rather than against today's menu,
-- for the reason the snapshot exists at all: that is the food the customer was actually
-- handed, and a dish edited or withdrawn next month must not change what last week's
-- order was. `@>` on the array is a containment test, so a line carrying a name, a price,
-- a quantity and its options still contains `{"itemId": …}`.
--
-- Corrections judge both rows. `using` sees the rating as it stands and `with check` the
-- rating as it will be, so rating what you ate and then moving the stars onto what you
-- did not is refused by the second. The delivered condition on `using` is defence rather
-- than a reachable gate — a rating cannot exist on an undelivered order, because the
-- insert would have been refused, and `delivered` is terminal — and it is spelled out
-- anyway because the two clauses drifting apart is exactly how the first hole opened.
alter policy rate_own_delivered_item on public.item_ratings
  with check (
    customer_uid = auth.uid()
    and exists (
      select 1 from public.orders o
       where o.id = item_ratings.order_id
         and o.customer_uid = auth.uid()
         and o.status = 'delivered'
         and o.merchant_id = item_ratings.merchant_id
         and o.items @> jsonb_build_array(jsonb_build_object('itemId', item_ratings.item_id::text))
    )
  );

alter policy correct_own_item_rating on public.item_ratings
  using (
    customer_uid = auth.uid()
    and exists (
      select 1 from public.orders o
       where o.id = item_ratings.order_id
         and o.customer_uid = auth.uid()
         and o.status = 'delivered'
         and o.merchant_id = item_ratings.merchant_id
         and o.items @> jsonb_build_array(jsonb_build_object('itemId', item_ratings.item_id::text))
    )
  )
  with check (
    customer_uid = auth.uid()
    and exists (
      select 1 from public.orders o
       where o.id = item_ratings.order_id
         and o.customer_uid = auth.uid()
         and o.status = 'delivered'
         and o.merchant_id = item_ratings.merchant_id
         and o.items @> jsonb_build_array(jsonb_build_object('itemId', item_ratings.item_id::text))
    )
  );
