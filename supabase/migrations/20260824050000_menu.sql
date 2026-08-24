-- The menu joins realtime: both of its tables are watched live.
alter publication supabase_realtime add table menu_categories;
alter publication supabase_realtime add table menu_items;

-- ---------------------------------------------------------------- categories

-- Saving a menu's categories, in one statement.
--
-- The editor sends the whole list every time: some renamed, some reordered, some new,
-- some gone. Firestore updated one inline array. Here that is three kinds of statement,
-- and half-applied is not an option — a category deleted but its replacement missing
-- leaves items pointing at nothing. So the batch becomes this function: the removals,
-- the updates, the inserts and the read-back land together or not at all.
--
-- Returns the resulting list with ids filled in, so newly added categories come back
-- addressable without waiting for the realtime echo.
create function public.save_menu_categories(p_merchant_id uuid, p_categories jsonb)
returns jsonb
language plpgsql
as $$
declare
  cat record;
begin
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

  return coalesce((
    select jsonb_agg(
             jsonb_build_object('id', id, 'name', name, 'sort_order', sort_order)
             order by sort_order
           )
      from public.menu_categories
     where merchant_id = p_merchant_id
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.save_menu_categories(uuid, jsonb) from public, anon;
grant execute on function public.save_menu_categories(uuid, jsonb)
  to authenticated, service_role;
