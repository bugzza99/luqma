-- The nightly orphan sweep has never once run on a hosted project.
--
-- Hosted Supabase carries a trigger on `storage.objects` called `protect_delete`:
--
--   IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true'
--   THEN RAISE EXCEPTION 'Direct deletion from storage tables is not allowed.
--                         Use the Storage API instead.' USING ERRCODE = '42501';
--
-- `sweep_orphan_media` is a direct DELETE, so every 03:30 run since the job was
-- scheduled has raised 42501 and rolled back — the `media` rows and the objects both
-- survived, on both projects.
--
-- Three things kept that invisible, and they are worth naming because they are the
-- general case, not this bug:
--
--   * The trigger does not exist on PGlite, which has the `storage` tables only because
--     our own migrations create them. The schema suite was therefore testing a database
--     where the failure cannot happen.
--   * The job's only output is a `cron.job_run_details` row nobody reads. A scheduled
--     job that fails looks exactly like a scheduled job that had nothing to do.
--   * What it fails to do — reclaim space from images nobody attached — looks like an
--     empty bucket right up until the 1 GB tier is full.
--
-- The trigger names its own way through, and it is a transaction-local setting rather
-- than a privilege: the point is to stop a careless hand-typed DELETE, not to stop a
-- function written for the purpose. `set_config(..., true)` lasts until this statement's
-- transaction ends and is visible to nothing else.
--
-- `pg_catalog.set_config` is spelled out because the function runs with `search_path = ''`.
create or replace function public.sweep_orphan_media()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_removed integer;
begin
  perform pg_catalog.set_config('storage.allow_delete_query', 'true', true);

  with orphans as (
    select m.id,
           -- Everything after the bucket segment: `<uploader>/menuItem/<uuid>.jpg`.
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
