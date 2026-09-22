-- A notification waits for a phone, instead of giving up in five minutes.
--
-- Found on production, not in a review: seven rows in `push_outbox` were dead-lettered,
-- and all seven carried the same `last_error` — `no tokens`. Five of them were from one
-- day: four «طلب انضمام جديد» and one «طلب اشتراك جديد», all addressed to the owner.
-- Every recipient has a registered device *now*. They simply had none at the moment the
-- message was written.
--
-- Nothing was lost — the applications are still in the queue, and the owner reads them on
-- a screen. What was lost is being told at the time, and the day it happened was the day
-- before a real merchant applied, was approved, and vanished.
--
-- The cause is two halves that disagree. `send-push` settles a recipient with no device
-- as an error and says so in a comment — "Settled rather than retried: five attempts
-- against an account with no phone is five minutes of nothing" — but `settle_push` with
-- an error only records the error and releases the claim. It never sets `sent_at`. So the
-- row is claimed again on the next minute's cron, five times, and dies about five minutes
-- after it was written. **Somebody who installs the app an hour later is never reached.**
--
-- The comment's own reasoning is what is wrong, not only the code. Five attempts against
-- an account with no phone is five minutes of nothing *because the attempts are a minute
-- apart* — the number of attempts was never the problem, the spacing was.
--
-- So attempts get spread out instead of being spent at once: roughly two minutes, ten
-- minutes, an hour, then six hours. The same five attempts now span about seven hours,
-- which covers an owner who registers their phone that evening, and covers a transient
-- FCM failure far better than four more tries in the same four minutes did.
--
-- Bounded on purpose. A notification is about something that was true when it was
-- written; «أوردرك اتقبل» arriving on Thursday for Monday's order is worse than silence.
-- Seven hours is long enough for a phone to appear and short enough that nothing stale
-- ever lands.

alter table public.push_outbox
  add column if not exists next_attempt_at timestamptz;

comment on column public.push_outbox.next_attempt_at is
  'When this row may be claimed again after a failure. Null means now (or never tried). '
  'Set by settle_push with a backoff, so five attempts span hours rather than minutes — '
  'a recipient with no registered device yet is the case this exists for.';

-- Deliberately not in the partial index. `now()` is not immutable, so the predicate keeps
-- only what is constant — the same reason the lease's ten-minute expiry stays in the
-- query. The index still narrows to the rows worth scanning and this filters within them.
create index if not exists push_outbox_next_attempt_idx
  on public.push_outbox (next_attempt_at)
  where sent_at is null and attempts < 5;

create or replace function public.claim_push_batch(p_limit integer default 20)
returns table (
  id uuid,
  claim_token uuid,
  tokens text[],
  title text,
  body text,
  data jsonb,
  channel text
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  return query
  with claimed as (
    select o.id
      from public.push_outbox o
     where o.sent_at is null
       and o.attempts < 5
       -- A row that failed is not due yet. Null covers both a row never tried and every
       -- row written before this column existed, which must stay claimable.
       and coalesce(o.next_attempt_at, o.created_at) <= now()
       and (
         o.claimed_at is null
         or o.claimed_at <= now() - interval '10 minutes'
       )
     order by o.created_at
     limit p_limit
     for update skip locked
  ), bumped as (
    update public.push_outbox o
       set attempts = o.attempts + 1,
           claimed_at = now(),
           claim_token = gen_random_uuid()
      from claimed
     where o.id = claimed.id
    returning o.*
  )
  select b.id,
         b.claim_token,
         array(
           select source.token
             from (
               select d.token
                 from public.device_tokens d
                where d.uid = b.uid
               union
               -- Transitional until every installed APK has moved off users.fcm_tokens;
               -- removing this half sooner would make an old app silently unreachable.
               select legacy.token
                 from public.users u
                 cross join lateral unnest(u.fcm_tokens) as legacy(token)
                where u.id = b.uid
                  -- Once an updated app claims an installation, that row is authoritative;
                  -- otherwise a stale array under the previous account recreates the bug.
                  and not exists (
                    select 1
                      from public.device_tokens owner
                     where owner.token = legacy.token
                  )
             ) source
            order by source.token
         ),
         b.title,
         b.body,
         b.data,
         b.channel
    from bumped b;
end;
$$;

revoke all on function public.claim_push_batch(integer) from public, anon, authenticated;
grant execute on function public.claim_push_batch(integer) to service_role;

-- How long a failed row waits, by how many times it has been tried.
--
-- A function rather than a `case` inside `settle_push` so the schedule can be read, and
-- argued with, in one place — and so the test can assert the shape rather than the
-- arithmetic being restated in it.
create or replace function public.push_retry_delay(p_attempts integer)
returns interval
language sql
immutable
set search_path = ''
as $fn$
  select case
    when p_attempts <= 1 then interval '2 minutes'
    when p_attempts = 2  then interval '10 minutes'
    when p_attempts = 3  then interval '1 hour'
    else                      interval '6 hours'
  end;
$fn$;

comment on function public.push_retry_delay(integer) is
  'The gap before a failed push is tried again. Five attempts span about seven hours, '
  'which is what makes a recipient who registers a device later still reachable.';

create or replace function public.settle_push(
  p_id uuid,
  p_claim_token uuid,
  p_error text default null,
  p_dead_tokens text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
begin
  if p_error is null then
    update public.push_outbox
       set sent_at = now(),
           last_error = null,
           claimed_at = null,
           claim_token = null,
           next_attempt_at = null
     where id = p_id
       and claim_token = p_claim_token
    returning uid into v_uid;
  else
    update public.push_outbox
       set last_error = p_error,
           claimed_at = null,
           claim_token = null,
           -- Computed from the attempt just spent, so the wait grows with each failure
           -- rather than the row coming straight back on the next minute's cron.
           next_attempt_at = now() + public.push_retry_delay(attempts)
     where id = p_id
       and claim_token = p_claim_token
    returning uid into v_uid;
  end if;

  -- Unchanged from the original, and deliberately so: a late completion is an expected
  -- consequence of crash recovery, so a superseded claim is a silent no-op rather than an
  -- exception that turns a healthy drain into a failed cron run.
  if v_uid is null then
    return;
  end if;

  if array_length(p_dead_tokens, 1) > 0 then
    -- FCM invalidates an installation, not one account's copy of it. Removing every
    -- legacy copy as well prevents the same dead handset returning through another uid.
    delete from public.device_tokens where token = any(p_dead_tokens);

    update public.users
       set fcm_tokens = array(
             select token
               from unnest(fcm_tokens) as token
              where not (token = any(p_dead_tokens))
           )
     where fcm_tokens && p_dead_tokens;
  end if;
end;
$$;

revoke all on function public.settle_push(uuid, uuid, text, text[])
  from public, anon, authenticated;
grant execute on function public.settle_push(uuid, uuid, text, text[]) to service_role;
