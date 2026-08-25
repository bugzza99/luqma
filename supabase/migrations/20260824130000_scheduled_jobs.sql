-- Scheduled server work: the accept-deadline escalator and the nightly billing pass.
--
-- Both were Firebase scheduled functions before the migration; on Postgres they are
-- SECURITY DEFINER functions that declare `app.server_mode` - the same declaration the
-- column and transition guards honour - so they move what no client may.
--
-- Scheduling itself is pg_cron's, guarded by availability: PGlite, which runs the local
-- migration suite, has no pg_cron, and a bare `create extension` there would stop every
-- local test before it reached a constraint. On any real Supabase stack the extension is
-- available and both schedules land. The functions stay callable by hand either way,
-- which is exactly how their tests - and an operator at 3am - reach them.

-- ---------------------------------------------------------------- the escalator

-- A merchant who lets the accept deadline pass has said, by silence, that they cannot
-- cook this order. Nobody tells the customer that; someone phones the restaurant. What
-- the flag is for is the admin screen: raise it, name the reason in history, and let a
-- person sort the rest out.
create or replace function public.escalate_unanswered_orders()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_moved integer := 0;
begin
  perform set_config('app.server_mode', 'on', true);

  with moved as (
    update public.orders
       set status = 'needsAttention',
           status_history = status_history || jsonb_build_array(
             jsonb_build_object('from', 'placed',
                                'to', 'needsAttention',
                                'by', 'system',
                                'at', now())),
           updated_at = now()
     where status = 'placed'
       -- Instant orders only: a pre-order has no deadline to run out of.
       and accept_deadline_at is not null
       and accept_deadline_at < now()
    returning 1
  )
  select count(*) into v_moved from moved;

  return v_moved;
end;
$$;

revoke execute on function public.escalate_unanswered_orders()
  from public, anon, authenticated;
grant execute on function public.escalate_unanswered_orders() to service_role;

-- ---------------------------------------------------------------- nightly billing

-- The pass reads every subscription term because whether an expired term still counts
-- depends on whether a LATER renewal exists for the same merchant - a query for expired
-- rows alone would downgrade merchants who had just paid. The group-by answers it:
-- a merchant whose NEWEST term has already ended has stopped paying, whatever the
-- history under it says. (Phase 9 moves the truth onto merchants.planExpiresAt, which
-- makes this bounded as well as correct.)
create or replace function public.downgrade_expired_subscriptions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_downgraded integer := 0;
begin
  perform set_config('app.server_mode', 'on', true);

  with expired as (
    select s.merchant_id
      from public.subscriptions s
     group by s.merchant_id
    having max(s.expires_at) < now()
  ),
  moved as (
    update public.merchants m
       set plan_id = null,
           updated_at = now()
      from expired e
     where m.id = e.merchant_id
       and m.plan_id is not null
    returning 1
  )
  select count(*) into v_downgraded from moved;

  return v_downgraded;
end;
$$;

revoke execute on function public.downgrade_expired_subscriptions()
  from public, anon, authenticated;
grant execute on function public.downgrade_expired_subscriptions() to service_role;

-- ---------------------------------------------------------------- the schedules

do $body$
declare
  v_cron boolean;
begin
  select count(*) > 0 into v_cron
    from pg_available_extensions
   where name = 'pg_cron';

  if v_cron then
    create extension if not exists pg_cron;

    -- Deadlines are minute-scale; the escalator runs every minute.
    perform cron.unschedule('luqma-escalate-unanswered')
      where exists (select 1 from cron.job where jobname = 'luqma-escalate-unanswered');
    perform cron.schedule('luqma-escalate-unanswered', '* * * * *',
      'select public.escalate_unanswered_orders()');

    -- Billing settles once a night.
    perform cron.unschedule('luqma-nightly-billing')
      where exists (select 1 from cron.job where jobname = 'luqma-nightly-billing');
    perform cron.schedule('luqma-nightly-billing', '0 3 * * *',
      'select public.downgrade_expired_subscriptions()');
  end if;
end;
$body$;
