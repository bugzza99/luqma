-- «حول لقمة» and the person who made it are two pages now.
--
-- They were one: the owner's photo, their personal links and a description of the app, on
-- a screen titled "about Luqma". The owner asked for the developer to stand entirely apart,
-- so a customer reading about the product is not reading a biography, and the biography
-- has a name and a few sentences of its own rather than a caption under a photo.
--
-- Everything lives on `config`, so this is keys, not tables:
--
--   about_description          stays — it is the product's.
--   developer_name             new
--   developer_bio              new
--   developer_photo_media_id   ← about_photo_media_id
--   developer_facebook         ← about_facebook
--   developer_whatsapp         ← about_whatsapp
--   developer_instagram        ← about_instagram
--
-- **Copied, not moved.** Those four about_* values were entered next to the words «صورتك»
-- — they are the owner's, and they carry over so nobody has to type them again. The old
-- rows are left where they are and nothing reads them any more: deleting live
-- configuration in a migration is a destructive write with no benefit, and `about_photo_
-- media_id` keeps protecting that photo from the sweep below until someone replaces it.
insert into public.config (key, value)
select replace(c.key, 'about_', 'developer_'), c.value
  from public.config c
 where c.key in ('about_photo_media_id', 'about_facebook', 'about_whatsapp', 'about_instagram')
on conflict (key) do nothing;

-- The orphan sweep deletes pending images older than a week that nothing references, and
-- it knows the references by name. A photo referenced only by the new key would read as an
-- orphan and be deleted from Storage. An admin's upload arrives approved and the sweep only
-- touches pending ones, so today this is belt and braces — which is the right amount of
-- caution for the one image in the product that is a person's face.
--
-- Edited in place through `prosrc`, the same way `place_order_priced` is, rather than
-- re-emitted from the older migration's text.
do $migrate$
declare
  v_src text;
  v_new text;
  v_pattern constant text := $p$where c.key = 'about_photo_media_id'$p$;
begin
  select prosrc into strict v_src from pg_proc
   where oid = 'public.sweep_orphan_media()'::regprocedure;

  if (length(v_src) - length(replace(v_src, v_pattern, ''))) / length(v_pattern) <> 1 then
    raise exception 'sweep_orphan_media no longer names the about photo exactly once; '
                    're-read it before protecting the developer photo.';
  end if;

  v_new := replace(v_src, v_pattern,
    $p$where c.key in ('about_photo_media_id', 'developer_photo_media_id')$p$);

  -- The signature and settings are the original's, spelled out — including
  -- `search_path = ''`, which the body depends on by qualifying everything. `create or
  -- replace` keeps the existing revoke from `public, anon, authenticated`.
  execute format(
    'create or replace function public.sweep_orphan_media() returns integer '
    'language plpgsql security definer set search_path = '''' as %L',
    v_new);
end;
$migrate$;
