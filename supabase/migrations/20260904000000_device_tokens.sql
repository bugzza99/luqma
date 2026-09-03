-- A push token names one app installation, not one account. Keeping the token as the
-- key makes two owners structurally impossible, which matters on shared merchant phones
-- that change hands between an owner and a courier.
create table public.device_tokens (
  token      text primary key check (btrim(token) <> ''),
  uid        uuid not null references auth.users on delete cascade,
  updated_at timestamptz not null default now()
);

create index device_tokens_uid_idx on public.device_tokens (uid);

alter table public.device_tokens enable row level security;

-- Ownership can move between accounts, so an ordinary per-row policy cannot perform the
-- transfer. The two functions below are the only client doors into this table.
revoke all on public.device_tokens from anon, authenticated;

-- Existing arrays can contain one installation under several accounts. The most recently
-- updated profile is the best evidence available for who used that installation last;
-- the uid tie-breaker only makes equal timestamps deterministic.
insert into public.device_tokens (token, uid, updated_at)
select token, id, updated_at
  from (
    select distinct on (legacy.token)
           legacy.token as token,
           u.id,
           u.updated_at
      from public.users u
      cross join lateral unnest(u.fcm_tokens) as legacy(token)
     where btrim(legacy.token) <> ''
     order by legacy.token, u.updated_at desc, u.id desc
  ) winners;

create or replace function public.register_device_token(p_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  if p_token is null or btrim(p_token) = '' then
    raise exception 'device token must not be empty'
      using errcode = 'invalid_parameter_value';
  end if;

  -- The primary-key conflict is the transfer: concurrent registrations serialize on the
  -- installation row instead of racing through separate reads of an account array.
  insert into public.device_tokens (token, uid, updated_at)
  values (p_token, v_uid, now())
  on conflict (token) do update
    set uid = excluded.uid,
        updated_at = excluded.updated_at;
end;
$$;

create or replace function public.forget_device_token(p_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  -- The owner predicate keeps a late sign-out from deleting an installation that has
  -- already been claimed by the next account on the shared phone.
  delete from public.device_tokens
   where token = p_token
     and uid = v_uid;
end;
$$;

revoke all on function public.register_device_token(text) from public, anon;
revoke all on function public.forget_device_token(text) from public, anon;
grant execute on function public.register_device_token(text) to authenticated;
grant execute on function public.forget_device_token(text) to authenticated;

-- Keep the outbox contract stable while current and already-installed APKs use different
-- token stores. A device row wins over stale array ownership, while UNION keeps duplicate
-- values inside the transitional arrays from ringing one handset twice.
create or replace function public.claim_push_batch(p_limit integer default 20)
returns table (
  id uuid,
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
     where o.sent_at is null and o.attempts < 5
     order by o.created_at
     limit p_limit
     for update skip locked
  ), bumped as (
    update public.push_outbox o
       set attempts = o.attempts + 1
      from claimed
     where o.id = claimed.id
    returning o.*
  )
  select b.id,
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

create or replace function public.settle_push(
  p_id uuid,
  p_error text default null,
  p_dead_tokens text[] default '{}'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_error is null then
    update public.push_outbox set sent_at = now(), last_error = null where id = p_id;
  else
    update public.push_outbox set last_error = p_error where id = p_id;
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
revoke all on function public.settle_push(uuid, text, text[])
  from public, anon, authenticated;
