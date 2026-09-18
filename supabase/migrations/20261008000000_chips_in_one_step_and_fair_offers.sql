-- A shop's chips change in one step, and the offers shelf is fair to every shop.

-- ------------------------------------------------------------- Chips, all or nothing
--
-- The admin app set a shop's chips as two requests: delete them all, then insert the new
-- set. A dropped connection — or a chip deleted in another tab a second earlier — between
-- the two left the shop in no chip at all, under a screen that said the save had failed.
-- One function, one transaction: either the new set, or the old one untouched.
--
-- Security invoker on purpose: `admin_merchant_cuisines` already decides who may write
-- these rows, and a definer here would be a second place that has to get that right.
create or replace function public.set_merchant_cuisines(
  p_merchant_id uuid,
  p_cuisine_ids uuid[]
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not public.is_admin() then
    raise exception 'only an admin puts a shop in a category' using errcode = '42501';
  end if;

  delete from public.merchant_cuisines where merchant_id = p_merchant_id;

  insert into public.merchant_cuisines (merchant_id, cuisine_id)
  select p_merchant_id, c
    from unnest(coalesce(p_cuisine_ids, '{}'::uuid[])) as c
  on conflict do nothing;
end;
$$;

revoke all on function public.set_merchant_cuisines(uuid, uuid[]) from public, anon;
grant execute on function public.set_merchant_cuisines(uuid, uuid[]) to authenticated;

-- ------------------------------------------------------------- Fair offers
--
-- Newest first, twenty at most, meant one busy shop publishing twenty offers pushed every
-- other shop's off the home. Now each shop's newest offer comes before any shop's second,
-- and so on down — the first row of the shelf is one offer per shop. The ceiling rises to
-- two hundred so the «see all» list can hold every offer in a town this size.
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
  with offered as (
    select mi.*,
           m.name as shop_name,
           row_number() over (partition by mi.merchant_id
                              order by mi.created_at desc, mi.name) as nth
      from public.menu_items mi
      join public.menu_categories c on c.id = mi.category_id and c.is_offers
      join public.merchants m on m.id = mi.merchant_id
     where m.city_id = p_city_id
       and m.status = 'approved'
       and mi.is_available
  )
  select o.id,
         o.merchant_id,
         o.shop_name,
         o.category_id,
         o.name,
         o.description,
         o.price,
         o.media_id,
         case when md.status = 'approved' then md.url end,
         o.rating_avg,
         o.rating_count,
         0::bigint
    from offered o
    left join public.media md on md.id = o.media_id
   order by o.nth, o.created_at desc, o.name
   limit least(greatest(p_limit, 1), 200);
$$;

grant execute on function public.offer_items(text, integer) to anon, authenticated;
