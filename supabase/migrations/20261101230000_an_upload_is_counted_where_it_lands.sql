-- An upload is counted where it lands: in the bucket, not only in the table beside it (A8).
--
-- M-03 capped uploads at `media_uploads_per_hour()` by counting `public.media` rows. But
-- the bytes go to `storage.objects` first, and `media_upload` asked only that the path
-- start with the caller's uid — so a script with any account (sign-up is open) could put
-- thousands of 2 MB files into the public `media` bucket without ever writing a row. They
-- were served from Luqma's own address until the orphan sweep a week later, and they
-- filled the free tier's storage, after which the owner's own menu photographs failed.
-- `staff-docs` took unlimited uploads the same way.
--
-- The insert policies now also ask how many objects this person put in the bucket in the
-- last hour. The same number as the rows for `media` — one picture is one object and one
-- row — and twelve for papers, which are three photographs and a few retakes. Counted by
-- the path prefix the policy already requires, which the (bucket_id, name) index serves.

create or replace function public.storage_upload_within_rate(p_bucket text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select count(*) < case p_bucket
                      when 'media' then public.media_uploads_per_hour()
                      else 12
                    end
    from storage.objects o
   where o.bucket_id = p_bucket
     and o.name like (auth.uid())::text || '/%'
     and o.created_at > now() - interval '1 hour';
$fn$;

revoke all on function public.storage_upload_within_rate(text) from public, anon;
grant execute on function public.storage_upload_within_rate(text) to authenticated;

drop policy if exists media_upload on storage.objects;
create policy media_upload on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'media'
    and split_part(name, '/', 1) = (auth.uid())::text
    and public.storage_upload_within_rate('media')
  );

drop policy if exists staff_docs_upload on storage.objects;
create policy staff_docs_upload on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'staff-docs'
    and split_part(name, '/', 1) = ((select auth.uid()))::text
    and public.storage_upload_within_rate('staff-docs')
  );
