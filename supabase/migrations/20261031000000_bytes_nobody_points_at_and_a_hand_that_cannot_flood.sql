-- M-03: a cap on uploading, and a sweep that starts from the bytes.
--
-- Two halves, and they cover each other. Neither alone is enough:
--
--   * A cap on `media` rows does not stop anybody filling the bucket with **bytes**. The
--     upload policy lets any signed-in person write an object under their own uid, and
--     `sweep_orphan_media` starts from `media` rows — so an object no row has ever named
--     is invisible to it, for ever, on a free tier with a gigabyte in it.
--   * A sweep does not stop anybody filling the **table**. It runs nightly and deletes
--     only what is a week old.
--
-- ------------------------------------------------------------------ the sweep starts from the wrong end
--
-- A lesson this repository has already learned once, on the other bucket.
-- `20261018000000` records it: the staff-documents sweep began from `staff_documents`
-- rows, so anything that removed the row — an auth cascade, a replacement — left the
-- objects behind for ever. The fix there was to keep the retention pass **and then**
-- garbage-collect every unreferenced object of the right age.
--
-- `sweep_orphan_media` never got that second pass. `upload()` writes the object and then
-- the row, and removes the bytes when the row fails — but a process that dies between the
-- two, or a connection that drops after the object lands, leaves bytes nothing will ever
-- look at again. The product cannot see them (it reads `media`), the admin cannot see
-- them (the queue reads `media`), and the sweep could not see them either.
--
-- ------------------------------------------------------------------ and it is edited in place
--
-- **The body is not re-emitted from any migration's text.** That mistake was made twice
-- while writing this file, and both times every test stayed green:
--
--   * `20260828040000` added `storage.allow_delete_query`, without which hosted Supabase's
--     `protect_delete` refuses every delete from `storage.objects`. PGlite has no
--     `protect_delete`, so a sweep that deletes nothing at all on production passes the
--     whole local suite.
--   * `20261001000000` widened the protected config keys to include
--     `developer_photo_media_id`. Dropping that would let the nightly job delete the
--     photograph on «حول لقمة» a week after it was uploaded.
--
-- So this edits `prosrc`, exactly as `20261001000000` did for the same function and for
-- the same reason, and it raises if the anchor it expects is not there exactly once — a
-- drift has to be loud rather than silently producing a sweep that does half its job.
do $migrate$
declare
  v_src     text;
  v_new     text;
  v_anchor  constant text := 'get diagnostics v_removed = row_count;';
  v_second  constant text := $p$get diagnostics v_removed = row_count;

  -- The second pass. Bytes that no row has ever named, older than the same week the
  -- first pass waits on. A newer object is left alone on purpose: an upload in flight
  -- has written its object and not yet its row, and sweeping that deletes the picture
  -- somebody is in the middle of adding.
  --
  -- Matched on the url rather than the id, because a media row points at an object by
  -- url and the first pass already strips the public prefix to get back to the name.
  delete from storage.objects o
   where o.bucket_id = 'media'
     and o.created_at <= now() - interval '7 days'
     and not exists (
       select 1 from public.media m
        where regexp_replace(m.url, '^.*/object/public/media/', '') = o.name
     );$p$;
begin
  select prosrc into strict v_src from pg_proc
   where oid = 'public.sweep_orphan_media()'::regprocedure;

  if (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'sweep_orphan_media no longer counts its removals exactly once; '
                    're-read it before adding the object pass.';
  end if;

  if pg_catalog.strpos(v_src, 'storage.allow_delete_query') = 0 then
    raise exception 'sweep_orphan_media has lost its storage delete door; '
                    'fix that before adding to it.';
  end if;

  v_new := replace(v_src, v_anchor, v_second);

  -- The signature and settings are the original's, spelled out — including
  -- `search_path = ''`, which the body depends on by qualifying everything.
  execute format(
    'create or replace function public.sweep_orphan_media() returns integer '
    'language plpgsql security definer set search_path = '''' as %L',
    v_new);
end;
$migrate$;

comment on function public.sweep_orphan_media() is
  'Two passes. The first removes media rows nothing points at, and their objects; the '
  'second removes objects no row has ever named, which the first cannot see because it '
  'starts from the rows. Same shape as sweep_staff_documents, and for the same reason.';

-- ------------------------------------------------------------------ and a hand that cannot flood
--
-- `media_upload` lets any signed-in person write objects under their own uid, and nothing
-- counted them. The owner is about to upload roughly six hundred photographs by hand over
-- a fortnight, so the cap has to be far above real use and only ever catch a script: the
-- default is 200 an hour, which is more than three a minute sustained for an hour.
--
-- Counted on the `media` row rather than on the object, because the row is what makes a
-- picture real to the product — and because a trigger on `storage.objects` would fire for
-- the staff-documents bucket too, which has its own rules and its own three-at-a-time
-- shape.
insert into public.config (key, value) values ('media_uploads_per_hour', '200'::jsonb)
on conflict (key) do nothing;

create or replace function public.media_uploads_per_hour()
returns integer
language sql
stable
set search_path = ''
as $fn$
  select coalesce(
    (select (value #>> '{}')::integer from public.config
      where key = 'media_uploads_per_hour'),
    200);
$fn$;

revoke all on function public.media_uploads_per_hour() from public, anon;
grant execute on function public.media_uploads_per_hour()
  to authenticated, service_role;

create or replace function public.guard_media_upload_rate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_recent integer;
begin
  -- Trusted server work declares itself, the same way every other guard here is passed.
  -- A seed, a migration and the nightly pass are not a person with a camera.
  if coalesce(pg_catalog.current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  -- Counted against the uploader the row names. The policy already requires that to be
  -- `auth.uid()`, so there is only one value it can hold — and a null one belongs to
  -- server work, which the guard above has already let through.
  if new.uploaded_by is null then
    return new;
  end if;

  select count(*) into v_recent
    from public.media
   where uploaded_by = new.uploaded_by
     and created_at > now() - interval '1 hour';

  if v_recent >= public.media_uploads_per_hour() then
    raise exception 'too many uploads in an hour'
      using errcode = '53400',
            hint = 'This is a rate limit, not a refusal of the picture.';
  end if;

  return new;
end;
$fn$;

revoke all on function public.guard_media_upload_rate() from public, anon, authenticated;

drop trigger if exists guard_media_upload_rate on public.media;
create trigger guard_media_upload_rate
  before insert on public.media
  for each row execute function public.guard_media_upload_rate();
