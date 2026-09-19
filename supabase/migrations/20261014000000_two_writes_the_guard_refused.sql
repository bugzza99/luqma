-- The server can write a coupon (found 2026-09-19, when the cloud test suite first ran
-- against every migration since 2026-09-11).
--
-- `coupons_guard_merchant_writes` let two callers past it — an admin, and a function that
-- declared server mode — and treated everybody else as a shop writing its own coupon. The
-- service key and the dashboard are neither, so a platform coupon made from either was
-- refused with «coupon city must match merchant city», as if it had named a shop.

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
  -- The server itself — the service key, the dashboard's SQL editor, a seed script — is
  -- not a shop and has no merchant to match. It used to be refused as if it were one, so
  -- a platform-wide coupon could only be made from AdminApp.
  if auth.uid() is null
     and (session_user in ('postgres', 'supabase_admin')
          or coalesce(auth.jwt() ->> 'role', '') = 'service_role') then
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

-- And the prepaid hold, found by the same run: `hold_prepaid_credit` writes
-- `merchants.wallet_held` from a trigger on `orders`, and never declared server mode. On
-- insert that was hidden — `place_order` declares it first — but the release runs inside
-- whoever moved the status: the courier marking a prepaid order delivered, the shop
-- refusing it, the customer cancelling it. `guard_columns` refused every one of them, so a
-- prepaid shop's orders could not be finished at all. `security definer` does not help; the
-- guard asks whether a trusted function has declared itself (CLAUDE.md), and it is put back
-- afterwards because the setting is transaction-local inside the caller's transaction.
create or replace function public.hold_prepaid_credit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_hold  integer;
  v_prior text;
begin
  if tg_op = 'INSERT' then
    v_hold := public.prepaid_hold_for(new);
  elsif old.status not in ('delivered', 'cancelled', 'rejected')
        and new.status in ('delivered', 'cancelled', 'rejected') then
    -- Released once, on the first move out of a live state.
    v_hold := -public.prepaid_hold_for(new);
  else
    return new;
  end if;

  if v_hold <> 0 then
    v_prior := coalesce(current_setting('app.server_mode', true), '');
    perform set_config('app.server_mode', 'on', true);
    update public.merchants
       set wallet_held = greatest(wallet_held + v_hold, 0)
     where id = new.merchant_id;
    perform set_config('app.server_mode', v_prior, true);
  end if;
  return new;
end;
$$;
