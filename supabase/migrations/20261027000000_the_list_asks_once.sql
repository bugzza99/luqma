-- M-12: the merchants list asks once instead of once per shop.
--
-- Every card on AdminApp's merchants screen watched `merchantOrderCountProvider(id)`,
-- and that provider is an exact `count` against `orders` filtered to one shop. So opening
-- the screen made one HTTPS round trip per merchant — fifteen shops, fifteen requests,
-- each waiting on the internet from a phone in Edku. It is invisible with two shops and
-- it is the screen the owner lives on during the launch.
--
-- Counted by the database, in one statement, for a whole city.
--
-- **The delete decision deliberately does not use this.** The detail pane keeps its own
-- single exact count, because that number decides whether the delete control is offered
-- at all, and `orders.merchant_id` is `on delete restrict`: a batched figure fetched when
-- the list was built would offer a delete for a shop that took an order a minute later,
-- and the database would refuse it with `23503` after the admin had already confirmed.
-- One is a label and the other is a decision; they are allowed to be different queries.
--
-- `is_admin()` rather than `is_platform_admin()`: this is reading, which is what a
-- moderator is for.
create or replace function public.admin_merchant_order_counts(p_city_id text)
returns table (merchant_id uuid, orders integer)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
begin
  -- Refused rather than answered with nothing. A `security definer` function that puts
  -- `is_admin()` in its WHERE hands a non-admin an empty set, and an empty set reads as
  -- «there are no shops» — which is a sentence this product says for real. Same rule the
  -- policies are written under, reached from the function side.
  if not public.is_admin() then
    raise exception 'only an admin reads the shops'' order counts' using errcode = '42501';
  end if;

  return query
    select m.id, count(o.id)::integer
      from public.merchants m
      left join public.orders o on o.merchant_id = m.id
     where m.city_id = p_city_id
     group by m.id;
end;
$fn$;

comment on function public.admin_merchant_order_counts(text) is
  'How many orders each shop in a city has taken, in one statement. The label on the '
  'merchants list. The delete decision uses its own exact count per shop, because that '
  'one is a decision rather than a label.';

revoke all on function public.admin_merchant_order_counts(text) from public, anon;
grant execute on function public.admin_merchant_order_counts(text)
  to authenticated, service_role;

-- No index is added here, deliberately. `orders_merchant_status_idx` has existed since
-- the first schema as `(merchant_id, status, placed_at desc)`, and `merchant_id` is its
-- leading column, so the grouped count can already use it. Adding a second index on the
-- same leading column would be an extra write on every order placed, to buy nothing —
-- which is the mistake the next item on the list warns against in its own words: add
-- foreign-key indexes from `supabase db lint` and real plans, never blindly.
