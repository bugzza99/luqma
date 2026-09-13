-- Platform coverage must be revoked by the same join that grants it. The original
-- migration already backfilled legacy platform couriers; a JWT is not a second grant.
create or replace function public.is_platform_courier() returns boolean
language sql stable as $fn$
  select public.courier_carries(null);
$fn$;

-- Attachment is granted by the phone-checking RPC, never an arbitrary client uid.
drop policy owner_manages_own_roster on public.courier_merchants;
create policy admin_manages_rosters on public.courier_merchants for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy owner_detaches_courier on public.courier_merchants for update to authenticated
  using (public.is_merchant_owner(merchant_id))
  with check (public.is_merchant_owner(merchant_id) and not is_active);

-- An owner can turn an attachment off, not retarget its identity or forge its author.
-- The SECURITY DEFINER attachment RPC runs as its owner and may reactivate the row.
create function public.guard_roster_detach() returns trigger
language plpgsql set search_path = '' as $fn$
begin
  if current_user = 'authenticated' and not public.is_admin()
     and (to_jsonb(new) - 'is_active') is distinct from (to_jsonb(old) - 'is_active') then
    raise exception 'a shop may only deactivate an existing attachment' using errcode='42501';
  end if;
  return new;
end;
$fn$;
create trigger courier_merchants_guard_detach before update on public.courier_merchants
  for each row execute function public.guard_roster_detach();

drop policy read_staff on public.staff;
create policy read_staff on public.staff for select to authenticated
  using (public.is_admin() or uid = (select auth.uid())
    or (role <> 'courier' and public.is_merchant_owner(merchant_id))
    or (role = 'courier' and public.owner_of_rosters_courier(uid)));

-- Accounts minted after the original backfill also need a real initial grant.
-- This is insert-only: later edits must never resurrect a detached relationship.
create function public.attach_initial_courier_scope() returns trigger
language plpgsql security definer set search_path = '' as $fn$
begin
  insert into public.courier_merchants(courier_uid,merchant_id)
  values (new.uid,new.merchant_id) on conflict do nothing;
  return new;
end;
$fn$;
revoke all on function public.attach_initial_courier_scope() from public, anon, authenticated;
create trigger staff_attach_initial_courier after insert on public.staff
  for each row when (new.role = 'courier')
  execute function public.attach_initial_courier_scope();

select public.add_table_to_realtime('courier_merchants');
select public.add_table_to_realtime('staff_applications');

-- Decisions and their actor/audit row are one operation, owned by the definer RPC.
drop policy admin_reviews_applications on public.staff_applications;
revoke update on public.staff_applications from authenticated, anon;
revoke insert on public.staff_applications from authenticated, anon;
grant insert(kind,name,phone,note) on public.staff_applications to authenticated, anon;

-- The address migration accidentally dropped this existing owner-editable column.
drop trigger merchants_guard_columns on public.merchants;
create trigger merchants_guard_columns before update on public.merchants for each row
  execute function public.guard_columns(
    '{name,phone,description,logo_media_id,cover_media_id,opening_hours,paused_until,min_order,delivery_fee_override,prep_minutes,landmark_id,landmark_name,street,lat,lng}');
