-- H-03: an admin removes a courier's papers through an audited function, with a reason.
--
-- And, urgently, the hole `20261024000000` opened in passing.
--
-- ------------------------------------------------------------------ the hole first
--
-- `refuse_moderator_delete` was installed on 25 tables in `public`, chosen by reading the
-- `for all` policies there. **`storage.objects` is in another schema and was not one of
-- them**, and two policies on it are gated on `public.is_admin()` — which since that
-- migration answers for a moderator too. So widening one predicate handed a moderator the
-- delete on every courier's national ID photograph and on every image in the product.
--
-- Nothing was exposed: production carries two platform accounts, both admins, and no
-- moderator has ever existed. That is luck rather than design, and it is the exact risk
-- the grant-then-except shape carries — **widening a predicate reaches every policy that
-- reads it, including the ones in a schema you did not enumerate.** Enumerate by asking
-- the catalogue, never by reading the migrations.
--
-- Both policies ask the narrow question now. A moderator moderates images through
-- `admin_review_media`, which is the door for that and is deliberately still wide:
-- rejecting an image hides it from the product, and is reversible.

drop policy if exists media_delete on storage.objects;
create policy media_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'media' and public.is_platform_admin());

-- ------------------------------------------------------------------ then H-03
--
-- An admin could delete a courier's identity documents straight from the client, and
-- nothing anywhere recorded that it happened. H-09 settled the rule this breaks: every
-- sensitive admin mutation goes through a function that writes the change and its
-- evidence together, and the direct path is taken away, "because a write that skips the
-- function skips the audit with it".
--
-- Identity documents are the strongest case for it in the product. They are the only
-- thing a courier hands over that they cannot get back, the only reason
-- `staff_documents` exists, and the one thing whose disappearance a courier would notice
-- only when asked for them again.
--
-- So the policy stops granting an admin any direct delete at all. What remains for a
-- client is what it always was: an owner clearing a failed upload of their own that is
-- not currently serving as a verified document.
drop policy if exists staff_docs_delete on storage.objects;
create policy staff_docs_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'staff-docs'
    and split_part(name, '/', 1) = (select auth.uid())::text
    and not exists (
      select 1
        from public.staff_documents d
       where d.uid = (select auth.uid())
         and name in (d.id_front_path, d.id_back_path, d.selfie_path)
    )
  );

-- The bytes and the row go together, or neither does — and the row is all three papers.
--
-- `staff_documents` holds three `not null` paths written as a set by
-- `set_my_staff_documents`: a row means "this person has handed in their papers", and
-- that is the question `courier_application_needs_papers` asks before an approval. There
-- is no state in the product for "two papers on file", so removing one is not something
-- to model — an admin judging a photograph unacceptable means **the papers are not
-- acceptable and must be handed in again**, which is precisely the state of having none.
--
-- So this removes the set. It is a smaller API than a per-document one, it keeps the
-- invariant the table was built on, and it needs no nullable column rippling through the
-- approval guard, the admin's queue and the papers sheet.
--
-- Deleting the objects while the row still names them leaves «شوف البطاقة» drawing a
-- broken image, which reads as a bug rather than as a decision somebody took. Deleting
-- the row while the bytes stay leaves a national ID in a bucket that nothing in the
-- product points at, for the sweep to find a month later — if it finds it at all.
create or replace function public.admin_delete_staff_documents(
  p_uid    uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor  uuid := (select auth.uid());
  v_reason text := nullif(pg_catalog.btrim(p_reason), '');
  v_docs   public.staff_documents;
  v_prior  text;
begin
  if v_actor is null or not public.is_platform_admin() then
    raise exception 'only an admin removes a courier''s papers' using errcode = '42501';
  end if;

  -- A reason is required rather than optional. The audit row exists to answer "why are
  -- this courier's papers gone", and a log that may be empty does not answer it — the
  -- same reason `record_commission_payment` takes its actor from `auth.uid()` rather than
  -- from a parameter: evidence that can be skipped is not evidence.
  if v_reason is null then
    raise exception 'say why the papers are being removed'
      using errcode = 'invalid_parameter_value';
  end if;

  select * into v_docs from public.staff_documents where uid = p_uid for update;
  if not found then
    raise exception 'that person has no papers on file' using errcode = 'P0002';
  end if;

  -- The door hosted Supabase leaves open for a definer function, which `20260828040000`
  -- found the hard way. Transaction-local, and put back: leaving it standing would let
  -- whatever the caller's transaction does next delete objects unasked. Same lesson as
  -- `app.server_mode` in `apply_order_settlement`.
  v_prior := coalesce(pg_catalog.current_setting('storage.allow_delete_query', true), '');
  perform pg_catalog.set_config('storage.allow_delete_query', 'true', true);

  delete from storage.objects
   where bucket_id = 'staff-docs'
     and name in (v_docs.id_front_path, v_docs.id_back_path, v_docs.selfie_path);

  perform pg_catalog.set_config('storage.allow_delete_query', v_prior, true);

  delete from public.staff_documents where uid = p_uid;

  insert into public.audit_log (action, actor, detail)
  values (
    'staffDocuments.deleted', v_actor,
    pg_catalog.jsonb_build_object(
      'uid', p_uid,
      -- The paths, not the bytes: enough to prove which objects went, and they name
      -- nothing about the person that the uid does not already.
      'paths', pg_catalog.jsonb_build_array(
        v_docs.id_front_path, v_docs.id_back_path, v_docs.selfie_path),
      'uploadedAt', v_docs.uploaded_at,
      'reason', v_reason
    )
  );
end;
$fn$;

revoke all on function public.admin_delete_staff_documents(uuid, text)
  from public, anon;
grant execute on function public.admin_delete_staff_documents(uuid, text)
  to authenticated, service_role;

comment on function public.admin_delete_staff_documents(uuid, text) is
  'The only way an admin removes a courier''s identity papers. Takes a reason, and writes '
  'the deletion and its evidence in one transaction. Removes the set, because a row means '
  'three papers on file and there is no state for two.';
