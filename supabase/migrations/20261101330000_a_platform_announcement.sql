-- The platform can send a notification of its own, and it reaches the city.
--
-- The owner reported, 2026-09-24, that a campaign push "does not work at all", and that it
-- should not need a shop. Two faults behind that:
--
--   * A push reached only customers with a saved address in the city, because an address
--     is how a customer's city was known. Somebody who installed the app and has not
--     ordered yet has none — the very person a welcome message is for. On production that
--     was two customers in three, and the owner's own test phones.
--   * `promotions.merchant_id` was required, so the owner could not announce anything as
--     Luqma itself.
--
-- A push may name no shop now; every other channel still belongs to one (a banner links
-- to a shop, a boost ranks one). A whole-city push reaches a customer with no address
-- while there is only one city to belong to. The day a second city opens, that stops by
-- itself — an Edku announcement must not reach a stranger — and a city on the account is
-- what would replace it. Staff accounts are never sent one: their apps create no
-- `marketing` channel, and an offer would fall back to the kitchen's alarm.
--
-- The payload's `merchantId` is an empty string rather than JSON null: FCM data values are
-- strings, and `send-push` would turn null into the word "null", which the app would try
-- to open as a shop.

alter table public.promotions alter column merchant_id drop not null;
alter table public.promotions
  add constraint promotions_merchant_unless_platform_push
    check (merchant_id is not null or channel = 'push');

create or replace function public.send_promotion_push()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_promotion record;
  v_limit     integer;
  v_queued    integer := 0;
  v_rows      integer;
  v_one_city  boolean;
begin
  -- The cap is the city's, and it is read here rather than taken as an argument for the
  -- same reason the audit gave for `record_subscription_payment`: a limit the caller
  -- supplies is a limit the caller can raise.
  select coalesce((value #>> '{}')::integer, 0) into v_limit
    from public.config where key = 'marketing_push_per_week';
  v_limit := coalesce(v_limit, 0);

  -- An account carries no city. While there is only one, an account with no address yet
  -- can only belong to it; once there are two, it could belong to either.
  v_one_city := (select count(*) from public.cities) = 1;

  for v_promotion in
    select id, city_id, merchant_id, title, body, zone_ids
      from public.promotions
     where channel = 'push'
       and status = 'approved'
       and pushed_at is null
       and start_at <= now()
       and end_at > now()
     -- Oldest first, so a backlog is worked through in the order the admin approved it
     -- rather than in whatever order the planner returns.
     order by start_at
     for update skip locked
  loop
    -- Re-checked per promotion rather than once: each send consumes a slot, so two
    -- approved campaigns going live in the same minute must not both get through a cap
    -- of one.
    if not public.push_slot_available(v_promotion.city_id, v_limit) then
      exit;
    end if;

    insert into public.push_outbox (uid, title, body, data, channel)
    select u.id,
           v_promotion.title,
           v_promotion.body,
           pg_catalog.jsonb_build_object(
             'kind', 'promotion',
             'promotionId', v_promotion.id::text,
             -- Empty for the platform's own announcement; see the header.
             'merchantId', coalesce(v_promotion.merchant_id::text, '')
           ),
           'marketing'
      from public.users u
     where u.marketing_push
       and not u.is_blocked
       -- A staff account's app has no marketing channel; the offer would ring its alarm.
       and not exists (select 1 from public.staff s where s.uid = u.id)
       and (
         -- The city is the floor, and an empty `zone_ids` narrows to nothing *within* it.
         -- Reading the empty array as "no filter at all" would send an Edku restaurant's
         -- offer to every customer in every city this product ever serves.
         exists (
           select 1
             from public.addresses a
             join public.zones z on z.id = a.zone_id
            where a.user_id = u.id
              and z.city_id = v_promotion.city_id
              and (
                v_promotion.zone_ids = '{}'::uuid[]
                or a.zone_id = any(v_promotion.zone_ids)
              )
         )
         -- A customer with no address yet, for a whole-city push, while one city is all
         -- there is to belong to.
         or (v_one_city
             and v_promotion.zone_ids = '{}'::uuid[]
             and not exists (select 1 from public.addresses a where a.user_id = u.id))
       );

    get diagnostics v_rows = row_count;
    v_queued := v_queued + v_rows;

    -- Stamped whether or not anybody was queued. A campaign that reached nobody has
    -- still had its turn; leaving it null would make it a candidate again on the next
    -- pass, for ever.
    update public.promotions set pushed_at = now() where id = v_promotion.id;
  end loop;

  return v_queued;
end;
$function$;
