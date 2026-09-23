-- SNAPSHOT of public.admin_delete_account as it runs — written by snapshot-functions.mjs.
-- Documentation only: never applied. Change it with a migration.

CREATE OR REPLACE FUNCTION public.admin_delete_account(p_uid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_staff_scope     text;
  v_staff_role      text;
  v_kind            text;
  v_orders_scrubbed integer := 0;
  v_prior_mode      text;
begin
  if auth.uid() is null or not public.is_platform_admin() then
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
  -- Not while an order is on its way: scrubbing it would take the street and the phone
  -- off an order a courier is carrying. Finished or cancelled first (A9).
  if exists (
    select 1 from public.orders
     where customer_uid = p_uid
       and status in ('placed', 'accepted', 'preparing', 'outForDelivery',
                      'needsAttention')
  ) then
    raise exception 'an order is still on its way' using errcode = 'P0001';
  end if;

  -- An application that never became an account leaves with its applicant: the
  -- name, number and note in it are theirs.
  delete from public.staff_applications
   where applicant_uid = p_uid and status <> 'approved';

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  -- Scrub customer personal contact details and retain only the order's broad zone.
  update public.orders
     set customer_name  = 'حساب محذوف',
         customer_phone = 'حساب محذوف',
         address = pg_catalog.jsonb_build_object('zoneId', zone_id),
         note = null,
         items = coalesce(
           (select pg_catalog.jsonb_agg(line.value - 'note' order by line.ordinality)
              from pg_catalog.jsonb_array_elements(items)
                   with ordinality as line(value, ordinality)),
           items)
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
$function$;
