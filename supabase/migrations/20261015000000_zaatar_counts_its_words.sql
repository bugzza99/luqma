-- «زعتر», the complaints assistant, counts its words.
--
-- Free-tier abuse limit: a customer may exchange up to 40 turns with the assistant per
-- Cairo day. Beyond 40 turns, the Edge Function returns 429 {"fallback": true} and the
-- app falls back to the deterministic, rule-based OrderHelper.
--
-- RLS is enabled and forced. No client read or write is granted on `zaatar_usage`;
-- interaction happens solely through the security-definer function `zaatar_take_turn()`,
-- granted to authenticated callers only.

create table if not exists public.zaatar_usage (
  uid   uuid not null references auth.users(id) on delete cascade,
  day   date not null,
  count integer not null default 1 check (count >= 1),
  primary key (uid, day)
);

comment on table public.zaatar_usage is
  'Counts complaints-assistant turns per customer per Cairo day to keep free-tier costs bounded.';

alter table public.zaatar_usage enable row level security;
alter table public.zaatar_usage force row level security;
revoke all on public.zaatar_usage from public, anon, authenticated;

-- Increments today's Cairo day turn count for auth.uid() and returns whether the turn is allowed
-- (true for up to 40 turns per day, false once the cap is exceeded).
create or replace function public.zaatar_take_turn()
returns boolean
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_today date;
  v_count integer;
begin
  if v_uid is null then
    return false;
  end if;

  v_today := (now() at time zone 'Africa/Cairo')::date;

  insert into public.zaatar_usage (uid, day, count)
  values (v_uid, v_today, 1)
  on conflict (uid, day) do update
    set count = public.zaatar_usage.count + 1
  returning count into v_count;

  return v_count <= 40;
end;
$fn$;

comment on function public.zaatar_take_turn() is
  'Increments today''s (Cairo day) turn count for auth.uid() and returns false above 40 turns per day.';

revoke execute on function public.zaatar_take_turn() from public, anon;
grant execute on function public.zaatar_take_turn() to authenticated;

-- ------------------------------------------------------------------ and forgets them

-- One row per customer per day, on a free-tier 500 MB database, for a number that is
-- worthless the moment the Cairo day it counts is over. Nothing reads a row older than
-- today, so nothing keeps one: the same lesson as `push_outbox`, where a queue with no
-- prune grows for ever behind a feature that works perfectly.
--
-- Sixty days rather than two, because the only other reader is a person asking how much
-- «زعتر» was used last month, and that answer is cheap to keep.
create or replace function public.prune_zaatar_usage()
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_removed integer;
begin
  delete from public.zaatar_usage
   where day < (now() at time zone 'Africa/Cairo')::date - 60;
  get diagnostics v_removed = row_count;
  return v_removed;
end;
$fn$;

comment on function public.prune_zaatar_usage() is
  'Deletes zaatar_usage rows older than 60 Cairo days. Runs on the nightly cron; no client may call it.';

revoke execute on function public.prune_zaatar_usage() from public, anon, authenticated;

-- PGlite has no pg_cron and a bare `cron.schedule` there fails the whole migration, so
-- the schedule is guarded exactly as every other job in this repository is.
--
-- The nightly job it joins is the one from `20260824130000_scheduled_jobs.sql`, restated
-- in full: pg_cron holds a command, not a list, so adding a statement means rewriting the
-- command. Both run in one transaction — if the billing pass fails, the prune is rolled
-- back with it, which is the right way round for a delete.
do $body$
declare
  v_cron boolean;
begin
  select count(*) > 0 into v_cron
    from pg_available_extensions
   where name = 'pg_cron';

  if v_cron then
    perform cron.unschedule('luqma-nightly-billing')
      where exists (select 1 from cron.job where jobname = 'luqma-nightly-billing');
    perform cron.schedule('luqma-nightly-billing', '0 3 * * *',
      'select public.downgrade_expired_subscriptions(); select public.prune_zaatar_usage();');
  end if;
end;
$body$;
