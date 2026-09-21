-- H-08: `moderator` becomes a role somebody can actually hold.
--
-- The role has existed in the schema, in `StaffRole`, and as a choice on the admin's own
-- staff form since Phase 2 — and the access gate has only ever asked `is_admin()`, which
-- a moderator does not satisfy. So creating one produced an account that could not sign
-- into anything, and nothing said so: the form offered it, the row was written, and the
-- person was handed credentials that open nothing.
--
-- The owner's decision (2026-09-21): a moderator is **an admin except money and
-- deletion**. That sentence is implemented the way it is written — by granting, then
-- excepting — rather than by widening the 47 policies and 44 functions that ask
-- `is_admin()` one at a time. Widening by hand is 91 judgements, and the ones that get
-- missed fail silently in the direction of "this screen is empty for no reason".
--
-- Two exceptions the sentence does not name, and which the owner plainly does not mean:
--
--   * **`staff` and `courier_merchants`.** `staff` carries a `for all` policy, so a
--     moderator holding an admin's reach could edit staff rows — including their own, to
--     `role = 'admin'`. A permission that can grant itself is not a permission.
--   * **`config`.** It holds `default_commission_percent`, which is money by another
--     name, and `min_supported_version`, which walls every customer out of the product
--     with no back door. Neither belongs to somebody who may not record a payment.

-- ------------------------------------------------------------------ who is strictly an admin

-- `is_admin()` keeps its meaning for the whole read-and-moderate surface and now answers
-- true for a moderator too. This is the narrower question, and it is what every money,
-- privilege and control-plane door asks from here.
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  -- Read from the row, not from the claim. A moderator promoted to admin an hour ago
  -- carries a token that still says moderator, and the reverse matters more: an admin
  -- demoted to moderator must lose the till now rather than when their JWT expires.
  select exists (
    select 1 from public.staff s
     where s.uid = (select auth.uid())
       and s.scope = 'platform'
       and s.role = 'admin'
       and s.is_active
  );
$fn$;

revoke execute on function public.is_platform_admin() from public;
grant execute on function public.is_platform_admin() to anon, authenticated, service_role;

-- `is_admin()` widens to include a moderator. Every policy and function that asks it is
-- granting the moderate-and-read surface, which is exactly what the owner described.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(public.claim('admin')::boolean, false)
     and exists (
       select 1 from public.staff s
        where s.uid = (select auth.uid())
          and s.scope = 'platform'
          and s.role in ('admin', 'moderator')
          and s.is_active
     );
$fn$;

revoke execute on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated, service_role;

-- The hook stamps the claim for a moderator as well, so the gate in AdminApp lets them
-- in. `role` still says which they are, and that is what the screens read to decide what
-- to offer — the server is what decides what is permitted.
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  claims jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  meta   jsonb := coalesce(claims -> 'app_metadata', '{}'::jsonb)
                  - array['role', 'scope', 'merchant_id', 'admin'];
  s      record;
begin
  select scope, role, merchant_id
    into s
    from public.staff
   where uid = (event ->> 'user_id')::uuid
     and is_active;

  if found then
    meta := meta || jsonb_build_object('role', s.role, 'scope', s.scope);

    if s.merchant_id is not null then
      meta := meta || jsonb_build_object('merchant_id', s.merchant_id);
    end if;

    if s.scope = 'platform' and s.role in ('admin', 'moderator') then
      meta := meta || jsonb_build_object('admin', true);
    end if;
  end if;

  return jsonb_set(event, '{claims,app_metadata}', meta);
end;
$fn$;

revoke execute on function public.custom_access_token_hook(jsonb)
  from public, anon, authenticated;
grant execute on function public.custom_access_token_hook(jsonb)
  to supabase_auth_admin;

-- ------------------------------------------------------------------ nothing is deleted

-- Twenty-five tables carry a `for all` policy gated on `is_admin()`, and widening that
-- function opens the delete on every one of them. Rewriting all twenty-five to split the
-- verb would be twenty-five chances to widen something by accident; a trigger only ever
-- refuses, so the worst a mistake here can do is stop an admin deleting something.
create or replace function public.refuse_moderator_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  -- A trusted server function acting on its own behalf is not a moderator pressing a
  -- button; cascades and scheduled work declare server mode and pass through.
  if coalesce(pg_catalog.current_setting('app.server_mode', true), '') = 'on' then
    return old;
  end if;

  if public.is_admin() and not public.is_platform_admin() then
    raise exception 'a moderator may review and edit, but not delete'
      using errcode = '42501';
  end if;

  return old;
end;
$fn$;

revoke all on function public.refuse_moderator_delete() from public, anon, authenticated;

do $body$
declare
  t text;
begin
  foreach t in array array[
    'addresses', 'cities', 'config', 'coupons', 'courier_merchants', 'cuisines',
    'daily_meals', 'dismissed_landmark_suggestions', 'home_sections', 'landmarks',
    'media', 'menu_categories', 'menu_items', 'merchant_cuisines',
    'merchant_served_zones', 'merchants', 'order_issues', 'orders', 'plans',
    'promotions', 'ratings', 'staff', 'subscriptions', 'users', 'zones'
  ] loop
    execute pg_catalog.format(
      'drop trigger if exists refuse_moderator_delete on public.%I', t);
    execute pg_catalog.format(
      'create trigger refuse_moderator_delete before delete on public.%I '
      'for each row execute function public.refuse_moderator_delete()', t);
  end loop;
end;
$body$;

-- ------------------------------------------------------------------ nor the till

-- A moderator may not touch the money. Each of these already refused anybody who was not
-- an admin; the only change is *which* question they ask, now that `is_admin()` answers
-- for two roles.
do $body$
declare
  fn text;
  def text;
begin
  foreach fn in array array[
    'top_up_wallet', 'record_subscription_payment', 'record_commission_payment',
    'record_courier_payment', 'admin_set_commission_policy', 'admin_set_shop_commission',
    'admin_set_plan', 'activate_subscription_request', 'reject_subscription_request',
    'create_coupon', 'update_coupon', 'set_coupon_active', 'admin_delete_account',
    'admin_delete_merchant'
  ] loop
    -- Rewritten in place: read the body, swap the question, put it back. Listing every
    -- signature by hand across eight migrations is where a typo becomes an open door.
    for def in
      select pg_catalog.pg_get_functiondef(p.oid)
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = fn
    loop
      if def like '%is_admin()%' then
        execute pg_catalog.replace(def, 'public.is_admin()', 'public.is_platform_admin()');
      end if;
    end loop;
  end loop;
end;
$body$;

-- ------------------------------------------------------------------ nor the roster

-- `staff` and `courier_merchants` decide who anybody *is*. A moderator with an admin's
-- reach on `staff` could write `role = 'admin'` onto their own row, which is the one
-- permission that hands out every other one.
create or replace function public.refuse_moderator_privilege_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if coalesce(pg_catalog.current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  if public.is_admin() and not public.is_platform_admin() then
    raise exception 'a moderator may not change who anybody is'
      using errcode = '42501';
  end if;

  return new;
end;
$fn$;

revoke all on function public.refuse_moderator_privilege_write()
  from public, anon, authenticated;

drop trigger if exists refuse_moderator_privilege_write on public.staff;
create trigger refuse_moderator_privilege_write
  before insert or update on public.staff
  for each row execute function public.refuse_moderator_privilege_write();

drop trigger if exists refuse_moderator_privilege_write on public.courier_merchants;
create trigger refuse_moderator_privilege_write
  before insert or update on public.courier_merchants
  for each row execute function public.refuse_moderator_privilege_write();

-- `config` is the control plane: the commission rate is money by another name, and
-- `min_supported_version` walls every customer out of the product with no back door.
drop trigger if exists refuse_moderator_privilege_write on public.config;
create trigger refuse_moderator_privilege_write
  before insert or update on public.config
  for each row execute function public.refuse_moderator_privilege_write();

-- And `plans`, which is what a subscription is priced from.
drop trigger if exists refuse_moderator_privilege_write on public.plans;
create trigger refuse_moderator_privilege_write
  before insert or update on public.plans
  for each row execute function public.refuse_moderator_privilege_write();
