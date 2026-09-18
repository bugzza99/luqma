-- The shops' offers, on the customer's home.
--
-- Every restaurant has had an «العروض» shelf since 20261006000000, and the owner asked for
-- what is on those shelves to be the second thing a customer sees. A shelf is recognised by
-- a flag rather than by its name: a shop that renames «العروض» to «عروض الأسبوع» has not
-- stopped running offers, and a shop that happens to type the same word into a different
-- shelf has not started. The flag travels with the row through any rename.

alter table public.menu_categories
  add column if not exists is_offers boolean not null default false;

comment on column public.menu_categories.is_offers is
  'This shelf holds the shop''s offers, and what is on it reaches the customer''s home '
  '(offer_items). Set on the shelf a restaurant starts with; survives a rename.';

-- The shelves already made — «ابو حاتم»'s among them — were made by name.
update public.menu_categories set is_offers = true where name = 'العروض' and not is_offers;

-- And every new restaurant's second shelf is the offers shelf from the start.
create or replace function public.seed_default_menu_categories(p_merchant_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.menu_categories (merchant_id, name, sort_order, is_offers)
  select p_merchant_id, shelf.name, shelf.sort_order, shelf.is_offers
    from (values
      ('الوجبات الأساسية', 0, false),
      ('العروض',           1, true),
      ('الإضافات',          2, false),
      ('المشروبات',         3, false)
    ) as shelf(name, sort_order, is_offers)
   where not exists (
     select 1 from public.menu_categories where merchant_id = p_merchant_id
   );
$$;

revoke all on function public.seed_default_menu_categories(uuid) from public, anon, authenticated;

-- The same row shape as popular_items, so the customer app draws it with the same tile.
-- Newest first: an offer is news, and the one a shop put up this morning is the one it wants
-- seen. Only what a customer could actually order — an approved shop, an available dish —
-- and only an approved picture, the rule every image in the product follows.
create or replace function public.offer_items(p_city_id text, p_limit integer default 20)
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
  select mi.id,
         mi.merchant_id,
         m.name,
         mi.category_id,
         mi.name,
         mi.description,
         mi.price,
         mi.media_id,
         case when md.status = 'approved' then md.url end,
         mi.rating_avg,
         mi.rating_count,
         0::bigint
    from public.menu_items mi
    join public.menu_categories c on c.id = mi.category_id and c.is_offers
    join public.merchants m on m.id = mi.merchant_id
    left join public.media md on md.id = mi.media_id
   where m.city_id = p_city_id
     and m.status = 'approved'
     and mi.is_available
   order by mi.created_at desc, mi.name
   limit least(greatest(p_limit, 1), 50);
$$;

grant execute on function public.offer_items(text, integer) to anon, authenticated;

-- On every city's home, second — right under the category chips — as the owner asked. The
-- admin moves or hides it from «ترتيب الرئيسية» like any other section.
update public.home_sections h
   set sort_order = h.sort_order + 1
 where h.sort_order >= 1
   and not exists (select 1 from public.home_sections o
                    where o.city_id = h.city_id and o.key = 'offers');

insert into public.home_sections (key, city_id, type, title_ar, sort_order, is_visible)
select 'offers', c.id, 'offers', 'العروض', 1, true
  from public.cities c
on conflict (key, city_id) do nothing;

-- ------------------------------------------ A signed-out customer can see the shops again
--
-- Found writing the test above, and live in production: `read_approved_merchants` is a
-- policy for `anon` as well as `authenticated`, and its `belongs_to_merchant` reaches
-- `courier_carries` — which 20260920000000 revoked from `anon`. Postgres checks the right to
-- call a function when it plans the query, not when a row needs it, so every signed-out
-- read of `merchants` failed outright with "permission denied for function
-- courier_carries": the home, a shop, the popular shelf, all of it, for anybody browsing
-- before signing in.
--
-- Granting it is safe by construction: it answers only about `auth.uid()`, which for
-- `anon` is null, and a null caller carries no shop.
grant execute on function public.courier_carries(uuid) to anon;

-- The same browse, one shelf down: `popular_items` counts delivered orders, and a signed-out
-- caller has no right to read `orders`, so «الأكتر طلباً» failed for them too — silently,
-- because the home hides a shelf that cannot load. It returns dish counts and nothing about
-- any order or any customer, and still filters to approved shops and available dishes itself,
-- so it runs as its owner.
alter function public.popular_items(text, integer) security definer;
