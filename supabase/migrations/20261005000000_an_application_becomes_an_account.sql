-- An application becomes an account, and somebody is told it arrived.
--
-- The first real merchant applied on 2026-09-17 and four things went wrong, all of them
-- this file's subject:
--
--   1. Nothing asked the applicant for a password, so there was no account to sign into.
--   2. No admin was told an application had arrived.
--   3. Approving it only stamped `approved`: no staff row, no shop. The application left
--      the queue and the merchant did not exist anywhere — searching their number found
--      nothing, which is exactly what the owner saw.
--   4. The partner app then asked that merchant for an email and a password they had
--      never had.
--
-- The shape that fixes it keeps the rule the application queue exists for: **an account
-- with no `staff` row has no privileges at all**. So the applicant may now create the
-- ordinary phone account themselves — the same thing a customer creates — and the
-- application carries its id. Approval is still the admin's, and approval is what mints
-- the `staff` row and the shop.

alter table public.staff_applications
  add column if not exists applicant_uid uuid references auth.users on delete set null;

comment on column public.staff_applications.applicant_uid is
  'The phone account the applicant made when they applied. Carries nothing by itself: '
  'privileges live in `staff`, and only approval writes that.';

-- Insert is granted column by column since 20260929000000, so the new column needs its own
-- grant — and only to `authenticated`: naming an account means having signed into one.
grant insert(applicant_uid) on public.staff_applications to authenticated;

-- **An application is signed now.** `anon` loses the insert entirely, and the account named
-- has to be the one holding the token. Two reasons, and the first is not tidiness:
--
--   * An anonymous application is one anybody can write as often as they can post, and each
--     one wakes every platform admin on the critical channel. Signed, each one costs a
--     GoTrue sign-up on a number nobody else has taken.
--   * An application with no account is the incident: it reaches the queue, leaves it
--     `approved`, and creates nothing. Refusing it at the door is better than refusing it
--     at the approval, which is where the owner finds out.
--
-- An APK from before this asked for a password will be refused — deliberately. It is the
-- build that produces the accountless row.
revoke insert on public.staff_applications from anon;

drop policy if exists anybody_may_apply on public.staff_applications;
create policy anybody_may_apply on public.staff_applications
  for insert to authenticated
  with check (
    status = 'pending'
    and reviewed_at is null
    and reviewed_by is null
    and review_note is null
    and staff_uid is null
    and applicant_uid = auth.uid()
  );

-- ------------------------------------------------ The number applied for is the number held
--
-- The policy above proves the row names *your* account. It cannot prove the account is the
-- one whose telephone is written on the row — and that gap is a shop worth stealing: fill in
-- a real restaurant's name and number against your own uid, let the owner ring the
-- restaurant and agree terms with them, and approval hands the shop to you.
--
-- So the two must be the same number. A customer's account address is their number folded
-- into the reserved domain (`Phone.toAccountEmail`), which is what makes this answerable
-- here at all.
create or replace function public.application_phone_is_the_applicant_s()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
begin
  if new.applicant_uid is null then
    return new;
  end if;

  select email into v_email from auth.users where id = new.applicant_uid;

  if v_email is distinct from
     public.normalise_phone(new.phone) || '@phone.luqma.app' then
    raise exception 'apply with the number your account is on' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists staff_applications_phone_is_the_account
  on public.staff_applications;
create trigger staff_applications_phone_is_the_account
  before insert on public.staff_applications
  for each row execute function public.application_phone_is_the_applicant_s();

-- ---------------------------------------------------------------- Somebody is told

create or replace function public.notify_admins_of_application()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin record;
  v_kind  text;
begin
  v_kind := case new.kind
              when 'courier' then 'مندوب'
              when 'homeKitchen' then 'مطبخ بيتي'
              else 'مطعم'
            end;

  for v_admin in
    select uid from public.staff
     where scope = 'platform' and role = 'admin' and is_active
  loop
    insert into public.push_outbox (uid, title, body, data, channel)
    values (
      v_admin.uid,
      'طلب انضمام جديد',
      new.name || ' — ' || v_kind || ' — ' || new.phone,
      pg_catalog.jsonb_build_object('kind', 'staffApplication', 'applicationId', new.id::text),
      -- The same channel the unanswered-order alert uses: this is somebody waiting for a
      -- telephone call, and a notification that waits until the app is opened is one the
      -- owner reads a day late.
      'orders_critical'
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists staff_applications_notify_admins on public.staff_applications;
create trigger staff_applications_notify_admins
  after insert on public.staff_applications
  for each row execute function public.notify_admins_of_application();

-- ---------------------------------------------------------------- Approval mints it

-- Approving an application creates the account it asked for: the staff row, and for a
-- restaurant or a home kitchen the shop as well, owned by the applicant and waiting for the
-- details only the owner knows (hours, delivery, menu).
create or replace function public.approve_staff_application(
  p_id          uuid,
  p_zone_id     uuid default null,
  p_merchant_id uuid default null,
  p_note        text default null
)
returns public.staff_applications
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_app         public.staff_applications;
  v_city        text;
  v_merchant_id uuid := p_merchant_id;
  v_prior_mode  text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'only an admin approves an application' using errcode = '42501';
  end if;

  -- Locked: two admins approving the same row would otherwise both mint an account.
  select * into v_app
    from public.staff_applications
   where id = p_id
     for update;

  if not found or v_app.status <> 'pending' then
    raise exception 'that application has already been decided' using errcode = 'P0002';
  end if;

  if v_app.applicant_uid is null then
    raise exception 'the applicant has no account yet' using errcode = 'P0001';
  end if;

  if exists (select 1 from public.staff where uid = v_app.applicant_uid) then
    raise exception 'that person already has a staff account' using errcode = '23505';
  end if;

  -- Asked again here, not only at the door. The rows already in the table were written
  -- before the trigger existed, and this is the moment the answer turns into a shop.
  if not exists (
    select 1 from auth.users
     where id = v_app.applicant_uid
       and email = public.normalise_phone(v_app.phone) || '@phone.luqma.app'
  ) then
    raise exception 'that account is not on the number applied for' using errcode = '42501';
  end if;

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  if v_app.kind = 'courier' then
    -- A courier's account is bound to one shop by the schema (`staff_scope_matches_merchant`),
    -- and carries for others through `courier_merchants`. So approval needs the shop they
    -- start with; the admin picks it and can attach more afterwards.
    if v_merchant_id is null then
      raise exception 'a courier needs a shop to start with' using errcode = '22023';
    end if;

    insert into public.staff (uid, scope, role, merchant_id, name, phone, is_active)
    values (v_app.applicant_uid, 'merchant', 'courier', v_merchant_id, v_app.name,
            v_app.phone, true);

    -- `attached_by` is written here rather than left to the trigger: server mode is on for
    -- the staff insert above, and a function in server mode keeps whatever it wrote — which
    -- would be nothing. "Who put this rider on this shop" is a question asked after money
    -- has gone missing, and the answer is the admin who approved.
    insert into public.courier_merchants
      (courier_uid, merchant_id, is_active, attached_by, attached_at)
    values (v_app.applicant_uid, v_merchant_id, true, auth.uid(), now())
    on conflict (courier_uid, merchant_id) where merchant_id is not null
      do update set is_active = true, attached_by = auth.uid(), attached_at = now();
  else
    -- A shop of their own. The zone decides the city, because a zone belongs to one.
    if p_zone_id is null then
      raise exception 'a shop needs a zone' using errcode = '22023';
    end if;

    select city_id into v_city from public.zones where id = p_zone_id;
    if v_city is null then
      raise exception 'no such zone' using errcode = '22023';
    end if;

    insert into public.merchants (
      city_id, type, name, zone_id, phone, status, owner_uid,
      -- Zero commission until the owner sets terms or the shop takes a plan: the first
      -- shops in the city join at nothing, and a rate nobody agreed is worse than none.
      revenue_model, revenue_value
    )
    values (
      v_city, v_app.kind, v_app.name, p_zone_id, v_app.phone, 'pending', v_app.applicant_uid,
      'commission', 0
    )
    returning id into v_merchant_id;

    insert into public.staff (uid, scope, role, merchant_id, name, phone, is_active)
    values (v_app.applicant_uid, 'merchant', 'owner', v_merchant_id, v_app.name,
            v_app.phone, true);
  end if;

  update public.staff_applications
     set status      = 'approved',
         reviewed_at = now(),
         reviewed_by = auth.uid(),
         review_note = nullif(btrim(p_note), ''),
         staff_uid   = v_app.applicant_uid
   where id = p_id
  returning * into v_app;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values ('approveStaffApplication', auth.uid(), v_merchant_id,
          pg_catalog.jsonb_build_object('application', p_id, 'kind', v_app.kind));

  -- Their app is already installed and signed in: say it worked.
  insert into public.push_outbox (uid, title, body, data, channel)
  values (
    v_app.applicant_uid,
    'حسابك اتفعّل',
    case when v_app.kind = 'courier'
         then 'افتح لقمة شريك، هتلاقي شاشة التوصيل.'
         else 'افتح لقمة شريك، محلك جاهز — كمّل بياناته والمنيو.'
    end,
    pg_catalog.jsonb_build_object('kind', 'staffApproved'),
    'orders_critical'
  );

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);

  return v_app;
end;
$fn$;

revoke all on function public.approve_staff_application(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.approve_staff_application(uuid, uuid, uuid, text)
  to authenticated, service_role;

-- ---------------------------------------------- The old way of approving is closed

-- `review_staff_application` is what stamped `approved` and created nothing, and it is
-- still installed on every admin handset carrying an older APK. Leaving it callable leaves
-- the incident reproducible by somebody who simply has not updated: they approve, the row
-- leaves the queue, no account is made — and the new function then refuses it, because it
-- is no longer pending.
--
-- It keeps rejecting. A rejection is a decision with no account behind it, which is exactly
-- what this function was always able to do correctly.
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
  if p_status = 'approved' then
    raise exception 'approval makes the account now — update the admin app'
      using errcode = '0A000';
  end if;
  if p_status <> 'rejected' then
    raise exception 'an application is approved or rejected' using errcode = '22023';
  end if;

  update public.staff_applications
     set status      = p_status,
         reviewed_at = now(),
         reviewed_by = auth.uid(),
         review_note = nullif(btrim(p_note), ''),
         staff_uid   = null
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
