-- Slice S1: subscriptions a shop can ask for, server half.
--
-- The owner's decisions:
-- 1. A plan is a monthly amount instead of commission: while a shop's plan is active
--    (plan_id is not null and plan_expires_at > now()), its orders carry no commission
--    and no prepaid charge. When it ends the shop goes back to its own revenue model/value.
-- 2. The shop asks from MerchantApp: a plan, 1/3/6/12 months, and payment method (cash/transfer).
--    The admin confirms the money arrived and activates, possibly with a different amount,
--    or rejects with a reason.
-- 3. The shop and admins are told 3 days before a plan ends.

-- ------------------------------------------------------------------ A. Requests table

create table public.subscription_requests (
  id                  uuid primary key default gen_random_uuid(),
  merchant_id         uuid not null references public.merchants on delete cascade,
  plan_id             text not null references public.plans on delete restrict,
  months              integer not null check (months in (1, 3, 6, 12)),
  quoted_amount       integer not null check (quoted_amount >= 0),
  payment_method      text not null check (payment_method in ('cash', 'transfer')),
  transfer_reference  text check (transfer_reference is null or char_length(transfer_reference) <= 80),
  status              text not null default 'pending'
                        check (status in ('pending', 'activated', 'rejected', 'cancelled')),
  reject_reason       text,
  requested_by        uuid references auth.users on delete set null,
  reviewed_by         uuid references auth.users on delete set null,
  reviewed_at         timestamptz,
  subscription_id     uuid references public.subscriptions on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- At most one pending request per merchant.
create unique index subscription_requests_one_pending_idx
  on public.subscription_requests (merchant_id)
  where status = 'pending';

create trigger subscription_requests_set_updated_at
  before update on public.subscription_requests
  for each row execute function public.set_updated_at();

alter table public.subscription_requests enable row level security;
alter table public.subscription_requests force row level security;

-- No client insert/update/delete policies: every write goes through functions.
create policy subscription_requests_owner_and_admin_select
  on public.subscription_requests
  for select to authenticated
  using (public.is_merchant_owner(merchant_id) or public.is_admin());

revoke all on public.subscription_requests from public, anon, authenticated;
grant select on public.subscription_requests to authenticated, service_role;

-- ------------------------------------------------------------------ request_subscription

create or replace function public.request_subscription(
  p_plan_id        text,
  p_months         integer,
  p_payment_method text,
  p_reference      text default null
)
returns public.subscription_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prior_mode    text;
  v_merchant_id   uuid;
  v_merchant_name text;
  v_plan          public.plans;
  v_quoted_amount integer;
  v_reference     text;
  v_request       public.subscription_requests;
  v_admin         record;
begin
  if auth.uid() is null then
    raise exception 'sign in to request a subscription' using errcode = '42501';
  end if;

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');

  select s.merchant_id into v_merchant_id
    from public.staff s
   where s.uid = auth.uid()
     and s.role = 'owner'
     and s.is_active;

  if v_merchant_id is null then
    raise exception 'only an active merchant owner can request a subscription' using errcode = '42501';
  end if;

  select * into v_plan
    from public.plans
   where id = p_plan_id;

  if not found or not v_plan.is_active then
    raise exception 'plan not found or inactive' using errcode = 'P0002';
  end if;

  if p_months not in (1, 3, 6, 12) then
    raise exception 'months must be 1, 3, 6, or 12' using errcode = 'check_violation';
  end if;

  if p_payment_method not in ('cash', 'transfer') then
    raise exception 'payment method must be cash or transfer' using errcode = 'check_violation';
  end if;

  v_reference := nullif(btrim(p_reference), '');
  if v_reference is not null and char_length(v_reference) > 80 then
    raise exception 'transfer reference exceeds 80 characters' using errcode = 'check_violation';
  end if;

  v_quoted_amount := v_plan.price_monthly * p_months;

  select name into v_merchant_name
    from public.merchants
   where id = v_merchant_id;

  insert into public.subscription_requests (
    merchant_id, plan_id, months, quoted_amount, payment_method,
    transfer_reference, status, requested_by
  ) values (
    v_merchant_id, p_plan_id, p_months, v_quoted_amount, p_payment_method,
    v_reference, 'pending', auth.uid()
  ) returning * into v_request;

  for v_admin in
    select uid from public.staff
     where scope = 'platform' and role = 'admin' and is_active
  loop
    insert into public.push_outbox (uid, title, body, data, channel)
    values (
      v_admin.uid,
      'طلب اشتراك جديد',
      v_merchant_name || ' طلب باقة ' || v_plan.name || ' لمدة ' || p_months || ' شهر',
      jsonb_build_object('kind', 'subscription_request', 'requestId', v_request.id::text),
      'orders_critical'
    );
  end loop;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
  return v_request;
end;
$$;

revoke execute on function public.request_subscription(text, integer, text, text) from public, anon;
grant execute on function public.request_subscription(text, integer, text, text) to authenticated, service_role;

-- ------------------------------------------------------------------ cancel_subscription_request

create or replace function public.cancel_subscription_request(p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prior_mode text;
  v_req        public.subscription_requests;
begin
  if auth.uid() is null then
    raise exception 'sign in to cancel a subscription request' using errcode = '42501';
  end if;

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');

  -- Locked: two admins answering the same request at once must not both see it pending —
  -- that is one payment credited as two terms (found in review).
  select * into v_req
    from public.subscription_requests
   where id = p_id
     for update;

  if not found then
    raise exception 'subscription request not found' using errcode = 'P0002';
  end if;

  if v_req.status <> 'pending' then
    raise exception 'only pending requests can be cancelled' using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.staff
     where uid = auth.uid()
       and merchant_id = v_req.merchant_id
       and role = 'owner'
       and is_active
  ) then
    raise exception 'only the shop owner can cancel this request' using errcode = '42501';
  end if;

  update public.subscription_requests
     set status = 'cancelled'
   where id = p_id;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
end;
$$;

revoke execute on function public.cancel_subscription_request(uuid) from public, anon;
grant execute on function public.cancel_subscription_request(uuid) to authenticated, service_role;

-- ------------------------------------------------------------------ activate_subscription_request

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
  v_prior_mode text;
  v_req        public.subscription_requests;
  v_sub_json   jsonb;
  v_sub_id     uuid;
  v_expires_at timestamptz;
  v_plan_name  text;
  v_date_str   text;
  v_owner      record;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'only an admin can activate a subscription request' using errcode = '42501';
  end if;

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');

  -- Locked: two admins answering the same request at once must not both see it pending —
  -- that is one payment credited as two terms (found in review).
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

  v_sub_json := public.record_subscription_payment(
    v_req.merchant_id,
    v_req.plan_id,
    coalesce(p_amount, v_req.quoted_amount),
    v_req.months
  );
  v_sub_id := (v_sub_json ->> 'id')::uuid;
  v_expires_at := (v_sub_json ->> 'expires_at')::timestamptz;

  update public.subscription_requests
     set status = 'activated',
         subscription_id = v_sub_id,
         reviewed_by = auth.uid(),
         reviewed_at = now()
   where id = p_id;

  select name into v_plan_name
    from public.plans
   where id = v_req.plan_id;

  v_date_str := to_char(v_expires_at at time zone 'Africa/Cairo', 'DD/MM/YYYY');

  for v_owner in
    select uid from public.staff
     where merchant_id = v_req.merchant_id
       and role = 'owner'
       and is_active
  loop
    insert into public.push_outbox (uid, title, body, data, channel)
    values (
      v_owner.uid,
      'اشتراكك اتفعّل',
      'باقة ' || coalesce(v_plan_name, v_req.plan_id) || ' شغالة لحد ' || v_date_str,
      jsonb_build_object('kind', 'subscription_activated', 'requestId', p_id::text, 'subscriptionId', v_sub_id::text),
      'orders_critical'
    );
  end loop;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
end;
$$;

revoke execute on function public.activate_subscription_request(uuid, integer) from public, anon;
grant execute on function public.activate_subscription_request(uuid, integer) to authenticated, service_role;

-- ------------------------------------------------------------------ reject_subscription_request

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
  v_prior_mode text;
  v_req        public.subscription_requests;
  v_reason     text;
  v_owner      record;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'only an admin can reject a subscription request' using errcode = '42501';
  end if;

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');

  -- Locked: two admins answering the same request at once must not both see it pending —
  -- that is one payment credited as two terms (found in review).
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

  v_reason := nullif(btrim(p_reason), '');
  if v_reason is null then
    raise exception 'rejection reason is required' using errcode = 'check_violation';
  end if;

  update public.subscription_requests
     set status = 'rejected',
         reject_reason = v_reason,
         reviewed_by = auth.uid(),
         reviewed_at = now()
   where id = p_id;

  for v_owner in
    select uid from public.staff
     where merchant_id = v_req.merchant_id
       and role = 'owner'
       and is_active
  loop
    insert into public.push_outbox (uid, title, body, data, channel)
    values (
      v_owner.uid,
      'طلب الاشتراك اترفض',
      v_reason,
      jsonb_build_object('kind', 'subscription_rejected', 'requestId', p_id::text),
      'orders_critical'
    );
  end loop;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
end;
$$;

revoke execute on function public.reject_subscription_request(uuid, text) from public, anon;
grant execute on function public.reject_subscription_request(uuid, text) to authenticated, service_role;

-- ------------------------------------------------------------------ B. Patch place_order_priced

do $migrate$
declare
  v_src text;
  v_pattern_prepaid constant text := $p$if v_merchant.revenue_model = 'prepaid'
     and v_merchant.wallet_balance - v_merchant.wallet_held < v_merchant.revenue_value then$p$;
  v_replace_prepaid constant text := $p$if not (v_merchant.plan_id is not null and v_merchant.plan_expires_at > now())
     and v_merchant.revenue_model = 'prepaid'
     and v_merchant.wallet_balance - v_merchant.wallet_held < v_merchant.revenue_value then$p$;

  v_pattern_revenue constant text := $p$select jsonb_build_object(
           'model', v_merchant.revenue_model,
           'value', v_merchant.revenue_value,
           'amount', 0
     ) into v_revenue;$p$;
  v_replace_revenue constant text := $p$select case
           when v_merchant.plan_id is not null and v_merchant.plan_expires_at > now() then
             jsonb_build_object('model', 'subscription', 'value', 0, 'amount', 0)
           else
             jsonb_build_object('model', v_merchant.revenue_model, 'value', v_merchant.revenue_value, 'amount', 0)
         end into v_revenue;$p$;
begin
  select prosrc into strict v_src from pg_proc
   where oid = 'public.place_order_priced(jsonb)'::regprocedure;

  if (length(v_src) - length(replace(v_src, v_pattern_prepaid, ''))) / length(v_pattern_prepaid) <> 1 then
    raise exception 'place_order_priced prepaid pattern did not match exactly once';
  end if;

  if (length(v_src) - length(replace(v_src, v_pattern_revenue, ''))) / length(v_pattern_revenue) <> 1 then
    raise exception 'place_order_priced revenue pattern did not match exactly once';
  end if;

  v_src := replace(v_src, v_pattern_prepaid, v_replace_prepaid);
  v_src := replace(v_src, v_pattern_revenue, v_replace_revenue);

  execute format(
    'create or replace function public.place_order_priced(p_draft jsonb) '
    'returns jsonb language plpgsql security definer set search_path = '''' as %L',
    v_src);
end;
$migrate$;

-- ------------------------------------------------------------------ C. Reminders & pg_cron

alter table public.subscriptions
  add column if not exists reminded_at timestamptz;

comment on column public.subscriptions.reminded_at is
  'When the merchant and admins were reminded that this term is ending. Null until sent.';

create or replace function public.remind_expiring_subscriptions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prior_mode text;
  v_count      integer := 0;
  v_rec        record;
  v_date_str   text;
  v_owner      record;
  v_admin      record;
begin
  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');

  for v_rec in
    with latest_subs as (
      select distinct on (s.merchant_id)
             s.id as subscription_id,
             s.merchant_id,
             s.plan_id,
             s.expires_at,
             s.reminded_at
        from public.subscriptions s
       order by s.merchant_id, s.expires_at desc, s.created_at desc
    )
    select ls.subscription_id,
           ls.merchant_id,
           ls.plan_id,
           p.name as plan_name,
           m.name as merchant_name,
           m.plan_expires_at
      from public.merchants m
      join latest_subs ls on ls.merchant_id = m.id
      left join public.plans p on p.id = ls.plan_id
     where m.plan_expires_at between now() and (now() + interval '3 days')
       and ls.reminded_at is null
  loop
    v_date_str := to_char(v_rec.plan_expires_at at time zone 'Africa/Cairo', 'DD/MM/YYYY');

    -- Push to active owner(s)
    for v_owner in
      select uid from public.staff
       where merchant_id = v_rec.merchant_id
         and role = 'owner'
         and is_active
    loop
      insert into public.push_outbox (uid, title, body, data, channel)
      values (
        v_owner.uid,
        'اشتراكك هيخلص قريب',
        'باقة ' || coalesce(v_rec.plan_name, v_rec.plan_id) || ' بتخلص يوم ' || v_date_str || '. جدّد عشان متدفعش عمولة.',
        jsonb_build_object('kind', 'subscription_expiring', 'merchantId', v_rec.merchant_id::text, 'subscriptionId', v_rec.subscription_id::text),
        'orders_critical'
      );
    end loop;

    -- Push to active platform admin(s)
    for v_admin in
      select uid from public.staff
       where scope = 'platform'
         and role = 'admin'
         and is_active
    loop
      insert into public.push_outbox (uid, title, body, data, channel)
      values (
        v_admin.uid,
        'اشتراك هيخلص قريب',
        v_rec.merchant_name || ' — ' || v_date_str,
        jsonb_build_object('kind', 'subscription_expiring', 'merchantId', v_rec.merchant_id::text, 'subscriptionId', v_rec.subscription_id::text),
        'orders_critical'
      );
    end loop;

    update public.subscriptions
       set reminded_at = now()
     where id = v_rec.subscription_id;

    v_count := v_count + 1;
  end loop;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
  return v_count;
end;
$$;

revoke execute on function public.remind_expiring_subscriptions() from public, anon, authenticated;
grant execute on function public.remind_expiring_subscriptions() to service_role;

do $body$
declare
  v_cron boolean;
begin
  select count(*) > 0 into v_cron
    from pg_available_extensions
   where name = 'pg_cron';

  if v_cron then
    create extension if not exists pg_cron;

    perform cron.unschedule('luqma-remind-expiring-subscriptions')
      where exists (select 1 from cron.job where jobname = 'luqma-remind-expiring-subscriptions');
    perform cron.schedule('luqma-remind-expiring-subscriptions', '0 8 * * *',
      'select public.remind_expiring_subscriptions()');
  end if;
end;
$body$;

-- ------------------------------------------------------------------ D. admin_subscriptions

create or replace function public.admin_subscriptions()
returns table(
  merchant_id        uuid,
  merchant_name      text,
  merchant_type      text,
  plan_id            text,
  plan_name          text,
  plan_expires_at    timestamptz,
  revenue_model      text,
  revenue_value      int,
  pending_request_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prior_mode text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'only an admin can view admin_subscriptions' using errcode = '42501';
  end if;

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);

  return query
  select m.id,
         m.name,
         m.type,
         m.plan_id,
         p.name,
         m.plan_expires_at,
         m.revenue_model,
         m.revenue_value,
         sr.id
    from public.merchants m
    left join public.plans p on p.id = m.plan_id
    left join public.subscription_requests sr
      on sr.merchant_id = m.id and sr.status = 'pending'
   order by m.plan_expires_at desc nulls last, m.name asc;
end;
$$;

revoke execute on function public.admin_subscriptions() from public, anon;
grant execute on function public.admin_subscriptions() to authenticated, service_role;
