alter table public.push_outbox
  add column claimed_at timestamptz,
  add column claim_token uuid,
  add constraint push_outbox_claim_pair
    check ((claimed_at is null) = (claim_token is null));

-- Fifteen cron ticks recover a crashed worker quickly, while a full twenty-row batch
-- still gets roughly forty-five seconds per row before an ordinary slow send can be
-- stolen by the next drain.
--
-- The clock-dependent half cannot live in a partial-index predicate because PostgreSQL
-- requires those expressions to be immutable. Keeping it in the key lets the drain
-- reject live leases while the partial predicate still excludes the sent and exhausted
-- history that would otherwise make this queue grow without bound.
drop index public.push_outbox_pending_idx;
create index push_outbox_pending_idx
  on public.push_outbox (created_at, claimed_at)
  where sent_at is null and attempts < 5;

-- PostgreSQL cannot replace a function when its fixed result columns change.
drop function public.claim_push_batch(integer);

create function public.claim_push_batch(p_limit integer default 20)
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
       and (
         o.claimed_at is null
         or o.claimed_at <= now() - interval '15 minutes'
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

drop function public.settle_push(uuid, text, text[]);

create function public.settle_push(
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
           claim_token = null
     where id = p_id
       and claim_token = p_claim_token
    returning uid into v_uid;
  else
    update public.push_outbox
       set last_error = p_error,
           claimed_at = null,
           claim_token = null
     where id = p_id
       and claim_token = p_claim_token
    returning uid into v_uid;
  end if;

  -- A late completion is an expected consequence of crash recovery, so it is a silent
  -- no-op rather than an exception that turns a healthy drain into a failed cron run.
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

revoke all on function public.claim_push_batch(integer) from public, anon, authenticated;
revoke all on function public.settle_push(uuid, uuid, text, text[])
  from public, anon, authenticated;
