-- An order remains as financial history after its customer account is deleted, but the
-- frozen delivery address must not remain a route back to that person. The zone is the
-- only address field the ledger needs; it is broad geography and also already frozen on
-- orders.zone_id. Both scrubs run inside the existing server-mode window so the order
-- column guard stays in force before and after the trusted function returns.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid uuid := auth.uid();
  v_orders_scrubbed integer;
  v_prior_mode text;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  -- An already-deleted GoTrue row makes a retry a success. A phone can lose the first
  -- response after the transaction commits, and asking it to distinguish that from a
  -- failed request would make an irreversible action look uncertain.
  perform 1 from auth.users where id = v_uid for update;
  if not found then
    return;
  end if;

  -- Shop ownership and delivery authority outlive a customer-app screen. Removing either
  -- needs an administrator who can hand the responsibility to somebody else first.
  if exists (select 1 from public.staff where uid = v_uid) then
    raise exception 'staff accounts require administrative deletion'
      using errcode = 'insufficient_privilege';
  end if;

  -- `guard_order_columns` asks whether a trusted server function has declared itself, not
  -- who owns the function -- `security definer` does not satisfy it, and without this the
  -- scrub below is refused outright with "column not yours to change on an order".
  --
  -- It has to cover the deletion as well: `orders.customer_uid` is `on delete set null`,
  -- and that referential action runs as an ordinary update, firing the same guard on a
  -- column no role is ever allowed to write.
  --
  -- Restored rather than left standing, because the setting is transaction-local and this
  -- runs inside the caller's transaction -- leaving it on would stand every guard down for
  -- whatever that transaction did next.
  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  -- The contact marker explains why the person is gone. The address keeps only the broad
  -- zone needed by the financial record; no empty personal-detail keys survive.
  update public.orders
     set customer_name = 'حساب محذوف',
         customer_phone = 'حساب محذوف',
         address = pg_catalog.jsonb_build_object('zoneId', zone_id)
   where customer_uid = v_uid;
  get diagnostics v_orders_scrubbed = row_count;

  -- The transaction makes this entry proof that the scrub and GoTrue deletion both
  -- completed. Detail keeps only the channel and counts needed to audit the event;
  -- deliberately no uid, name, phone, or other personal data survives in it.
  insert into public.audit_log (action, actor, detail)
  values (
    'customer.account_deleted',
    v_uid,
    pg_catalog.jsonb_build_object(
      'source', 'customer_app',
      'ordersScrubbed', v_orders_scrubbed,
      'authUserDeleted', true
    )
  );

  -- Existing cascades remove the profile, addresses, ratings, tokens and sessions. The
  -- orders reference is set null; settlement rows still restrict deletion of the orders
  -- themselves, so the ledger remains intact.
  delete from auth.users where id = v_uid;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
end;
$fn$;

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

  -- Scrub customer personal contact details and retain only the order's broad zone.
  update public.orders
     set customer_name  = 'حساب محذوف',
         customer_phone = 'حساب محذوف',
         address = pg_catalog.jsonb_build_object('zoneId', zone_id)
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
