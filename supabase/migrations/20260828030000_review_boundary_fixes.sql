-- Six defects a review found in code that had been green for weeks.
--
-- They share a shape rather than a file: each is a statement that is correct for the
-- case somebody had in mind and wrong for one nobody wrote down. One city. A list that
-- is there. A row that is only ever inserted. A rating that is only ever created.

-- ---------------------------------------------------------------- one city at a time

-- `home_sections` is keyed `(key, city_id)` — the same `key` exists once per city, on
-- purpose. `reorder_home_sections(p_keys)` matched on `key` alone, so arranging Edku's
-- home rearranged every other city's along with it.
--
-- Edku is the only city today, which is exactly why this could sit here unnoticed: there
-- is no second city for it to damage yet. The whole data model carries `city_id`
-- precisely so that one day there is.
drop function if exists public.reorder_home_sections(text[]);

create function public.reorder_home_sections(p_keys text[], p_city_id text)
returns void
language sql
as $$
  update home_sections s
    set sort_order = k.ord - 1
    from unnest(p_keys) with ordinality as k(key, ord)
    where s.key = k.key
      and s.city_id is not distinct from p_city_id;
$$;

revoke execute on function public.reorder_home_sections(text[], text) from public, anon;
grant execute on function public.reorder_home_sections(text[], text) to authenticated;

-- ---------------------------------------------------------------- a list that is not there

-- `jsonb_array_elements(null)` returns no rows rather than raising, so
-- `not exists (select 1 from jsonb_array_elements(p_categories) ...)` was true of every
-- category the merchant had: a call that lost its argument deleted the entire menu and
-- reported success.
--
-- An empty array stays a real instruction — clearing a menu on purpose is something
-- somebody may mean. It is *absence* that is refused, because absence is never meant.
create or replace function public.save_menu_categories(p_merchant_id uuid, p_categories jsonb)
returns jsonb
language plpgsql
as $$
declare
  cat record;
begin
  if p_categories is null or jsonb_typeof(p_categories) <> 'array' then
    raise exception 'save_menu_categories needs an array of categories'
      using errcode = 'P0001';
  end if;

  -- Gone from the incoming list means gone.
  delete from public.menu_categories c
   where c.merchant_id = p_merchant_id
     and not exists (
       select 1
         from jsonb_array_elements(p_categories) as incoming
        where incoming.value ->> 'id' = c.id::text
     );

  for cat in select * from jsonb_array_elements(p_categories) loop
    if coalesce(cat.value ->> 'id', '') = '' then
      insert into public.menu_categories (merchant_id, name, sort_order)
      values (p_merchant_id, cat.value ->> 'name',
              coalesce((cat.value ->> 'sort_order')::int, 0));
    else
      update public.menu_categories
         set name = cat.value ->> 'name',
             sort_order = coalesce((cat.value ->> 'sort_order')::int, 0)
       where id = (cat.value ->> 'id')::uuid
         and merchant_id = p_merchant_id;
    end if;
  end loop;

  return (select coalesce(jsonb_agg(jsonb_build_object(
                   'id', c.id, 'name', c.name, 'sort_order', c.sort_order)
                   order by c.sort_order), '[]'::jsonb)
            from public.menu_categories c
           where c.merchant_id = p_merchant_id);
end;
$$;

-- ---------------------------------------------------------------- a column that told the truth once

-- Every other table with `updated_at` got its trigger from one `foreach` list in the
-- first schema. `config` was left out of that array, so its `updated_at` stayed the
-- insert time for ever — a column that answers its question wrongly rather than not at
-- all.
drop trigger if exists config_set_updated_at on config;
create trigger config_set_updated_at before update on config
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------- moving stars

-- `rate_own_delivered_order` is careful: the rating must belong to the customer, and to
-- an order that customer actually received from that merchant. `correct_own_rating`
-- checked only the first half.
--
-- So a customer could rate a shop they really had ordered from, then UPDATE that same
-- row to point `merchant_id` at any other shop in the city — one star, on a merchant
-- they had never bought anything from, as many times as there are merchants. Correcting
-- a rating and inventing one have to be judged by the same rule.
drop policy if exists correct_own_rating on ratings;
create policy correct_own_rating on ratings for update to authenticated
  using (customer_uid = auth.uid())
  with check (customer_uid = auth.uid()
              and exists (select 1 from orders o
                           where o.id = order_id
                             and o.customer_uid = auth.uid()
                             and o.merchant_id = ratings.merchant_id
                             and o.status = 'delivered'));

-- ---------------------------------------------------------------- whose object is it

-- `media_upload` checked only the bucket, so any signed-in customer could write any
-- object name into a **public** bucket: an unbounded number of 2 MiB files, each served
-- from the project's own domain the moment it lands, against a 1 GB tier.
--
-- The `media` row is still what keeps an unapproved image out of the product — but a row
-- governs what the app renders, not what a direct URL serves, and the daily orphan sweep
-- only reaches rows older than seven days.
--
-- A per-uploader prefix does not by itself bound the volume. What it does is make the
-- objects addressable as one person's, so an abusive account can be emptied in a single
-- statement rather than joined back through `owner` a row at a time.
--
-- `sweep_orphan_media` needs no change: it already derives the object name as everything
-- after `/object/public/media/`, whatever shape the rest of the path takes.
-- `split_part(name, '/', 1)` rather than `storage.foldername(name)[1]`: they mean the
-- same thing for this shape, and the first is ordinary Postgres. The schema tests run on
-- PGlite, which has the `storage` tables but not Storage's own functions, so a policy
-- written on `foldername` fails at *migration* time there and takes every migration after
-- it down with it.
drop policy if exists media_upload on storage.objects;
create policy media_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'media'
              and split_part(name, '/', 1) = auth.uid()::text);

-- ---------------------------------------------------------------- two people, one code

-- The coupon checks read `coupon_redemptions` and `coupons.used_count`, then decide.
-- Nothing held the coupon still in between, and `coupon_redemptions` is unique on
-- `order_id` alone — so two orders placed at the same moment both saw a fresh count and
-- both passed. `per_user_limit` and `total_limit` were advisory under exactly the load
-- that makes a code worth abusing.
--
-- The lock goes in this wrapper rather than inside `place_order_priced`, which is 360
-- lines of money arithmetic: a second copy of that function differing by two words is a
-- worse risk than the race it closes. `place_order` is the only entry point a client can
-- reach — `place_order_priced` is revoked from `anon` and `authenticated` — so a lock
-- taken here is a lock taken on every path that can redeem anything.
create or replace function public.place_order(p_draft jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_code text;
begin
  if auth.uid() is null then
    raise exception 'sign in to place an order' using errcode = '42501';
  end if;

  if exists (select 1 from public.users where id = auth.uid() and is_blocked) then
    raise exception 'this account cannot place orders' using errcode = '42501';
  end if;

  perform public.check_draft_bounds(p_draft);

  -- Only when a code was actually offered: an ordinary order must not queue behind
  -- anything, and with no code there is nothing to hold still.
  v_code := nullif(btrim(p_draft ->> 'couponCode'), '');
  if v_code is not null then
    perform 1
       from public.coupons c
       join public.merchants m on m.id = (p_draft ->> 'merchantId')::uuid
      where c.city_id = m.city_id
        and c.code = upper(translate(v_code, U&'\0660\0661\0662\0663\0664\0665\0666\0667\0668\0669', '0123456789'))
      for update of c;
  end if;

  return public.place_order_priced(p_draft);
end;
$fn$;

revoke execute on function public.place_order(jsonb) from public, anon;
