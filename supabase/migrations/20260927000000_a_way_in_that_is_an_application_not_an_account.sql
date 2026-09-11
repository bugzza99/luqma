-- A way in for couriers, restaurants and home kitchens — and it is an application.
--
-- The owner asked for a page in MerchantApp: one question, «مندوب ولا مطعم ولا أكل
-- بيتي؟», and they review what arrives. That is the right workflow and the wrong place to
-- write it. **`staff` is what every policy in this database reads to decide who you are**,
-- so a page writing it directly would hand that boundary an anonymous writer and give
-- anybody who installs the APK a row in it.
--
-- So this table. A row here **has no privileges of any kind** — nothing joins to it,
-- nothing reads it to decide access, and it grants nothing. The owner reads it in
-- AdminApp, telephones, and approves; approval is what calls `create-staff-account`, which
-- remains the only thing that may mint a `staff` row.
--
-- The applicant is not signed in — they have no account, that is the point — so `anon` may
-- insert and may do nothing else. What limits that: one open application per number, hard
-- length caps on every field, and no read of any kind. A stranger with the APK can leave
-- their name and number once and learn nothing.
create table staff_applications (
  id           uuid primary key default gen_random_uuid(),
  kind         text not null check (kind in ('courier', 'restaurant', 'homeKitchen')),
  name         text not null check (char_length(btrim(name)) between 2 and 80),
  phone        text not null check (char_length(phone) between 6 and 20),
  -- Whatever they typed about themselves: the shop's address, the areas they cover, the
  -- hours they work. It is read by a person on a telephone call, not parsed.
  note         text check (note is null or char_length(note) <= 500),
  status       text not null default 'pending'
                 check (status in ('pending', 'approved', 'rejected')),
  created_at   timestamptz not null default now(),
  reviewed_at  timestamptz,
  reviewed_by  uuid references auth.users on delete set null,
  review_note  text check (review_note is null or char_length(review_note) <= 500),
  -- Set on approval so a row can be traced to what it became. Null for everything else.
  staff_uid    uuid references public.staff (uid) on delete set null
);

comment on table staff_applications is
  'Somebody asking to join. Carries no privileges and is joined to by nothing — the '
  'owner reads it, telephones, and approves, and approval mints the account elsewhere.';

-- One open application per number. Not a rate limit and not pretending to be one: it stops
-- the same person filling the queue by tapping twice, and leaves a rejected or approved
-- number free to apply again later.
create unique index staff_applications_one_open
  on staff_applications (public.normalise_phone(phone)) where status = 'pending';

create index staff_applications_pending_idx
  on staff_applications (created_at desc) where status = 'pending';

alter table staff_applications enable row level security;
alter table staff_applications force row level security;

-- Insert, and nothing else. There is no select policy for `anon` on purpose: an applicant
-- cannot read the queue, cannot check whether a number is already in it, and cannot see
-- what an admin wrote about them.
grant insert on staff_applications to anon, authenticated;
create policy anybody_may_apply on staff_applications
  for insert to anon, authenticated
  with check (
    status = 'pending'
    and reviewed_at is null
    and reviewed_by is null
    and review_note is null
    and staff_uid is null
  );

-- The queue is the admin's, and only theirs. A merchant owner has no business reading
-- other people's applications, and the applicant has no business reading their own.
grant select, update on staff_applications to authenticated;
create policy admin_reads_applications on staff_applications
  for select to authenticated using (public.is_admin());

-- `using` and `with check` both, because without the first an admin could be given a row
-- they may not see and without the second the decision columns could be written by an
-- update that passed the read. Everything about who may act is one predicate.
create policy admin_reviews_applications on staff_applications
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- The reviewer is `auth.uid()` and never a parameter. Same rule as
-- `record_commission_payment`: a log that can be lied to is not evidence.
create or replace function public.review_staff_application(
  p_id     uuid,
  p_status text,
  p_note   text default null,
  p_staff_uid uuid default null
)
returns public.staff_applications
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_row public.staff_applications;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'only an admin reviews an application' using errcode = '42501';
  end if;
  if p_status not in ('approved', 'rejected') then
    raise exception 'an application is approved or rejected' using errcode = '22023';
  end if;

  update public.staff_applications
     set status      = p_status,
         reviewed_at = now(),
         reviewed_by = auth.uid(),
         review_note = nullif(btrim(p_note), ''),
         staff_uid   = case when p_status = 'approved' then p_staff_uid else null end
   where id = p_id
     and status = 'pending'
  returning * into v_row;

  if not found then
    -- Either it is gone or somebody else has already decided it. Both are the same thing
    -- to the person looking at a stale queue, and neither is an error worth a stack trace.
    raise exception 'that application has already been decided' using errcode = 'P0002';
  end if;

  insert into public.audit_log (action, actor, detail)
  values ('reviewStaffApplication', auth.uid(),
          jsonb_build_object('application', p_id, 'status', p_status));

  return v_row;
end;
$fn$;

revoke execute on function
  public.review_staff_application(uuid, text, text, uuid) from public, anon;
grant execute on function
  public.review_staff_application(uuid, text, text, uuid) to authenticated, service_role;
