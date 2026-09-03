-- A dismissal is a boundary change, not a claim change.
--
-- The access-token hook already refuses to stamp claims for an inactive account, but a
-- token issued before the dismissal keeps the old claims until it expires. The staff
-- row is therefore the current truth for staff-shaped predicates; the token still says
-- which job was granted, while this lookup says whether that grant is alive now.

-- SECURITY DEFINER is necessary here because this helper is used by policies on staff
-- itself. Reading staff as the policy caller would recurse into the same policy. The
-- answer exposes only whether auth.uid() has an active row, and the primary key on
-- staff(uid) makes it one indexed lookup.
create or replace function public.is_active_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
      from public.staff s
     where s.uid = (select auth.uid())
       and s.is_active
  );
$fn$;

revoke execute on function public.is_active_staff() from public;
grant execute on function public.is_active_staff() to anon, authenticated, service_role;

create or replace function public.is_admin() returns boolean
language sql stable as $fn$
  select coalesce(public.claim('admin')::boolean, false)
     and public.is_active_staff();
$fn$;

-- Merchant membership is staff-shaped too. Tightening the shared predicate closes the
-- read paths as well as the owner-only writes, while customer branches continue to use
-- their own uid and never need a staff row.
create or replace function public.belongs_to_merchant(m uuid) returns boolean
language sql stable as $fn$
  select m is not null
     and public.claim('merchant_id')::uuid = m
     and public.is_active_staff();
$fn$;

create or replace function public.is_merchant_owner(m uuid) returns boolean
language sql stable as $fn$
  select m is not null
     and public.claim('merchant_id')::uuid = m
     and public.staff_role() = 'owner'
     and public.is_active_staff();
$fn$;

create or replace function public.is_courier_for(m uuid) returns boolean
language sql stable as $fn$
  select m is not null
     and public.claim('merchant_id')::uuid = m
     and public.staff_role() = 'courier'
     and public.is_active_staff();
$fn$;

create or replace function public.is_platform_courier() returns boolean
language sql stable as $fn$
  select public.staff_role() = 'courier'
     and public.staff_scope() = 'platform'
     and public.is_active_staff();
$fn$;

-- An assigned courier used to skip every role helper because courier_uid matched
-- auth.uid() directly. Keeping the whole delivery identity in one predicate prevents
-- that shortcut from preserving money-moving access after dismissal.
create or replace function public.is_courier_for_order(
  p_courier_uid uuid,
  p_merchant_id uuid,
  p_delivery_by text
)
returns boolean
language sql
stable
as $fn$
  select public.is_active_staff()
     and (
       p_courier_uid = (select auth.uid())
       or (
         p_courier_uid is null
         and (
           (public.claim('merchant_id')::uuid = p_merchant_id
            and public.staff_role() = 'courier')
           or (public.staff_role() = 'courier'
               and public.staff_scope() = 'platform'
               and p_delivery_by = 'platform')
         )
       )
     );
$fn$;

-- The transition guard is repeated because an UPDATE policy alone can become broader
-- later. The final transition moves money, so both layers must agree that the courier is
-- still employed at the instant the word delivered is written.
create or replace function public.enforce_order_transition()
returns trigger
language plpgsql
as $fn$
declare
  actor text;
begin
  if new.status = old.status then
    return new;
  end if;

  if coalesce(current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  if public.is_admin() then
    return new;
  end if;

  if old.status in ('delivered', 'cancelled') then
    raise exception 'order % is finished (%), and cannot be moved', old.id, old.status
      using errcode = 'check_violation';
  end if;

  actor := case
    when auth.uid() = old.customer_uid then 'customer'
    when public.is_merchant_owner(old.merchant_id) then 'merchant'
    when public.is_courier_for_order(
      old.courier_uid, old.merchant_id, old.delivery_by
    ) then 'courier'
    else 'nobody'
  end;

  if not (
    (actor = 'customer' and old.status = 'placed' and new.status = 'cancelled')
    or (actor = 'merchant' and (
         (old.status = 'placed' and new.status in ('accepted', 'cancelled'))
      or (old.status = 'accepted' and new.status in ('preparing', 'cancelled'))
      or (old.status = 'preparing' and new.status = 'outForDelivery')))
    or (actor = 'courier' and (
         (old.status = 'preparing' and new.status = 'outForDelivery')
      or (old.status = 'outForDelivery' and new.status in ('delivered', 'cancelled'))))
  ) then
    raise exception '% may not move an order from % to %', actor, old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$fn$;

create or replace function public.guard_order_columns()
returns trigger
language plpgsql
as $fn$
declare
  allowed text[];
  touched text[];
begin
  if coalesce(current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  if public.is_admin() then
    return new;
  end if;

  allowed := case
    when auth.uid() = old.customer_uid
      then array['status', 'status_history', 'cancel_reason', 'cancelled_by']
    when public.is_merchant_owner(old.merchant_id)
      then array['status', 'status_history', 'prep_minutes', 'cancel_reason', 'cancelled_by']
    when public.is_courier_for_order(
      old.courier_uid, old.merchant_id, old.delivery_by
    )
      then array['status', 'status_history', 'courier_uid', 'delivered_at',
                 'cancel_reason', 'cancelled_by']
    else array[]::text[]
  end || array['updated_at'];

  select coalesce(array_agg(k), '{}')
    into touched
    from jsonb_each(to_jsonb(new)) as changes(k, v)
   where v is distinct from (to_jsonb(old) -> changes.k);

  if not (touched <@ allowed) then
    raise exception 'column not yours to change on an order: %',
      array_to_string(array(select unnest(touched) except select unnest(allowed)), ', ')
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$fn$;

create or replace function public.append_order_status_history()
returns trigger
language plpgsql
as $fn$
declare
  v_by text;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  if coalesce(current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  v_by := case
    when public.is_admin() then 'admin'
    when auth.uid() = old.customer_uid then 'customer'
    when public.is_merchant_owner(old.merchant_id) then 'merchant'
    when public.is_courier_for_order(
      old.courier_uid, old.merchant_id, old.delivery_by
    ) then 'courier'
    else 'customer'
  end;

  new.status_history := coalesce(new.status_history, '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'from', old.status,
      'to', new.status,
      'by', v_by,
      'at', now()
    )
  );

  return new;
end;
$fn$;

drop policy read_orders on public.orders;
create policy read_orders on public.orders for select to authenticated
  using (public.is_admin()
         or customer_uid = auth.uid()
         or public.belongs_to_merchant(merchant_id)
         or public.is_courier_for_order(courier_uid, merchant_id, delivery_by));

drop policy courier_moves_orders on public.orders;
create policy courier_moves_orders on public.orders for update to authenticated
  using (public.is_courier_for_order(courier_uid, merchant_id, delivery_by))
  with check (public.is_courier_for_order(courier_uid, merchant_id, delivery_by));

-- The client cannot be allowed to update is_active directly any more: doing so would
-- skip GoTrue and leave refresh credentials alive. Only the service-role function below
-- declares server mode, so every product path goes through the revocation attempt.
create or replace function public.guard_staff_activation()
returns trigger
language plpgsql
as $fn$
begin
  if new.is_active is distinct from old.is_active
     and coalesce(current_setting('app.server_mode', true), '') <> 'on' then
    raise exception 'staff activation changes must use the server boundary'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$fn$;

create trigger staff_guard_activation
  before update of is_active on public.staff
  for each row execute function public.guard_staff_activation();

-- The Edge Function has already verified the caller with GoTrue, but the table is read
-- again inside this transaction so an admin dismissed between those two requests cannot
-- spend the service role. One transaction lock serialises administrator dismissals;
-- without it, two admins could each observe the other and disable both concurrently.
create or replace function public.set_staff_active(
  p_uid uuid,
  p_active boolean,
  p_actor uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_target public.staff;
  v_prior_mode text;
begin
  perform pg_advisory_xact_lock(20260905);

  if not exists (
    select 1
      from public.staff s
     where s.uid = p_actor
       and s.scope = 'platform'
       and s.role = 'admin'
       and s.is_active
  ) then
    raise exception 'only an active platform admin changes staff access'
      using errcode = 'insufficient_privilege';
  end if;

  select *
    into v_target
    from public.staff
   where uid = p_uid
   for update;

  if not found then
    raise exception 'no such staff account' using errcode = 'P0002';
  end if;

  if not p_active
     and v_target.is_active
     and v_target.scope = 'platform'
     and v_target.role = 'admin'
     and not exists (
       select 1
         from public.staff s
        where s.scope = 'platform'
          and s.role = 'admin'
          and s.is_active
          and s.uid <> p_uid
     ) then
    raise exception 'last active platform admin' using errcode = 'check_violation';
  end if;

  v_prior_mode := coalesce(current_setting('app.server_mode', true), '');
  perform set_config('app.server_mode', 'on', true);

  update public.staff
     set is_active = p_active,
         updated_at = now()
   where uid = p_uid;

  perform set_config('app.server_mode', v_prior_mode, true);

  insert into public.audit_log (action, actor, merchant_id, detail)
  values ('staff.active_changed', p_actor, v_target.merchant_id,
          jsonb_build_object(
            'uid', p_uid,
            'active', p_active,
            'previous', v_target.is_active
          ));
end;
$fn$;

revoke execute on function public.set_staff_active(uuid, boolean, uuid)
  from public, anon, authenticated;
grant execute on function public.set_staff_active(uuid, boolean, uuid)
  to service_role;
