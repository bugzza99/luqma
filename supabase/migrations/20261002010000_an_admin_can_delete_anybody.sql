-- An admin can delete any customer, merchant owner or courier (except platform staff).
--
-- Deleting an account removes personal data and credentials while preserving financial
-- records (orders, settlements).
--
-- Two foreign keys to auth.users block deletion today and become `on delete set null`:
-- 1. promotions.requested_by (was restrict)
-- 2. commission_payments.recorded_by (was no action)

do $$
declare
  v_con text;
begin
  -- 1. promotions.requested_by
  select conname into v_con
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
   where c.conrelid = 'public.promotions'::regclass
     and c.contype = 'f'
     and a.attname = 'requested_by';

  if v_con is not null then
    execute format('alter table public.promotions drop constraint %I', v_con);
  end if;

  alter table public.promotions alter column requested_by drop not null;
  alter table public.promotions
    add constraint promotions_requested_by_fkey
    foreign key (requested_by) references auth.users(id) on delete set null;

  -- 2. commission_payments.recorded_by
  select conname into v_con
    from pg_constraint c
    join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
   where c.conrelid = 'public.commission_payments'::regclass
     and c.contype = 'f'
     and a.attname = 'recorded_by';

  if v_con is not null then
    execute format('alter table public.commission_payments drop constraint %I', v_con);
  end if;

  alter table public.commission_payments alter column recorded_by drop not null;
  alter table public.commission_payments
    add constraint commission_payments_recorded_by_fkey
    foreign key (recorded_by) references auth.users(id) on delete set null;
end $$;

-- Administrative account deletion for any customer, owner or courier.
-- Refuses platform staff and self-deletion.
create or replace function public.admin_delete_account(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_staff_scope     text;
  v_staff_role      text;
  v_kind            text;
  v_orders_scrubbed integer := 0;
  v_prior_mode      text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  if p_uid = auth.uid() then
    raise exception 'cannot delete yourself'
      using errcode = 'insufficient_privilege';
  end if;

  -- Lock row in auth.users; if already gone, return (idempotent retry)
  perform 1 from auth.users where id = p_uid for update;
  if not found then
    return;
  end if;

  select scope, role into v_staff_scope, v_staff_role
    from public.staff
   where uid = p_uid;

  if v_staff_scope = 'platform' then
    raise exception 'cannot delete platform staff'
      using errcode = 'insufficient_privilege';
  end if;

  if v_staff_scope = 'merchant' and v_staff_role in ('owner', 'courier') then
    v_kind := v_staff_role;
  else
    v_kind := 'customer';
  end if;

  -- Set server_mode to on so guard triggers allow scrubbing order fields and cascade updates
  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  -- Scrub customer personal contact details on their orders
  update public.orders
     set customer_name  = 'حساب محذوف',
         customer_phone = 'حساب محذوف'
   where customer_uid = p_uid;
  get diagnostics v_orders_scrubbed = row_count;

  -- Deactivate courier attachments
  if v_kind = 'courier' then
    update public.courier_merchants
       set is_active = false
     where courier_uid = p_uid;
  end if;

  -- Audit without personal data
  insert into public.audit_log (action, actor, detail)
  values (
    'account.deleted_by_admin',
    auth.uid(),
    pg_catalog.jsonb_build_object(
      'kind', v_kind,
      'ordersScrubbed', v_orders_scrubbed
    )
  );

  delete from auth.users where id = p_uid;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
end;
$fn$;

revoke all on function public.admin_delete_account(uuid) from public, anon, service_role;
grant execute on function public.admin_delete_account(uuid) to authenticated;
