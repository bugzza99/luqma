-- Somewhere for an image to actually go, and cuisines to put on the home screen.
--
-- Every image column in this product has existed since the first schema — a merchant's
-- logo and cover, a menu item, a daily meal, a promotion — and the moderation queue that
-- reviews them was built and tested. **Nothing could ever put an image in any of them:**
-- there was no bucket, no policy on `storage.objects`, and no upload method on the
-- repository. The queue reviewed a table nothing wrote to, and every screen in the
-- product drew a grey box.

-- ---------------------------------------------------------------- the bucket

-- Public, and the path carries a uuid nobody can guess. The alternatives were both
-- worse: a private bucket makes every one of ~600 menu photos a signed URL that expires
-- and has to be re-minted, and a pending/approved bucket pair stores each image twice
-- during review and turns "approve" into a copy that can half-fail.
--
-- What keeps an unapproved image out of the product is the `media` row, not the object:
-- `read_media` hides anything not approved, and a rejected image is deleted outright
-- rather than left lying around unreferenced.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 2097152,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = true,
      file_size_limit = 2097152,
      allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

-- 2 MiB is not a guess. The apps downscale to 1600px at 85% quality before upload, which
-- lands a phone photo around 200 KB; the limit is the backstop for a build that forgets
-- to, not the working size. Without one, 600 menu items at a phone's native 5 MB is 3 GB
-- against a 1 GB free tier.

create policy media_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'media');

create policy media_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'media');

-- Deleting is the admin's, because deleting is what rejection *is* — and an uploader who
-- can delete can also delete the photo an order was placed against.
create policy media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and public.is_admin());

-- ---------------------------------------------------------------- two more things an image can be of

-- The owner's photo on حول لقمة and the picture on a cuisine circle are images like any
-- other, so they need a kind — there is one door for images and no second path.
alter table media drop constraint media_kind_check;
alter table media add constraint media_kind_check
  check (kind in ('merchantLogo', 'merchantCover', 'menuItem', 'dailyMeal', 'promotion',
                  'aboutPhoto', 'cuisine'));

-- ---------------------------------------------------------------- cuisines

-- What the circles across the top of the customer's home are.
--
-- Deliberately *not* `menu_categories`: that is one shop's own sectioning — "أطباق
-- رئيسية", "مشروبات" — and it is per-merchant. A cuisine is a city-wide kind of food
-- that a customer browses by, and it needs a picture, which means it needs a row.
--
-- Until now `categoryChips` rendered four Arabic words compiled into the app and
-- filtered nothing.
create table cuisines (
  id         uuid primary key default gen_random_uuid(),
  city_id    text not null references cities on delete restrict,
  name       text not null,
  media_id   uuid references media on delete set null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cuisines_name_per_city unique (city_id, name)
);
create index cuisines_city_idx on cuisines (city_id, sort_order);
create index cuisines_media_idx on cuisines (media_id) where media_id is not null;

create table merchant_cuisines (
  merchant_id uuid not null references merchants on delete cascade,
  cuisine_id  uuid not null references cuisines on delete cascade,
  primary key (merchant_id, cuisine_id)
);
create index merchant_cuisines_cuisine_idx on merchant_cuisines (cuisine_id);

alter table cuisines enable row level security;
alter table merchant_cuisines enable row level security;

-- Everybody reads: this is the top of the home screen, and a signed-out customer
-- browsing sees it before they have an account.
grant select on cuisines, merchant_cuisines to anon, authenticated;
create policy read_cuisines on cuisines for select to anon, authenticated using (true);
create policy read_merchant_cuisines on merchant_cuisines
  for select to anon, authenticated using (true);

-- Only an admin writes either. A merchant tagging itself into "مشويات" to appear under a
-- circle it does not belong in is the cheapest promotion in the product, and promotion is
-- something merchants pay for — see `promotions`.
grant insert, update, delete on cuisines, merchant_cuisines to authenticated;
create policy admin_cuisines on cuisines for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_merchant_cuisines on merchant_cuisines for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create trigger cuisines_set_updated_at before update on cuisines
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------- how long the food takes

-- One number, not a range. Edku is ten minutes across on a motorbike, so what actually
-- varies between two shops is the kitchen, not the distance — and a "25–35" built from
-- two hand-typed numbers reads as a precision nobody measured.
--
-- Bounded because it is typed: 600 is a typo, not a kitchen.
alter table merchants add column prep_minutes integer not null default 30
  check (prep_minutes between 5 and 180);

-- The merchant knows their own kitchen better than the admin does.
drop trigger merchants_guard_columns on merchants;
create trigger merchants_guard_columns before update on merchants for each row
  execute function public.guard_columns(
    '{name,phone,logo_media_id,cover_media_id,opening_hours,paused_until,min_order,delivery_fee_override,prep_minutes}');

-- ---------------------------------------------------------------- images nobody claimed

-- Somebody opens the picker, uploads, then backs out before attaching it to anything.
-- The row and the object both stay, for ever, against a 1 GB tier.
--
-- Seven days rather than seven minutes: an image is uploaded *before* the menu item that
-- references it exists, so anything shorter races the person still typing the form.
create or replace function public.sweep_orphan_media()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_removed integer;
begin
  with orphans as (
    select m.id, m.url
      from public.media m
     where m.status = 'pending'
       and m.created_at < now() - interval '7 days'
       and not exists (select 1 from public.merchants x where x.logo_media_id = m.id)
       and not exists (select 1 from public.merchants x where x.cover_media_id = m.id)
       and not exists (select 1 from public.menu_items x where x.media_id = m.id)
       and not exists (select 1 from public.daily_meals x where x.media_id = m.id)
       and not exists (select 1 from public.promotions x where x.media_id = m.id)
       and not exists (select 1 from public.cuisines x where x.media_id = m.id)
       and not exists (select 1 from public.config c
                        where c.key = 'about_photo_media_id'
                          and c.value #>> '{}' = m.id::text)
  ), gone as (
    delete from storage.objects o using orphans
     where o.bucket_id = 'media' and orphans.url like '%' || o.name
    returning 1
  )
  delete from public.media m using orphans where m.id = orphans.id;

  get diagnostics v_removed = row_count;
  return v_removed;
end;
$$;

-- Guarded by availability, exactly as `20260824130000_scheduled_jobs.sql` does it: PGlite
-- runs the local migration suite and has no pg_cron, and a bare `cron.schedule` there
-- stops every migration after this line.
do $$
declare v_cron boolean;
begin
  select count(*) > 0 into v_cron from pg_available_extensions where name = 'pg_cron';
  if v_cron then
    create extension if not exists pg_cron;
    perform cron.unschedule('sweep-orphan-media')
      where exists (select 1 from cron.job where jobname = 'sweep-orphan-media');
    perform cron.schedule('sweep-orphan-media', '30 3 * * *',
                          $c$select public.sweep_orphan_media()$c$);
  end if;
end;
$$;
