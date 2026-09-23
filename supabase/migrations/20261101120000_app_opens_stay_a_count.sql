-- The app-open count stays a count, not a free place to put rows (A13).
--
-- `record_app_open` is callable without an account, and must stay so: a customer
-- browsing before signing up is exactly who the owner wants counted. But it took any
-- device uuid, for ever, and nothing removed a row. A loop of random uuids inflated
-- «المستخدمين النشطين» and grew the table without limit on a free-tier database, while
-- the report never reads more than thirty days.
--
-- Two bounds, neither of which a real phone can reach:
--   * a ceiling on *new* devices per app per day — twenty thousand, against a town whose
--     whole population is a fraction of that. Past it, a new device is ignored rather
--     than refused: this is a counter, and a phone has no business reporting an error
--     about it. A device already counted today is still refreshed.
--   * a nightly prune of anything older than ninety days, three times what the report
--     shows, so a month-over-month comparison stays possible.

create or replace function public.app_open_daily_ceiling()
returns integer
language sql
immutable
set search_path = ''
as $fn$ select 20000 $fn$;

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

  -- A new device past the day's ceiling is not counted, and not an error either.
  if not exists (
       select 1 from public.app_opens
        where day = v_today and app = p_app and device_id = p_device_id)
     and (select count(*) from public.app_opens
           where day = v_today and app = p_app) >= public.app_open_daily_ceiling() then
    return;
  end if;

  insert into public.app_opens (day, app, device_id, uid, first_at, last_at)
  values (v_today, p_app, p_device_id, v_uid, now(), now())
  on conflict (day, app, device_id) do update
    set last_at = now(),
        uid     = coalesce(excluded.uid, public.app_opens.uid);
end;
$fn$;

revoke execute on function public.record_app_open(text, uuid) from public;
grant execute on function public.record_app_open(text, uuid) to anon, authenticated, service_role;

-- Everything older than ninety days, which the report cannot show. Returns how many rows
-- went, so the nightly job's history says what it did.
create or replace function public.prune_app_opens()
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_gone integer;
begin
  delete from public.app_opens
   where day < (now() at time zone 'Africa/Cairo')::date - 90;
  get diagnostics v_gone = row_count;
  return v_gone;
end;
$fn$;

revoke execute on function public.prune_app_opens() from public, anon, authenticated;

-- PGlite has no pg_cron, so the schedule is guarded as every other job here is.
do $body$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    perform cron.unschedule('luqma-prune-app-opens')
      where exists (select 1 from cron.job where jobname = 'luqma-prune-app-opens');
    perform cron.schedule('luqma-prune-app-opens', '40 3 * * *',
      'select public.prune_app_opens();');
  end if;
end;
$body$;
