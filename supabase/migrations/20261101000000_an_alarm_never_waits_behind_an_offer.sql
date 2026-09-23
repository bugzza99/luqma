-- An order alarm never waits behind a marketing campaign.
--
-- Every notification in the product sits in one queue, `push_outbox`, and the drain took
-- it strictly oldest first: `send-push` claims twenty rows once a minute. That was right
-- while every row was operational. It stopped being right when `send_promotion_push`
-- arrived, because a campaign writes **one row per customer in the city** on the
-- `marketing` channel. A campaign at 19:00 queues about fifteen hundred rows; the
-- merchant's alarm for an order placed at 19:02 is row fifteen hundred and one, and at
-- twenty a minute it rings at about a quarter past eight. The accept deadline is five
-- minutes. `escalate_unanswered_orders` moves the order to `needsAttention`, the customer
-- waits, and the phone in the kitchen never rang — on exactly the evenings the owner is
-- spending money to bring customers in.
--
-- The fix is priority, not a second queue. The channel already says how urgent a row is —
-- it is what Android separates them by — so the claim takes `orders_critical` first, then
-- `orders`, then `marketing`. `created_at` still orders rows *within* a channel: two alarms
-- are two shops waiting, and the one that has waited longer is the one nearer its deadline;
-- and a campaign goes out in the order it was written, as before.
--
-- **No cap on marketing's share of a batch, deliberately.** A cap would only ever take a
-- slot from marketing while an operational row is due and unclaimed — and under strict
-- priority that row has already been taken ahead of every offer, so there is nothing for
-- the cap to protect. The slots marketing receives are the ones nobody operational wanted
-- this minute. What a cap *would* do is leave those slots empty, so a campaign drains more
-- slowly for no one's benefit. Nor does a full marketing batch delay an alarm written a
-- moment later: each cron run is its own `pg_net` call and its own claim, so the next
-- minute's drain takes the alarm first whether or not this one is still sending offers.
-- A row a concurrent drain holds (`skip locked`) or one waiting out its backoff
-- (`next_attempt_at`) is not due for this claim, and marketing is not held back by it.
--
-- No starvation either: when nothing operational is due, marketing drains at the full
-- batch size, exactly as it did before.
--
-- **No new index.** `push_outbox_pending_idx` (`created_at, claimed_at`, partial on
-- `sent_at is null and attempts < 5`) still narrows the scan to the rows still waiting,
-- and sorting that set by channel is a top-N sort over at most one campaign's worth of
-- rows once a minute — an index ordered by channel would add a write to every
-- notification queued in the city to save a sort nobody waits on.
--
-- Everything else is `20261026000000_a_notification_waits_for_a_phone.sql` unchanged: the
-- lease (`claimed_at`, `claim_token`), `next_attempt_at`, `attempts < 5`,
-- `for update skip locked`, the token lookup, the grants.

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
$$;

revoke all on function public.claim_push_batch(integer) from public, anon, authenticated;
grant execute on function public.claim_push_batch(integer) to service_role;
