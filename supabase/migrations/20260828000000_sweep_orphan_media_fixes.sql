-- Two things wrong with the orphan sweep, both found by review.
--
-- The function deletes rows from `media` and objects from Storage. It is worth being
-- exact about who may call it and about which object it matches.

-- ---------------------------------------------------------------- who may call it

-- Postgres grants EXECUTE on a new function to PUBLIC. `sweep_orphan_media` is
-- `security definer` and deletes, so **any API caller could invoke it** — the nightly
-- clean-up was reachable from every phone in the city.
--
-- Every other definer function here was revoked when it was written; this one was not,
-- and nothing failed as a result, which is exactly why it survived.
revoke all on function public.sweep_orphan_media() from public, anon, authenticated;

-- ---------------------------------------------------------------- which object it matches

-- The old match was `orphans.url like '%' || o.name`, which is wrong twice over:
--
--   * A shorter object name that happens to be a suffix of an orphan's URL matches it.
--     An orphan ending `…/abc1.jpg` matches an unrelated object literally named `1.jpg`,
--     and that object is deleted while its own `media` row lives on — a picture that
--     vanishes from a menu with the row still pointing at it.
--
--   * `%` and `_` inside a name are wildcards to LIKE, so one name can match many URLs.
--     Nothing writes such a name today, but nothing stops one either.
--
-- The URL is built by `getPublicUrl`, so its tail *is* the object path. Strip the fixed
-- prefix and compare for equality instead of pattern-matching: exact, anchored, and with
-- no character that means anything special.
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
    select m.id,
           -- Everything after the bucket segment: `menuItem/<uuid>.jpg`.
           regexp_replace(m.url, '^.*/object/public/media/', '') as object_name
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
     where o.bucket_id = 'media'
       -- Equality, not LIKE. A row whose url did not come from this bucket strips to
       -- something that matches no object, which is the right outcome: leave it alone.
       and o.name = orphans.object_name
    returning 1
  )
  delete from public.media m using orphans where m.id = orphans.id;

  get diagnostics v_removed = row_count;
  return v_removed;
end;
$$;

revoke all on function public.sweep_orphan_media() from public, anon, authenticated;
