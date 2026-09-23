-- SNAPSHOT of public.claim_push_batch as it runs — written by snapshot-functions.mjs.
-- Documentation only: never applied. Change it with a migration.

CREATE OR REPLACE FUNCTION public.claim_push_batch(p_limit integer DEFAULT 20)
 RETURNS TABLE(id uuid, claim_token uuid, tokens text[], title text, body text, data jsonb, channel text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- An order update half an hour old is not news; retire it rather than send it.
  update public.push_outbox o
     set attempts = 5,
         last_error = 'too late to be news'
   where o.sent_at is null
     and o.attempts < 5
     and o.data ->> 'kind' = 'orderStatus'
     and o.created_at < now() - interval '30 minutes';

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
     -- The alarm, then the customer's order update, then the offer; oldest first within
     -- each. Anything the check constraint does not name sorts with marketing rather than
     -- ahead of an alarm.
     order by case o.channel
                when 'orders_critical' then 0
                when 'orders' then 1
                else 2
              end,
              o.created_at
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
$function$;
