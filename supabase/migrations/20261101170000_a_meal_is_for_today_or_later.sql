-- A kitchen publishes a meal for today or a day to come, never for one already over (C5).
--
-- A phone left open past midnight published its morning meal dated the day before, and
-- nothing refused it: the kitchen's write policy and the column guard do not look at the
-- date. The meal existed and the cook saw it, while every customer's today-only query
-- (`date` is a day key, compared by equality) passed it by. The app now dates a meal at
-- the moment it is published; this is the same rule where a stale or hand-written request
-- cannot talk its way past it.
--
-- On insert, from a client only. Server mode and the service role pass — seeds, tests
-- and any server path keep their freedom — and an existing row is left alone: yesterday's
-- meal being edited today is a correction, not a new publication.

create or replace function public.a_meal_is_for_today_or_later()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  if coalesce(pg_catalog.current_setting('role', true), '') = 'authenticated'
     and coalesce(pg_catalog.current_setting('app.server_mode', true), '') <> 'on'
     and new.date < (pg_catalog.now() at time zone 'Africa/Cairo')::date then
    raise exception 'a meal is published for today or later' using errcode = 'check_violation';
  end if;
  return new;
end;
$fn$;

revoke all on function public.a_meal_is_for_today_or_later() from public, anon, authenticated;

drop trigger if exists daily_meals_for_today_or_later on public.daily_meals;
create trigger daily_meals_for_today_or_later
  before insert on public.daily_meals
  for each row execute function public.a_meal_is_for_today_or_later();
