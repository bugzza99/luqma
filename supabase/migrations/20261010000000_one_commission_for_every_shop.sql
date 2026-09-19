-- One commission for every shop, collected weekly, and a warning when it runs high.
--
-- The owner's decisions of 2026-09-19:
--   * one rate for every shop, set in «الإعدادات», starting at 5%; a shop can be given its
--     own rate when the owner agrees one with it;
--   * collected in cash once a week, the owner recording it;
--   * above 500 ج owed, the shop and the owner are told — the owner decides what happens.
--
-- And one thing found on the way: a shop whose revenue model said 'subscription' paid no
-- commission once its plan lapsed, because an order is charged by the model on the row
-- whenever no plan is active. A plan already *is* the monthly amount (20261003000000), so
-- the model underneath it is what applies when there is no plan — and the owner's rule is
-- that a lapsed plan goes back to commission. Those rows become commission.

-- ------------------------------------------------------------------ which shops follow the rate

alter table public.merchants
  add column if not exists commission_custom boolean not null default false;

comment on column public.merchants.commission_custom is
  'True when the owner agreed this shop''s own rate. False follows the one rate in config '
  '(default_commission_percent), and changing that rate changes this shop''s too.';

-- ------------------------------------------------------------------ the policy, in config

insert into public.config (key, value) values
  ('default_commission_percent', '5'::jsonb),
  ('commission_alert_pounds', '500'::jsonb)
on conflict (key) do nothing;

create or replace function public.default_commission_bps()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select round((value #>> '{}')::numeric * 100)::integer
       from public.config where key = 'default_commission_percent'),
    0);
$$;

create or replace function public.commission_alert_piastres()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select round((value #>> '{}')::numeric * 100)::integer
       from public.config where key = 'commission_alert_pounds'),
    50000);
$$;

revoke all on function public.default_commission_bps() from public, anon;
revoke all on function public.commission_alert_piastres() from public, anon;
grant execute on function public.default_commission_bps() to authenticated, service_role;
grant execute on function public.commission_alert_piastres() to authenticated, service_role;

-- A new shop starts on the one rate, whoever made it — approval, the admin's own form.
create or replace function public.merchants_start_on_the_rate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Shared with every other new shop, exclusive against a change of the rate: a shop made
  -- while the owner changes the rate must not commit on the old one, unseen by the change
  -- (Astra's review, 2026-09-19).
  perform pg_catalog.pg_advisory_xact_lock_shared(7201);
  if not new.commission_custom then
    -- A shop created with a rate already written keeps it; one created with none — which is
    -- every shop approval makes — gets the one rate.
    if new.revenue_model = 'subscription' then
      new.revenue_model := 'commission';
      new.revenue_value := public.default_commission_bps();
    elsif new.revenue_model = 'commission' and new.revenue_value = 0 then
      new.revenue_value := public.default_commission_bps();
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists merchants_start_on_the_rate on public.merchants;
create trigger merchants_start_on_the_rate
  before insert on public.merchants
  for each row execute function public.merchants_start_on_the_rate();

-- The owner changes the rate, or the alert, from «الإعدادات». Every shop that follows the
-- rate moves with it in the same transaction — the promise of «نسبة واحدة لكل المحلات».
create or replace function public.admin_set_commission_policy(
  p_percent      numeric,
  p_alert_pounds integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prior text;
  v_moved integer;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'only an admin sets the commission' using errcode = '42501';
  end if;
  if p_percent is null or p_percent < 0 or p_percent > 50 then
    raise exception 'the rate is a percentage from 0 to 50' using errcode = 'check_violation';
  end if;
  if p_alert_pounds is null or p_alert_pounds < 0 or p_alert_pounds > 1000000 then
    raise exception 'the alert is an amount in pounds' using errcode = 'check_violation';
  end if;

  -- Waits for any shop being created to commit, and holds new ones until this commits.
  perform pg_catalog.pg_advisory_xact_lock(7201);

  insert into public.config (key, value) values
    ('default_commission_percent', pg_catalog.to_jsonb(p_percent)),
    ('commission_alert_pounds', pg_catalog.to_jsonb(p_alert_pounds))
  on conflict (key) do update set value = excluded.value, updated_at = now();

  v_prior := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  with moved as (
    update public.merchants
       set revenue_value = round(p_percent * 100)::integer,
           updated_at = now()
     where not commission_custom
       and revenue_model = 'commission'
    returning 1
  )
  select count(*) into v_moved from moved;

  insert into public.audit_log (action, actor, detail)
  values ('setCommissionPolicy', auth.uid(),
          pg_catalog.jsonb_build_object('percent', p_percent, 'alertPounds', p_alert_pounds,
                                        'shopsMoved', v_moved));

  perform pg_catalog.set_config('app.server_mode', v_prior, true);
  return pg_catalog.jsonb_build_object('shopsMoved', v_moved);
end;
$$;

revoke all on function public.admin_set_commission_policy(numeric, integer) from public, anon;
grant execute on function public.admin_set_commission_policy(numeric, integer) to authenticated;

-- A shop's own rate, or back to the one rate. The billing screen's two choices.
create or replace function public.admin_set_shop_commission(
  p_merchant_id uuid,
  p_custom_bps  integer   -- null: follow the one rate
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prior text;
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'only an admin sets a shop''s commission' using errcode = '42501';
  end if;
  if p_custom_bps is not null and (p_custom_bps < 0 or p_custom_bps > 5000) then
    raise exception 'the rate is a percentage from 0 to 50' using errcode = 'check_violation';
  end if;

  v_prior := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  update public.merchants
     set revenue_model = 'commission',
         revenue_value = coalesce(p_custom_bps, public.default_commission_bps()),
         commission_custom = p_custom_bps is not null,
         updated_at = now()
   where id = p_merchant_id;
  if not found then
    perform pg_catalog.set_config('app.server_mode', v_prior, true);
    raise exception 'no such merchant' using errcode = 'P0002';
  end if;

  insert into public.audit_log (action, actor, merchant_id, detail)
  values ('setShopCommission', auth.uid(), p_merchant_id,
          pg_catalog.jsonb_build_object('customBps', p_custom_bps));

  perform pg_catalog.set_config('app.server_mode', v_prior, true);
end;
$$;

revoke all on function public.admin_set_shop_commission(uuid, integer) from public, anon;
grant execute on function public.admin_set_shop_commission(uuid, integer) to authenticated;

-- The shops that exist today: every one follows the rate, and a 'subscription' model goes
-- back to commission (its plan, while active, still means no commission on its orders).
do $$
declare
  v_prior text := coalesce(current_setting('app.server_mode', true), '');
begin
  perform set_config('app.server_mode', 'on', true);
  update public.merchants
     set revenue_model = 'commission',
         revenue_value = public.default_commission_bps()
   where not commission_custom
     and revenue_model in ('commission', 'subscription');
  perform set_config('app.server_mode', v_prior, true);
end;
$$;

-- ------------------------------------------------------------------ told when it runs high

-- Once, as the amount owed crosses the line — not on every order after it, which would be a
-- notification per delivery to somebody who already knows.
create or replace function public.commission_crossed_alert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line  integer := public.commission_alert_piastres();
  v_admin record;
  v_owner record;
  v_body  text;
begin
  if v_line <= 0 or not (old.commission_owed < v_line and new.commission_owed >= v_line) then
    return new;
  end if;

  v_body := new.name || ' — عليه ' || (new.commission_owed / 100) || ' ج عمولة';

  for v_admin in
    select uid from public.staff where scope = 'platform' and role = 'admin' and is_active
  loop
    insert into public.push_outbox (uid, title, body, data, channel)
    values (v_admin.uid, 'عمولة عدّت الحد', v_body,
            pg_catalog.jsonb_build_object('kind', 'commissionDue', 'merchantId', new.id::text),
            'orders');
  end loop;

  for v_owner in
    select uid from public.staff where merchant_id = new.id and role = 'owner' and is_active
  loop
    insert into public.push_outbox (uid, title, body, data, channel)
    values (v_owner.uid, 'عمولة لقمة',
            'عليك ' || (new.commission_owed / 100) || ' ج عمولة. هنكلمك نتفق على ميعاد التحصيل.',
            pg_catalog.jsonb_build_object('kind', 'commissionDue', 'merchantId', new.id::text),
            'orders');
  end loop;

  return new;
end;
$$;

drop trigger if exists merchants_commission_crossed on public.merchants;
create trigger merchants_commission_crossed
  after update of commission_owed on public.merchants
  for each row execute function public.commission_crossed_alert();

-- ------------------------------------------------------------------ the weekly reminder

-- Saturday morning: every shop that owes gets its amount, and the owner gets one message
-- with the count and the total — the list itself is on «اليوم».
create or replace function public.remind_commission_due()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shop   record;
  v_owner  record;
  v_admin  record;
  v_count  integer := 0;
  v_total  bigint := 0;
begin
  for v_shop in
    select id, name, commission_owed from public.merchants where commission_owed > 0
  loop
    v_count := v_count + 1;
    v_total := v_total + v_shop.commission_owed;
    for v_owner in
      select uid from public.staff where merchant_id = v_shop.id and role = 'owner' and is_active
    loop
      insert into public.push_outbox (uid, title, body, data, channel)
      values (v_owner.uid, 'عمولة الأسبوع',
              'عليك ' || (v_shop.commission_owed / 100) || ' ج عمولة لقمة. التفاصيل في «كشف الحساب».',
              pg_catalog.jsonb_build_object('kind', 'commissionDue', 'merchantId', v_shop.id::text),
              'orders');
    end loop;
  end loop;

  if v_count > 0 then
    for v_admin in
      select uid from public.staff where scope = 'platform' and role = 'admin' and is_active
    loop
      insert into public.push_outbox (uid, title, body, data, channel)
      values (v_admin.uid, 'تحصيل العمولة',
              v_count || ' محل عليهم ' || (v_total / 100) || ' ج — القائمة في «اليوم».',
              pg_catalog.jsonb_build_object('kind', 'commissionDue'),
              'orders');
    end loop;
  end if;

  return v_count;
end;
$$;

revoke all on function public.remind_commission_due() from public, anon, authenticated;
grant execute on function public.remind_commission_due() to service_role;

do $body$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule('luqma-remind-commission-due')
      where exists (select 1 from cron.job where jobname = 'luqma-remind-commission-due');
    -- 07:00 UTC is 10:00 in Cairo in summer and 09:00 in winter; either is a working morning.
    perform cron.schedule('luqma-remind-commission-due', '0 7 * * 6',
      'select public.remind_commission_due()');
  end if;
end;
$body$;

-- ------------------------------------------------------------------ guards for every other path

-- An update keeps the same rules as the two functions above, whoever writes it — including
-- an admin handset still carrying an APK from before this policy, which writes the columns
-- directly (Astra's review, 2026-09-19):
--   * 'subscription' is not a model any more: it meant no commission once a plan lapsed.
--   * a rate written directly is a shop's own rate unless it is the one rate, so the next
--     change of the one rate does not overwrite a price the owner agreed with the shop.
-- The two functions above set `commission_custom` themselves; when the flag is changing in
-- the same statement, it is left as they wrote it.
create or replace function public.merchants_keep_to_the_rate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.revenue_model = 'subscription' then
    new.revenue_model := 'commission';
    if not new.commission_custom then
      new.revenue_value := public.default_commission_bps();
    end if;
  end if;
  if new.revenue_model = 'commission'
     and new.revenue_value is distinct from old.revenue_value
     and new.commission_custom is not distinct from old.commission_custom then
    new.commission_custom := new.revenue_value <> public.default_commission_bps();
  end if;
  return new;
end;
$$;

drop trigger if exists merchants_keep_to_the_rate on public.merchants;
create trigger merchants_keep_to_the_rate
  before update of revenue_model, revenue_value on public.merchants
  for each row execute function public.merchants_keep_to_the_rate();

-- The two keys through any door: `admin_set_config` accepts any key an admin sends, so an
-- older AdminApp — or a typo — could write a rate nobody can read, or change the rate
-- without moving the shops that follow it. A value that is not a number in range is
-- refused; a new rate moves the followers, in the same transaction, as the function does.
create or replace function public.config_keeps_commission_sane()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_number numeric;
  v_prior  text;
begin
  if new.key not in ('default_commission_percent', 'commission_alert_pounds') then
    return new;
  end if;
  begin
    v_number := (new.value #>> '{}')::numeric;
  exception when others then
    raise exception '% must be a number', new.key using errcode = 'check_violation';
  end;
  if v_number is null
     or (new.key = 'default_commission_percent' and (v_number < 0 or v_number > 50))
     or (new.key = 'commission_alert_pounds' and (v_number < 0 or v_number > 1000000)) then
    raise exception '% is out of range', new.key using errcode = 'check_violation';
  end if;

  if new.key = 'default_commission_percent'
     and (tg_op = 'INSERT' or new.value is distinct from old.value) then
    perform pg_catalog.pg_advisory_xact_lock(7201);
    v_prior := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
    perform pg_catalog.set_config('app.server_mode', 'on', true);
    update public.merchants
       set revenue_value = round(v_number * 100)::integer
     where not commission_custom
       and revenue_model = 'commission'
       and revenue_value is distinct from round(v_number * 100)::integer;
    perform pg_catalog.set_config('app.server_mode', v_prior, true);
  end if;
  return new;
end;
$$;

drop trigger if exists config_keeps_commission_sane on public.config;
create trigger config_keeps_commission_sane
  after insert or update of value on public.config
  for each row execute function public.config_keeps_commission_sane();
