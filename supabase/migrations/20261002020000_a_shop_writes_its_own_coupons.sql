-- A merchant owner creates and manages coupons for their own shop.
--
-- A merchant owner creates coupons for their own shop, they go live immediately,
-- and the admin can see and stop any coupon. Customers still never read the table —
-- they only call evaluate_coupon.

-- 1. Policy on coupons for merchant owners
create policy merchant_owner_coupons on public.coupons
  for all to authenticated
  -- `funded_by` in `using` as well as `with check`: `with check` guards only the row being
  -- written, so without it an owner could read and delete a coupon the platform pays for
  -- that an admin placed on their shop.
  using (
    merchant_id is not null
    and public.is_merchant_owner(merchant_id)
    and funded_by = 'merchant'
  )
  with check (
    merchant_id is not null
    and public.is_merchant_owner(merchant_id)
    and funded_by = 'merchant'
  );

-- 2. Guard trigger for merchant writes
-- Unless public.is_admin() or app.server_mode = 'on':
-- - forces used_count to stay what it was (0 on insert)
-- - forces created_by = auth.uid() on insert and keeps it on update
-- - refuses changing merchant_id or city_id on update
-- - city_id on insert must equal the merchant's city_id (refuse otherwise)
create or replace function public.coupons_guard_merchant_writes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_merchant_city_id text;
begin
  if public.is_admin() or coalesce(pg_catalog.current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.used_count := 0;
    new.created_by := auth.uid();

    select m.city_id into v_merchant_city_id
      from public.merchants m
     where m.id = new.merchant_id;

    if v_merchant_city_id is null or new.city_id is distinct from v_merchant_city_id then
      raise exception 'coupon city must match merchant city' using errcode = '42501';
    end if;
  elsif tg_op = 'UPDATE' then
    new.used_count := old.used_count;
    new.created_by := old.created_by;

    if new.merchant_id is distinct from old.merchant_id then
      raise exception 'cannot change merchant on a coupon' using errcode = '42501';
    end if;
    if new.city_id is distinct from old.city_id then
      raise exception 'cannot change city on a coupon' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$fn$;

drop trigger if exists coupons_guard_merchant_writes on public.coupons;
create trigger coupons_guard_merchant_writes
  before insert or update on public.coupons
  for each row execute function public.coupons_guard_merchant_writes();
