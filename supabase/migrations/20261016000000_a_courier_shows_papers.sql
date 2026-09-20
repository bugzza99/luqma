-- A courier shows their papers, and the papers belong to the person.
--
-- A platform courier carries other people's food and collects other people's cash, so
-- the owner checks who they are before approving them: national ID front, ID back, and
-- a selfie holding the ID. This migration is the documents and nothing else. The
-- per-delivery commission that travelled with this work in an earlier attempt is not
-- here and is not implied: a platform courier works at zero commission until that half
-- is designed on its own.
--
-- The earlier attempt (parked on `park/courier-papers-and-commission`) hung the three
-- paths off `staff_applications` and swept any object no application row pointed at.
-- Two things follow from that, and both are why this is a rewrite rather than a fix:
--
--   * An approved courier's ID photographs were kept alive by their *application* row.
--     Nothing in the product protects that row, and the sweep gave anything unreferenced
--     one day. So the most sensitive data here was one deleted row away from vanishing —
--     and, for as long as the row lived, kept for ever with no stated purpose after the
--     admin had looked at it.
--   * A document's life was asked about in one place and answered in another. That is
--     the same shape as the commission fault that parked the whole feature, and fixing
--     it in one half and not the other would have been fixing nothing.
--
-- So the documents hang off **the person** — `auth.users`, which the applicant already
-- owns before they apply and keeps when approval turns them into staff. One row per
-- person, and one function decides how long it lives. The owner's rule (2026-09-20):
-- keep the papers while they are working, and purge them a set time after they stop.

-- ------------------------------------------------------------------ the bucket

-- Private, unlike `media`. A menu photograph is public by design and what keeps an
-- unapproved one out of the product is its `media` row; a national ID is not something
-- a uuid in the path is allowed to be the only guard on.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('staff-docs', 'staff-docs', false, 3145728,
        array['image/jpeg', 'image/png'])
on conflict (id) do update
  set public             = false,
      file_size_limit    = 3145728,
      allowed_mime_types = array['image/jpeg', 'image/png'];

-- ------------------------------------------------------------------ the papers

create table if not exists public.staff_documents (
  -- The person, not the application and not the staff row. An applicant owns this uid
  -- before they apply (they make an ordinary phone account to do it) and keeps it when
  -- approval mints their `staff` row, so nothing has to be copied from one life to the
  -- next and there is never a moment where the papers belong to nobody.
  uid           uuid primary key references auth.users on delete cascade,
  id_front_path text not null,
  id_back_path  text not null,
  selfie_path   text not null,
  uploaded_at   timestamptz not null default now(),
  -- Null means keep. An instant means the papers are counting down to deletion, and
  -- `refresh_staff_documents_retention` is the only thing that writes it.
  purge_after   timestamptz
);

comment on table public.staff_documents is
  'Identity papers for somebody who applied to carry food and cash. Keyed on the person '
  'so they outlive the application and stop when the work does.';

comment on column public.staff_documents.purge_after is
  'Null while the person is working or waiting on a decision. Otherwise the instant '
  'after which the sweep deletes the objects and this row. Written by one function.';

create index if not exists staff_documents_purge_idx
  on public.staff_documents (purge_after) where purge_after is not null;

alter table public.staff_documents enable row level security;
alter table public.staff_documents force row level security;
revoke all on public.staff_documents from public, anon, authenticated;
grant select on public.staff_documents to authenticated;

-- The owner of the papers may see that they are there, and an admin may review them.
-- The earlier attempt let only an admin read, which left an applicant unable to tell
-- whether their upload had landed at all — on the one screen where a silent failure
-- costs them the job.
drop policy if exists read_own_or_admin_staff_documents on public.staff_documents;
create policy read_own_or_admin_staff_documents on public.staff_documents
  for select to authenticated
  using (uid = (select auth.uid()) or public.is_admin());

-- ------------------------------------------------------------------ the objects

-- Everything a person uploads lives under their own uid, and the policy is what makes
-- the path mean something rather than merely look organised.
drop policy if exists staff_docs_upload on storage.objects;
create policy staff_docs_upload on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'staff-docs'
    and split_part(name, '/', 1) = (select auth.uid())::text
  );

drop policy if exists staff_docs_read on storage.objects;
create policy staff_docs_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'staff-docs'
    and (split_part(name, '/', 1) = (select auth.uid())::text
         or public.is_admin())
  );

-- A person may replace a bad photograph of their own; an admin may remove any. The
-- nightly sweep does not come through here — it runs as a definer function that names
-- `storage.allow_delete_query`, which is the path hosted Supabase leaves open for
-- exactly this and which `20260828040000` discovered the hard way.
drop policy if exists staff_docs_delete on storage.objects;
create policy staff_docs_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'staff-docs'
    and (split_part(name, '/', 1) = (select auth.uid())::text
         or public.is_admin())
  );

-- ------------------------------------------------------------------ how long is a set time

insert into public.config (key, value) values ('staff_docs_grace_days', '30'::jsonb)
on conflict (key) do nothing;

create or replace function public.staff_docs_grace_days()
returns integer
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(
    (select (value #>> '{}')::integer from public.config where key = 'staff_docs_grace_days'),
    30);
$fn$;

revoke all on function public.staff_docs_grace_days() from public, anon;
grant execute on function public.staff_docs_grace_days() to authenticated, service_role;

-- Guarded on the table rather than inside `admin_set_config`, so a direct write and an
-- older AdminApp meet the same range. Same shape as `config_keeps_commission_sane`.
create or replace function public.config_keeps_staff_docs_sane()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_number numeric;
begin
  if new.key <> 'staff_docs_grace_days' then
    return new;
  end if;
  begin
    v_number := (new.value #>> '{}')::numeric;
  exception when others then
    raise exception '% must be a number', new.key using errcode = 'check_violation';
  end;
  -- Zero is excluded deliberately: it would delete a dismissed courier's papers before
  -- anybody could look at them again, and a dispute about cash outlives the dismissal.
  if v_number is null or v_number < 1 or v_number > 365
     or v_number <> pg_catalog.floor(v_number) then
    raise exception '% is out of range', new.key using errcode = 'check_violation';
  end if;
  return new;
end;
$fn$;

drop trigger if exists config_keeps_staff_docs_sane on public.config;
create trigger config_keeps_staff_docs_sane
  before insert or update of value on public.config
  for each row execute function public.config_keeps_staff_docs_sane();

-- ------------------------------------------------------------------ one writer of purge_after

-- The whole point of this migration, in one function.
--
-- Papers are kept while the person is *working* or *waiting to hear*, and purged a grace
-- period after neither is true. Every caller below asks this question the same way, so
-- there is no second authority to disagree with the first — which is the fault that
-- parked the earlier attempt.
--
-- The clock is never restarted on a row already counting down: a dismissed courier whose
-- staff row is touched again next week must not get another thirty days.
create or replace function public.refresh_staff_documents_retention(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if p_uid is null then
    return;
  end if;

  update public.staff_documents d
     set purge_after = case
           when exists (select 1 from public.staff s
                         where s.uid = p_uid and s.is_active)
             or exists (select 1 from public.staff_applications a
                         where a.applicant_uid = p_uid and a.status = 'pending')
           then null
           else coalesce(
             d.purge_after,
             pg_catalog.now() + pg_catalog.make_interval(days => public.staff_docs_grace_days()))
         end
   where d.uid = p_uid;
end;
$fn$;

revoke all on function public.refresh_staff_documents_retention(uuid)
  from public, anon, authenticated;
grant execute on function public.refresh_staff_documents_retention(uuid) to service_role;

-- Becoming staff, being dismissed, being reinstated, and being removed altogether are
-- four different statements and one question. The trigger asks it for all of them.
create or replace function public.staff_touches_documents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_staff_documents_retention(old.uid);
    return old;
  end if;
  perform public.refresh_staff_documents_retention(new.uid);
  if tg_op = 'UPDATE' and new.uid is distinct from old.uid then
    perform public.refresh_staff_documents_retention(old.uid);
  end if;
  return new;
end;
$fn$;

drop trigger if exists staff_touches_documents on public.staff;
create trigger staff_touches_documents
  after insert or update or delete on public.staff
  for each row execute function public.staff_touches_documents();

-- An application being decided changes the answer too, and does it without touching
-- `staff` at all when the decision is a rejection.
create or replace function public.application_touches_documents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_staff_documents_retention(old.applicant_uid);
    return old;
  end if;
  perform public.refresh_staff_documents_retention(new.applicant_uid);
  return new;
end;
$fn$;

drop trigger if exists application_touches_documents on public.staff_applications;
create trigger application_touches_documents
  after insert or update or delete on public.staff_applications
  for each row execute function public.application_touches_documents();

-- ------------------------------------------------------------------ handing the papers in

-- Three photographs or none. A set with a missing selfie is not a weaker set, it is an
-- application the owner cannot act on, and storing it would put a half-review in the
-- queue that looks like a whole one.
create or replace function public.set_my_staff_documents(
  p_id_front text,
  p_id_back  text,
  p_selfie   text
)
returns public.staff_documents
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid   uuid := (select auth.uid());
  v_row   public.staff_documents;
  v_paths text[];
  v_path  text;
begin
  if v_uid is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  v_paths := array[
    pg_catalog.btrim(p_id_front),
    pg_catalog.btrim(p_id_back),
    pg_catalog.btrim(p_selfie)
  ];

  foreach v_path in array v_paths loop
    if v_path is null or v_path = '' then
      raise exception 'all three documents are required' using errcode = '22023';
    end if;
    -- The path is checked against the caller rather than trusted, because the caller is
    -- what wrote it. Without this a courier could name somebody else's object and have
    -- the admin review a stranger's papers as theirs.
    if split_part(v_path, '/', 1) <> v_uid::text then
      raise exception 'those documents are not yours' using errcode = '42501';
    end if;
    if not exists (select 1 from storage.objects o
                    where o.bucket_id = 'staff-docs' and o.name = v_path) then
      raise exception 'that document was not uploaded' using errcode = 'P0002';
    end if;
  end loop;

  insert into public.staff_documents (uid, id_front_path, id_back_path, selfie_path, uploaded_at)
  values (v_uid, v_paths[1], v_paths[2], v_paths[3], pg_catalog.now())
      on conflict (uid) do update
         set id_front_path = excluded.id_front_path,
             id_back_path  = excluded.id_back_path,
             selfie_path   = excluded.selfie_path,
             uploaded_at   = excluded.uploaded_at;

  -- A fresh set on a person who had stopped counts as being back in the queue, and the
  -- one function decides whether that is true rather than this one assuming it.
  perform public.refresh_staff_documents_retention(v_uid);

  select * into v_row from public.staff_documents where uid = v_uid;
  return v_row;
end;
$fn$;

revoke all on function public.set_my_staff_documents(text, text, text) from public, anon;
grant execute on function public.set_my_staff_documents(text, text, text)
  to authenticated, service_role;

-- ------------------------------------------------------------------ no papers, no approval

-- Enforced on the table rather than inside `approve_staff_application`, so that an admin
-- handset carrying an older APK, a direct write and the function itself all meet the
-- same rule. `20261005000000` learned this the other way round: a guard that lives in
-- one function is a guard an old client walks past.
create or replace function public.courier_application_needs_papers()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if new.kind <> 'courier' or new.status <> 'approved' then
    return new;
  end if;
  -- Re-approving something already approved is not a fresh decision, and must not fail
  -- once the papers have been purged by the retention rule years later.
  if tg_op = 'UPDATE' and old.status = 'approved' then
    return new;
  end if;
  if new.applicant_uid is null
     or not exists (select 1 from public.staff_documents d where d.uid = new.applicant_uid) then
    raise exception 'a courier is approved on their papers, and there are none'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$fn$;

drop trigger if exists courier_application_needs_papers on public.staff_applications;
create trigger courier_application_needs_papers
  before insert or update on public.staff_applications
  for each row execute function public.courier_application_needs_papers();

-- ------------------------------------------------------------------ the sweep

-- Recompute first, then delete. The triggers above make retention prompt; recomputing
-- here makes it *true* — a row whose purge_after was written before somebody was
-- reinstated by a path nobody thought of is corrected rather than acted on. It costs a
-- pass over a table with one row per courier.
create or replace function public.sweep_staff_documents()
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_removed integer := 0;
  v_uid     uuid;
begin
  for v_uid in select uid from public.staff_documents loop
    perform public.refresh_staff_documents_retention(v_uid);
  end loop;

  -- Hosted Supabase refuses a direct delete from the storage tables unless a caller
  -- names itself this way. Transaction-local, and visible to nothing else.
  perform pg_catalog.set_config('storage.allow_delete_query', 'true', true);

  with due as (
    select uid, id_front_path, id_back_path, selfie_path
      from public.staff_documents
     where purge_after is not null
       and purge_after <= pg_catalog.now()
  ), paths as (
    select d.uid, p as object_name
      from due d, unnest(array[d.id_front_path, d.id_back_path, d.selfie_path]) as p
  ), gone as (
    delete from storage.objects o using paths
     where o.bucket_id = 'staff-docs'
       and o.name = paths.object_name
    returning 1
  )
  delete from public.staff_documents d using due where d.uid = due.uid;

  get diagnostics v_removed = row_count;
  return v_removed;
end;
$fn$;

revoke all on function public.sweep_staff_documents() from public, anon, authenticated;
grant execute on function public.sweep_staff_documents() to service_role;

-- ------------------------------------------------------------------ scheduling

-- Guarded on availability, because PGlite runs the local suite and has no pg_cron; a
-- bare `create extension` there stops every local test before it reaches a constraint.
do $body$
declare
  v_cron boolean;
begin
  select count(*) > 0 into v_cron
    from pg_available_extensions
   where name = 'pg_cron';

  if v_cron then
    create extension if not exists pg_cron;

    perform cron.unschedule('luqma-sweep-staff-docs')
      where exists (select 1 from cron.job where jobname = 'luqma-sweep-staff-docs');
    -- Retention is measured in days, so once a night is as prompt as the rule is.
    perform cron.schedule('luqma-sweep-staff-docs', '20 3 * * *',
      'select public.sweep_staff_documents()');
  end if;
end;
$body$;
