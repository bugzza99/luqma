-- A picture has a small copy beside it, and the server knows it belongs to it.
--
-- Every image was one JPEG at 1600px, ~200 KB, and a menu thumbnail drawn 78 points wide
-- downloaded all of it — every time the app opened, since nothing kept it on the phone.
-- With fifteen shops photographed that is about ten megabytes a visit, and the free tier's
-- egress runs out at roughly thirty visits a day. From the next build every upload writes a
-- small copy next to the photograph — the same name with `_s` before the extension, 400px —
-- which lists and thumbnails draw, and the phone keeps what it downloads.
--
-- The copy has no `media` row of its own; it is named after the photograph's. Two things
-- on the server had to learn that:
--
--   * `sweep_orphan_media` deletes, in its second pass, every object no row names. A copy
--     would have been deleted a week after upload — every thumbnail in the product. It is
--     read now as belonging to the object it is a copy of, and taken with an orphan.
--   * `storage_upload_within_rate` counts objects. A picture is two of them now, so the
--     hourly allowance for `media` is twice the pictures-per-hour setting; the number of
--     pictures a person can add in an hour is unchanged.
--
-- Both patched in place; each anchor must match exactly once.

do $migrate$
declare
  v_def text;
  v_old_first constant text := '       and o.name = orphans.object_name';
  v_old_second constant text :=
    '        where regexp_replace(m.url, ''^.*/object/public/media/'', '''') = o.name';
  v_old_rate constant text := '                      when ''media'' then public.media_uploads_per_hour()';
begin
  select pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), chr(13), '') into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'sweep_orphan_media';

  if (length(v_def) - length(replace(v_def, v_old_first, ''))) / length(v_old_first) <> 1
     or (length(v_def) - length(replace(v_def, v_old_second, ''))) / length(v_old_second) <> 1 then
    raise exception 'sweep_orphan_media has drifted; re-read it before patching.';
  end if;

  v_def := replace(v_def, v_old_first,
    '       -- The photograph and its small copy, `<name>_s.<ext>`, go together.
       and o.name in (orphans.object_name,
                      regexp_replace(orphans.object_name, ''(\.[A-Za-z0-9]+)$'', ''_s\1''))');
  v_def := replace(v_def, v_old_second,
    '        -- A small copy is named after its photograph and has no row of its own.
        where regexp_replace(m.url, ''^.*/object/public/media/'', '''')
              in (o.name, regexp_replace(o.name, ''_s(\.[A-Za-z0-9]+)$'', ''\1''))');
  execute v_def;

  select pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), chr(13), '') into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'storage_upload_within_rate';

  if (length(v_def) - length(replace(v_def, v_old_rate, ''))) / length(v_old_rate) <> 1 then
    raise exception 'storage_upload_within_rate has drifted; re-read it before patching.';
  end if;

  execute replace(v_def, v_old_rate,
    '                      -- Two objects a picture: the photograph and its small copy.
                      when ''media'' then public.media_uploads_per_hour() * 2');
end;
$migrate$;
