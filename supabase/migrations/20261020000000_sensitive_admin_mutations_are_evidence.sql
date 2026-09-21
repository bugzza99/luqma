-- H-09: the five highest-value unaudited admin mutations.
--
-- A decision and its evidence are one database operation. Every actor comes from
-- auth.uid(); no function accepts an actor parameter. Direct PostgREST paths are closed
-- where these writes used to use them, so an older APK cannot walk around the RPC.

-- ------------------------------------------------------------------ staff grants

create function public.create_staff_profile(
  p_uid         uuid,
  p_scope       text,
  p_role        text,
  p_merchant_id uuid default null
)
returns public.staff
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor uuid := auth.uid();
  v_staff public.staff;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin creates staff' using errcode = '42501';
  end if;

  if p_scope not in ('platform', 'merchant')
     or p_role not in ('admin', 'moderator', 'owner', 'courier')
     or (p_scope = 'platform' and p_role not in ('admin', 'moderator', 'courier'))
     or (p_scope = 'merchant' and p_role not in ('owner', 'courier'))
     or (p_scope = 'platform' and p_merchant_id is not null)
     or (p_scope = 'merchant' and p_merchant_id is null) then
    raise exception 'invalid staff scope and role' using errcode = 'check_violation';
  end if;

  if p_merchant_id is not null
     and not exists (select 1 from public.merchants where id = p_merchant_id) then
    raise exception 'no such merchant' using errcode = 'P0002';
  end if;

  insert into public.staff (uid, scope, role, merchant_id)
  values (p_uid, p_scope, p_role, p_merchant_id)
  returning * into v_staff;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values (
    'staff.created', v_actor, p_merchant_id,
    pg_catalog.jsonb_build_object(
      'old', null,
      'new', pg_catalog.jsonb_build_object(
        'uid', p_uid,
        'scope', p_scope,
        'role', p_role,
        'merchantId', p_merchant_id
      )
    )
  );

  return v_staff;
end;
$fn$;

revoke all on function public.create_staff_profile(uuid, text, text, uuid)
  from public, anon;
grant execute on function public.create_staff_profile(uuid, text, text, uuid)
  to authenticated, service_role;

-- ------------------------------------------------------------------ media moderation

create function public.admin_review_media(
  p_id     uuid,
  p_status text,
  p_note   text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor uuid := auth.uid();
  v_old   public.media;
  v_new   public.media;
  v_note  text := nullif(pg_catalog.btrim(p_note), '');
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin reviews media' using errcode = '42501';
  end if;
  if p_status not in ('approved', 'rejected') then
    raise exception 'a review must approve or reject media' using errcode = 'check_violation';
  end if;

  select * into v_old from public.media where id = p_id for update;
  if not found then
    raise exception 'media not found' using errcode = 'P0002';
  end if;

  update public.media
     set status = p_status,
         reviewed_by = v_actor,
         review_note = v_note
   where id = p_id
  returning * into v_new;

  insert into public.audit_log (action, actor, detail)
  values (
    'media.reviewed', v_actor,
    pg_catalog.jsonb_build_object(
      'mediaId', p_id,
      'old', pg_catalog.jsonb_build_object(
        'status', v_old.status,
        'reviewedBy', v_old.reviewed_by,
        'reviewNote', v_old.review_note
      ),
      'new', pg_catalog.jsonb_build_object(
        'status', v_new.status,
        'reviewedBy', v_new.reviewed_by,
        'reviewNote', v_new.review_note
      )
    )
  );
end;
$fn$;

revoke all on function public.admin_review_media(uuid, text, text) from public, anon;
grant execute on function public.admin_review_media(uuid, text, text)
  to authenticated, service_role;

-- The upload remains a direct insert. Only moderation's direct update is closed.
revoke update on public.media from authenticated;

-- ------------------------------------------------------------------ merchant decisions

create function public.admin_set_merchant_status(p_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor uuid := auth.uid();
  v_prior text;
  v_old   public.merchants;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin changes merchant status' using errcode = '42501';
  end if;
  if p_status not in ('pending', 'approved', 'suspended') then
    raise exception 'invalid merchant status' using errcode = 'check_violation';
  end if;

  select * into v_old from public.merchants where id = p_id for update;
  if not found then
    raise exception 'no such merchant' using errcode = 'P0002';
  end if;

  v_prior := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);
  update public.merchants set status = p_status where id = p_id;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values (
    'merchant.status_changed', v_actor, p_id,
    pg_catalog.jsonb_build_object(
      'merchantId', p_id,
      'old', pg_catalog.jsonb_build_object('status', v_old.status),
      'new', pg_catalog.jsonb_build_object('status', p_status)
    )
  );
  perform pg_catalog.set_config('app.server_mode', v_prior, true);
end;
$fn$;

create function public.admin_delete_merchant(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor uuid := auth.uid();
  v_old   public.merchants;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin deletes a merchant' using errcode = '42501';
  end if;

  select * into v_old from public.merchants where id = p_id for update;
  if not found then
    raise exception 'no such merchant' using errcode = 'P0002';
  end if;

  delete from public.merchants where id = p_id;

  -- merchant_id stays null because the referenced row is now gone. The deleted id is
  -- durable inside detail instead of being erased by ON DELETE SET NULL.
  insert into public.audit_log (action, actor, detail)
  values (
    'merchant.deleted', v_actor,
    pg_catalog.jsonb_build_object(
      'merchantId', p_id,
      'old', pg_catalog.jsonb_build_object(
        'id', v_old.id,
        'cityId', v_old.city_id,
        'name', v_old.name,
        'status', v_old.status,
        'revenueModel', v_old.revenue_model,
        'revenueValue', v_old.revenue_value
      ),
      'new', null
    )
  );
end;
$fn$;

create function public.admin_set_revenue_model(
  p_id    uuid,
  p_model text,
  p_value integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor uuid := auth.uid();
  v_prior text;
  v_old   public.merchants;
  v_new   public.merchants;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin changes a revenue model' using errcode = '42501';
  end if;
  if p_model not in ('subscription', 'commission', 'prepaid') or p_value < 0 then
    raise exception 'invalid revenue model or value' using errcode = 'check_violation';
  end if;

  select * into v_old from public.merchants where id = p_id for update;
  if not found then
    raise exception 'no such merchant' using errcode = 'P0002';
  end if;

  v_prior := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);
  update public.merchants
     set revenue_model = p_model,
         revenue_value = p_value
   where id = p_id
  returning * into v_new;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values (
    'merchant.revenue_model_changed', v_actor, p_id,
    pg_catalog.jsonb_build_object(
      'merchantId', p_id,
      'old', pg_catalog.jsonb_build_object(
        'model', v_old.revenue_model,
        'value', v_old.revenue_value
      ),
      'new', pg_catalog.jsonb_build_object(
        'model', v_new.revenue_model,
        'value', v_new.revenue_value
      )
    )
  );
  perform pg_catalog.set_config('app.server_mode', v_prior, true);
end;
$fn$;

revoke all on function public.admin_set_merchant_status(uuid, text) from public, anon;
revoke all on function public.admin_delete_merchant(uuid) from public, anon;
revoke all on function public.admin_set_revenue_model(uuid, text, integer) from public, anon;
grant execute on function public.admin_set_merchant_status(uuid, text)
  to authenticated, service_role;
grant execute on function public.admin_delete_merchant(uuid)
  to authenticated, service_role;
grant execute on function public.admin_set_revenue_model(uuid, text, integer)
  to authenticated, service_role;

-- Deletion has no other client path. Status and revenue share the table with legitimate
-- profile writes, so a narrow trigger closes only those columns for old authenticated
-- clients. The RPCs run as their owner and are not the authenticated database role.
revoke delete on public.merchants from authenticated;

create function public.require_merchant_decision_rpc()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if coalesce(pg_catalog.current_setting('role', true), '') = 'authenticated'
     and coalesce(pg_catalog.current_setting('app.server_mode', true), '') <> 'on'
     and (new.status is distinct from old.status
          or new.revenue_model is distinct from old.revenue_model
          or new.revenue_value is distinct from old.revenue_value) then
    raise exception 'merchant status and revenue require an admin RPC'
      using errcode = '42501';
  end if;
  return new;
end;
$fn$;

revoke all on function public.require_merchant_decision_rpc()
  from public, anon, authenticated;
drop trigger if exists merchants_require_decision_rpc on public.merchants;
create trigger merchants_require_decision_rpc
  before update of status, revenue_model, revenue_value on public.merchants
  for each row execute function public.require_merchant_decision_rpc();

-- ------------------------------------------------------------------ coupons

create function public.create_coupon(
  p_code             text,
  p_city_id          text,
  p_type             text,
  p_value            integer,
  p_max_discount     integer,
  p_min_order        integer,
  p_merchant_id      uuid,
  p_first_order_only boolean,
  p_per_user_limit   integer,
  p_total_limit      integer,
  p_is_active        boolean,
  p_funded_by        text,
  p_valid_from       timestamptz,
  p_valid_until      timestamptz
)
returns public.coupons
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor  uuid := auth.uid();
  v_coupon public.coupons;
begin
  if v_actor is null then
    raise exception 'sign in to create a coupon' using errcode = '42501';
  end if;
  if not public.is_admin()
     and not (p_merchant_id is not null
              and public.is_merchant_owner(p_merchant_id)
              and p_funded_by = 'merchant') then
    raise exception 'not allowed to create this coupon' using errcode = '42501';
  end if;
  if not public.is_admin() and not exists (
    select 1 from public.merchants m
     where m.id = p_merchant_id and m.city_id = p_city_id
  ) then
    raise exception 'coupon city must match merchant city' using errcode = '42501';
  end if;

  insert into public.coupons (
    code, city_id, type, value, max_discount, min_order, merchant_id,
    first_order_only, per_user_limit, total_limit, is_active, funded_by,
    valid_from, valid_until
  ) values (
    pg_catalog.upper(pg_catalog.translate(pg_catalog.btrim(p_code),
      '٠١٢٣٤٥٦٧٨٩', '0123456789')),
    p_city_id, p_type, p_value, p_max_discount, p_min_order, p_merchant_id,
    p_first_order_only, p_per_user_limit, p_total_limit, p_is_active,
    p_funded_by, p_valid_from, p_valid_until
  ) returning * into v_coupon;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values (
    'coupon.created', v_actor, v_coupon.merchant_id,
    pg_catalog.jsonb_build_object(
      'couponId', v_coupon.id,
      'old', null,
      'new', pg_catalog.jsonb_build_object(
        'code', v_coupon.code,
        'cityId', v_coupon.city_id,
        'type', v_coupon.type,
        'value', v_coupon.value,
        'maxDiscount', v_coupon.max_discount,
        'minOrder', v_coupon.min_order,
        'merchantId', v_coupon.merchant_id,
        'firstOrderOnly', v_coupon.first_order_only,
        'perUserLimit', v_coupon.per_user_limit,
        'totalLimit', v_coupon.total_limit,
        'isActive', v_coupon.is_active,
        'fundedBy', v_coupon.funded_by,
        'validFrom', v_coupon.valid_from,
        'validUntil', v_coupon.valid_until
      )
    )
  );

  return v_coupon;
end;
$fn$;

create function public.update_coupon(
  p_id               uuid,
  p_code             text,
  p_type             text,
  p_value            integer,
  p_max_discount     integer,
  p_min_order        integer,
  p_first_order_only boolean,
  p_per_user_limit   integer,
  p_total_limit      integer,
  p_is_active        boolean,
  p_funded_by        text,
  p_valid_from       timestamptz,
  p_valid_until      timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor uuid := auth.uid();
  v_old   public.coupons;
  v_new   public.coupons;
begin
  if v_actor is null then
    raise exception 'sign in to update a coupon' using errcode = '42501';
  end if;

  select * into v_old from public.coupons where id = p_id for update;
  if not found then
    raise exception 'coupon not found' using errcode = 'P0002';
  end if;
  if not public.is_admin()
     and not (v_old.merchant_id is not null
              and public.is_merchant_owner(v_old.merchant_id)
              and v_old.funded_by = 'merchant'
              and p_funded_by = 'merchant') then
    raise exception 'not allowed to update this coupon' using errcode = '42501';
  end if;

  update public.coupons
     set code = pg_catalog.upper(pg_catalog.translate(pg_catalog.btrim(p_code),
           '٠١٢٣٤٥٦٧٨٩', '0123456789')),
         type = p_type,
         value = p_value,
         max_discount = p_max_discount,
         min_order = p_min_order,
         first_order_only = p_first_order_only,
         per_user_limit = p_per_user_limit,
         total_limit = p_total_limit,
         is_active = p_is_active,
         funded_by = p_funded_by,
         valid_from = p_valid_from,
         valid_until = p_valid_until,
         updated_at = pg_catalog.now()
   where id = p_id
  returning * into v_new;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values (
    'coupon.updated', v_actor, v_new.merchant_id,
    pg_catalog.jsonb_build_object(
      'couponId', p_id,
      'old', pg_catalog.jsonb_build_object(
        'code', v_old.code, 'type', v_old.type, 'value', v_old.value,
        'maxDiscount', v_old.max_discount, 'minOrder', v_old.min_order,
        'firstOrderOnly', v_old.first_order_only,
        'perUserLimit', v_old.per_user_limit, 'totalLimit', v_old.total_limit,
        'isActive', v_old.is_active, 'fundedBy', v_old.funded_by,
        'validFrom', v_old.valid_from, 'validUntil', v_old.valid_until
      ),
      'new', pg_catalog.jsonb_build_object(
        'code', v_new.code, 'type', v_new.type, 'value', v_new.value,
        'maxDiscount', v_new.max_discount, 'minOrder', v_new.min_order,
        'firstOrderOnly', v_new.first_order_only,
        'perUserLimit', v_new.per_user_limit, 'totalLimit', v_new.total_limit,
        'isActive', v_new.is_active, 'fundedBy', v_new.funded_by,
        'validFrom', v_new.valid_from, 'validUntil', v_new.valid_until
      )
    )
  );
end;
$fn$;

create function public.set_coupon_active(p_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor uuid := auth.uid();
  v_old   public.coupons;
begin
  if v_actor is null then
    raise exception 'sign in to change a coupon' using errcode = '42501';
  end if;

  select * into v_old from public.coupons where id = p_id for update;
  if not found then
    raise exception 'coupon not found' using errcode = 'P0002';
  end if;
  if not public.is_admin()
     and not (v_old.merchant_id is not null
              and public.is_merchant_owner(v_old.merchant_id)
              and v_old.funded_by = 'merchant') then
    raise exception 'not allowed to change this coupon' using errcode = '42501';
  end if;

  update public.coupons
     set is_active = p_active,
         updated_at = pg_catalog.now()
   where id = p_id;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values (
    'coupon.active_changed', v_actor, v_old.merchant_id,
    pg_catalog.jsonb_build_object(
      'couponId', p_id,
      'old', pg_catalog.jsonb_build_object('isActive', v_old.is_active),
      'new', pg_catalog.jsonb_build_object('isActive', p_active)
    )
  );
end;
$fn$;

revoke all on function public.create_coupon(
  text, text, text, integer, integer, integer, uuid, boolean, integer, integer,
  boolean, text, timestamptz, timestamptz
) from public, anon;
revoke all on function public.update_coupon(
  uuid, text, text, integer, integer, integer, boolean, integer, integer,
  boolean, text, timestamptz, timestamptz
) from public, anon;
revoke all on function public.set_coupon_active(uuid, boolean) from public, anon;
grant execute on function public.create_coupon(
  text, text, text, integer, integer, integer, uuid, boolean, integer, integer,
  boolean, text, timestamptz, timestamptz
) to authenticated, service_role;
grant execute on function public.update_coupon(
  uuid, text, text, integer, integer, integer, boolean, integer, integer,
  boolean, text, timestamptz, timestamptz
) to authenticated, service_role;
grant execute on function public.set_coupon_active(uuid, boolean)
  to authenticated, service_role;

-- Reads remain policy-controlled. Every client mutation now has one RPC door.
revoke insert, update, delete on public.coupons from authenticated;

-- ------------------------------------------------------------------ subscription request decisions

create or replace function public.activate_subscription_request(
  p_id     uuid,
  p_amount integer default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor      uuid := auth.uid();
  v_prior_mode text;
  v_req        public.subscription_requests;
  v_sub_json   jsonb;
  v_sub_id     uuid;
  v_amount     integer;
  v_expires_at timestamptz;
  v_plan_name  text;
  v_date_str   text;
  v_owner      record;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin can activate a subscription request' using errcode = '42501';
  end if;

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');

  select * into v_req
    from public.subscription_requests
   where id = p_id
     for update;

  if not found then
    raise exception 'subscription request not found' using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'only pending requests can be activated' using errcode = 'P0001';
  end if;
  if p_amount is not null and p_amount < 0 then
    raise exception 'amount cannot be negative' using errcode = 'check_violation';
  end if;

  v_amount := coalesce(p_amount, v_req.quoted_amount);
  v_sub_json := public.record_subscription_payment(
    v_req.merchant_id, v_req.plan_id, v_amount, v_req.months
  );
  v_sub_id := (v_sub_json ->> 'id')::uuid;
  v_expires_at := (v_sub_json ->> 'expires_at')::timestamptz;

  update public.subscription_requests
     set status = 'activated',
         subscription_id = v_sub_id,
         reviewed_by = v_actor,
         reviewed_at = pg_catalog.now()
   where id = p_id;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values (
    'subscription_request.activated', v_actor, v_req.merchant_id,
    pg_catalog.jsonb_build_object(
      'requestId', p_id,
      'old', pg_catalog.jsonb_build_object(
        'status', v_req.status,
        'planId', v_req.plan_id,
        'months', v_req.months,
        'quotedAmount', v_req.quoted_amount
      ),
      'new', pg_catalog.jsonb_build_object(
        'status', 'activated',
        'subscriptionId', v_sub_id,
        'amount', v_amount,
        'reviewedBy', v_actor
      )
    )
  );

  select name into v_plan_name from public.plans where id = v_req.plan_id;
  v_date_str := pg_catalog.to_char(
    v_expires_at at time zone 'Africa/Cairo', 'DD/MM/YYYY'
  );

  for v_owner in
    select uid from public.staff
     where merchant_id = v_req.merchant_id and role = 'owner' and is_active
  loop
    insert into public.push_outbox (uid, title, body, data, channel)
    values (
      v_owner.uid,
      'اشتراكك اتفعّل',
      'باقة ' || coalesce(v_plan_name, v_req.plan_id) || ' شغالة لحد ' || v_date_str,
      pg_catalog.jsonb_build_object(
        'kind', 'subscription_activated', 'requestId', p_id::text,
        'subscriptionId', v_sub_id::text
      ),
      'orders_critical'
    );
  end loop;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
end;
$$;

create or replace function public.reject_subscription_request(
  p_id     uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor      uuid := auth.uid();
  v_prior_mode text;
  v_req        public.subscription_requests;
  v_reason     text;
  v_owner      record;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin can reject a subscription request' using errcode = '42501';
  end if;

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');

  select * into v_req
    from public.subscription_requests
   where id = p_id
     for update;

  if not found then
    raise exception 'subscription request not found' using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'only pending requests can be rejected' using errcode = 'P0001';
  end if;

  v_reason := nullif(pg_catalog.btrim(p_reason), '');
  if v_reason is null then
    raise exception 'rejection reason is required' using errcode = 'check_violation';
  end if;

  update public.subscription_requests
     set status = 'rejected',
         reject_reason = v_reason,
         reviewed_by = v_actor,
         reviewed_at = pg_catalog.now()
   where id = p_id;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values (
    'subscription_request.rejected', v_actor, v_req.merchant_id,
    pg_catalog.jsonb_build_object(
      'requestId', p_id,
      'old', pg_catalog.jsonb_build_object(
        'status', v_req.status,
        'planId', v_req.plan_id,
        'months', v_req.months,
        'quotedAmount', v_req.quoted_amount
      ),
      'new', pg_catalog.jsonb_build_object(
        'status', 'rejected',
        'reason', v_reason,
        'reviewedBy', v_actor
      )
    )
  );

  for v_owner in
    select uid from public.staff
     where merchant_id = v_req.merchant_id and role = 'owner' and is_active
  loop
    insert into public.push_outbox (uid, title, body, data, channel)
    values (
      v_owner.uid,
      'طلب الاشتراك اترفض',
      v_reason,
      pg_catalog.jsonb_build_object(
        'kind', 'subscription_rejected', 'requestId', p_id::text
      ),
      'orders_critical'
    );
  end loop;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
end;
$$;

revoke all on function public.activate_subscription_request(uuid, integer)
  from public, anon;
revoke all on function public.reject_subscription_request(uuid, text)
  from public, anon;
grant execute on function public.activate_subscription_request(uuid, integer)
  to authenticated, service_role;
grant execute on function public.reject_subscription_request(uuid, text)
  to authenticated, service_role;
