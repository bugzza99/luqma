-- A notification leaves within seconds, not within the minute.
--
-- `luqma-send-push` ran once a minute, so a new order's alarm waited up to sixty seconds
-- in `push_outbox` before FCM heard of it — forty-two for the test order on 2026-09-24 —
-- and the owner reported notifications as very slow. pg_cron 1.5+ takes a seconds
-- schedule; the drain now runs every five seconds.
--
-- It calls the Edge Function only when a row is due. Every tick calling it would be
-- 17,280 invocations a day against a free tier of 500,000 a month; guarded, the function
-- runs about once per notification, as before. The condition is the same one
-- `claim_push_batch` claims by, less the lease — a leased row being sent right now is not
-- a reason to call again, and one whose lease ran out is picked up on the next tick.
--
-- pg_cron logs a row per run in `cron.job_run_details`; at 17,280 a day that grows without
-- bound, so `luqma-prune-cron-runs` keeps three days of it, every night.
--
-- Guarded on pg_cron like every schedule here: PGlite has none.

do $migrate$
declare v_cron boolean;
begin
  select count(*) > 0 into v_cron from pg_available_extensions where name = 'pg_cron';
  if not v_cron then return; end if;

  perform cron.unschedule('luqma-send-push')
    where exists (select 1 from cron.job where jobname = 'luqma-send-push');

  perform cron.schedule('luqma-send-push', '5 seconds', $c$
    select net.http_post(
      url := e.url || '/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', e.secret
      ),
      body := '{}'::jsonb
    )
      from public.push_endpoint() e
     where e.url is not null and e.secret is not null
       and exists (
         select 1 from public.push_outbox o
          where o.sent_at is null
            and o.attempts < 5
            and coalesce(o.next_attempt_at, o.created_at) <= now()
            and (o.claimed_at is null or o.claimed_at <= now() - interval '10 minutes'))
  $c$);

  perform cron.unschedule('luqma-prune-cron-runs')
    where exists (select 1 from cron.job where jobname = 'luqma-prune-cron-runs');

  perform cron.schedule('luqma-prune-cron-runs', '17 3 * * *', $c$
    delete from cron.job_run_details where end_time < now() - interval '3 days'
  $c$);
end;
$migrate$;
