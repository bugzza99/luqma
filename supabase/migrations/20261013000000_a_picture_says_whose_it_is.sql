-- A picture in the moderation queue says whose it is (QA review 2026-09-19).
--
-- The card showed the photograph, its kind and «بواسطة: <uuid>» — so an admin approving a
-- dish photo could not tell which shop's menu it would appear on, or whether it was the dish
-- it claimed to be. `media.owner_id` already points at the thing each kind belongs to; this
-- names it, for the pending queue only, in one call rather than one lookup per card.

create or replace function public.admin_media_context(p_ids uuid[])
returns table (media_id uuid, shop text, item text, uploader text)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'only an admin' using errcode = '42501';
  end if;

  return query
  select m.id,
         coalesce(owner_shop.name, item_shop.name, meal_shop.name, promo_shop.name,
                  uploader_shop.name),
         coalesce(mi.name, dm.name, nullif(p.title, ''), c.name),
         coalesce(nullif(u.name, ''), uploader_shop.name)
    from public.media m
    left join public.merchants owner_shop
           on m.kind in ('merchantLogo', 'merchantCover') and owner_shop.id = m.owner_id
    left join public.menu_items mi on m.kind = 'menuItem' and mi.id = m.owner_id
    left join public.merchants item_shop on item_shop.id = mi.merchant_id
    left join public.daily_meals dm on m.kind = 'dailyMeal' and dm.id = m.owner_id
    left join public.merchants meal_shop on meal_shop.id = dm.merchant_id
    left join public.promotions p on m.kind = 'promotion' and p.id = m.owner_id
    left join public.merchants promo_shop on promo_shop.id = p.merchant_id
    left join public.cuisines c on m.kind = 'cuisine' and c.id = m.owner_id
    left join public.users u on u.id = m.uploaded_by
    left join public.staff s on s.uid = m.uploaded_by
    left join public.merchants uploader_shop on uploader_shop.id = s.merchant_id
   where m.id = any(p_ids);
end;
$$;

revoke execute on function public.admin_media_context(uuid[]) from public, anon;
grant execute on function public.admin_media_context(uuid[]) to authenticated;
