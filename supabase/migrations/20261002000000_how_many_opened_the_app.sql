-- Active users per app, counted by devices and accounts over day, week, month.
--
-- The owner wants active users for today, the last 7 days and the last 30 days, per app
-- ('customer', 'merchant'), counted two ways: devices (installs, signed in or not) and
-- accounts (signed-in users).
--
-- Table public.app_opens:
-- - day: the day in Africa/Cairo.
-- - app: 'customer' or 'merchant'.
-- - device_id: client install uuid.
-- - uid: signed-in user uuid (null for unsigned-in device opens).
-- - primary key: (day, app, device_id).
-- - RLS on, no client policies at all (nobody reads or writes it directly).

create table public.app_opens (
  day        date not null,
  app        text not null check (app in ('customer', 'merchant')),
  device_id  uuid not null,
  uid        uuid references auth.users on delete set null,
  first_at   timestamptz not null default now(),
  last_at    timestamptz not null default now(),
  primary key (day, app, device_id)
);

create index app_opens_app_day_idx on public.app_opens (app, day);

alter table public.app_opens enable row level security;
alter table public.app_opens force row level security;

comment on table public.app_opens is
  'Daily app opens per device and account. Unreadable and unwriteable directly by clients; '
  'written via record_app_open and read via admin_active_users.';

-- Records an app open from a handset.
--
-- An open is recorded once per device per day however many times it is called.
-- A later signed-in call on the same day updates uid via coalesce(excluded.uid, app_opens.uid).
-- It must never take a uid from a parameter; auth.uid() is the authority.
create or replace function public.record_app_open(
  p_app       text,
  p_device_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_today date;
  v_uid   uuid := auth.uid();
begin
  if p_app is null or p_app not in ('customer', 'merchant') then
    raise exception 'unknown app: %', p_app using errcode = '22023';
  end if;

  if p_device_id is null then
    raise exception 'device_id is required' using errcode = '22023';
  end if;

  v_today := (now() at time zone 'Africa/Cairo')::date;

  insert into public.app_opens (day, app, device_id, uid, first_at, last_at)
  values (v_today, p_app, p_device_id, v_uid, now(), now())
  on conflict (day, app, device_id) do update
    set last_at = now(),
        uid     = coalesce(excluded.uid, public.app_opens.uid);
end;
$fn$;

revoke execute on function public.record_app_open(text, uuid) from public;
grant execute on function public.record_app_open(text, uuid) to anon, authenticated, service_role;

-- Reports active users for today, the last 7 days and the last 30 days per app.
--
-- Periods:
-- - 'day': today (Cairo).
-- - 'week': today and the 6 days before (7 days total).
-- - 'month': today and the 29 days before (30 days total).
--
-- Returns a row for every (app, period) pair even when the count is 0.
create or replace function public.admin_active_users()
returns table(
  app      text,
  period   text,
  devices  bigint,
  accounts bigint
)
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_today date;
begin
  if not public.is_admin() then
    raise exception 'insufficient privilege' using errcode = 'insufficient_privilege';
  end if;

  v_today := (now() at time zone 'Africa/Cairo')::date;

  return query
  with targets as (
    select t.app, p.period, p.ord, p.days_back
      from (values ('customer'), ('merchant')) as t(app)
      cross join (values ('day', 1, 0), ('week', 2, 6), ('month', 3, 29)) as p(period, ord, days_back)
  )
  select tg.app,
         tg.period,
         coalesce(count(distinct ao.device_id), 0)::bigint as devices,
         coalesce(count(distinct ao.uid), 0)::bigint as accounts
    from targets tg
    left join public.app_opens ao
      on ao.app = tg.app
     and ao.day between (v_today - tg.days_back) and v_today
   group by tg.app, tg.period, tg.ord
   order by tg.app, tg.ord;
end;
$fn$;

revoke execute on function public.admin_active_users() from public, anon;
grant execute on function public.admin_active_users() to authenticated, service_role;
