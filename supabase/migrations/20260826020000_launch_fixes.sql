-- Launch fixes from the pre-launch audit, round two.
--
-- One file rather than five on purpose: these fixes belong to the same audit pass, and
-- each patch here is a `create or replace` (idempotent) or a guarded `do` block, so
-- they re-apply cleanly and read as one story — the server tightening what the first
-- audit round left open.

-- ---------------------------------------------------------------- C2: a user row for every account

-- `users` is keyed by the auth account, but nothing ever created the row: GoTrue makes
-- the account, and the phone captured at checkout is the first thing that tries to write
-- `users.phone`. Before this trigger that write hit a row that did not exist, and a
-- customer's first order silently carried an empty phone. The trigger creates the row
-- the moment the account does, so a phone captured later has somewhere to land.
--
-- SECURITY DEFINER because the inserting role is `supabase_auth_admin`, which — exactly
-- like the access-token hook — has no grant on `public.users`. Idempotent on purpose: a
-- re-insert (or a trigger re-fire) is a no-op, and the defaults live in the schema, not
-- here.
create or replace function public.ensure_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger ensure_user_profile_after_insert
  after insert on auth.users
  for each row execute function public.ensure_user_profile();

-- ---------------------------------------------------------------- H2: a daily meal is for today, and only before its window closes

-- The priced half of `place_order` — `place_order_priced` since the S1 audit renamed it
-- behind a wrapper that refuses a blocked customer. It already refused a draft or a
-- closed day; what it did not check is whether the meal is for *today* and whether its
-- collection window has already passed. A reservation for yesterday's meal, or one
-- placed after the kitchen has finished handing out portions, would otherwise go
-- through — and the kitchen would owe food it cannot give. Asked in Cairo time on
-- purpose: the day key is `yyyy-MM-dd` and the window is minutes since midnight, so
-- comparing against a UTC clock would refuse yesterday's meal at 9pm Edku and accept
-- tomorrow's at 1am.
--
-- The wrapper `place_order` is left untouched: the is_blocked guard it carries is the
-- whole point of S1, and re-creating it here would silently drop that check.
--
-- The decision lives in its own function rather than inline so it is testable on PGlite,
-- which has the real date/interval machinery but no `auth.uid()` — the one thing that
-- stops the priced function itself being called there.
create or replace function public.meal_is_reservable(
  p_meal public.daily_meals,
  p_at   timestamptz
)
returns boolean
language plpgsql
stable
as $$
declare
  v_local timestamp := p_at at time zone 'Africa/Cairo';
begin
  if p_meal.date <> v_local::date then
    return false;
  end if;
  if (extract(hour from v_local) * 60 + extract(minute from v_local))
     >= p_meal.pickup_window_end then
    return false;
  end if;
  return true;
end;
$$;

create or replace function public.place_order_priced(p_draft jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_merchant   public.merchants;
  v_zone_id    uuid;
  v_address    jsonb;
  v_items      jsonb := p_draft -> 'items';
  v_line       jsonb;
  v_menu       record;
  v_subtotal   integer := 0;
  v_qty        integer := 0;
  v_delivery   integer;
  v_coupon     public.coupons;
  v_coupon_code text;
  v_user_uses  integer;
  v_first_order boolean;
  v_sub_discount  integer := 0;
  v_del_discount  integer := 0;
  v_platform_owes integer := 0;
  v_cap        integer;
  v_delivery_by text;
  v_revenue    jsonb;
  v_deadline   timestamptz;
  v_timeout    integer;
  v_order      public.orders;
  v_meal       public.daily_meals;
  -- Read once: every branch below asks the same question about this draft.
  v_is_preorder boolean := p_draft ->> 'type' = 'preorder';
  -- Kept beside the record on purpose: `v_coupon is not null` on a RECORD is false
  -- when any field is null - an uncapped-free fixedAmount coupon has several - so the
  -- redemption block would silently never run and every code would be endless.
  v_coupon_id  uuid;
begin
  if v_uid is null then
    raise exception 'sign in to place an order' using errcode = '42501';
  end if;

  perform set_config('app.server_mode', 'on', true);

  select * into v_merchant
    from public.merchants where id = (p_draft ->> 'merchantId')::uuid;
  if not found then
    raise exception 'merchant not found' using errcode = 'P0002';
  end if;
  if v_merchant.status <> 'approved' then
    raise exception 'merchant not accepting orders' using errcode = 'P0001';
  end if;
  if v_merchant.paused_until is not null and v_merchant.paused_until > now() then
    raise exception 'merchant not accepting orders' using errcode = 'P0001';
  end if;

  -- Outside the posted hours, no order. The same question the phone asks through
  -- Merchant.acceptsOrdersAt, asked again where a stale or hand-written request
  -- cannot talk its way past it.
  if not public.merchant_open_at(v_merchant.opening_hours, now()) then
    raise exception 'merchant not accepting orders' using errcode = 'P0001';
  end if;

  -- Prepaid: the platform stops carrying a merchant who has run out, before the order
  -- rather than after - one order going out unpaid for is one too many.
  if v_merchant.revenue_model = 'prepaid'
     and v_merchant.wallet_balance < v_merchant.revenue_value then
    raise exception 'merchant not accepting orders' using errcode = 'P0001';
  end if;

  -- Recompute every line from its source of truth: the name and unit price are read,
  -- not believed. The quantity is the customer's to say - but only ever as a positive
  -- whole number, and extras can never cost less than nothing, because a negative figure
  -- is arithmetic that *lowers* what the courier collects at the door.
  --
  -- The source differs by type. An instant order prices itself from the merchant's menu.
  -- A pre-order prices itself from the day's meal: the app sends the daily_meals id in
  -- itemId - a home kitchen's published meal has no menu_items row to be found under -
  -- so reading the menu here would refuse every reservation the city ever tried to make.
  if v_is_preorder then
    if nullif(btrim(p_draft ->> 'dailyMealId'), '') is null then
      raise exception 'a pre-order names its meal' using errcode = 'P0001';
    end if;
    select * into strict v_meal
      from public.daily_meals
     where id = (p_draft ->> 'dailyMealId')::uuid
       and merchant_id = v_merchant.id;
    -- A draft, or a day already closed, is not something to reserve against. Raised in
    -- the sentence the phone classifies as "somebody got there first".
    if v_meal.status <> 'published' then
      raise exception 'meal not accepting reservations' using errcode = 'P0001';
    end if;
    -- The meal is for one specific day, and reservations close when its collection
    -- window ends. Both in Cairo time: the day key is `yyyy-MM-dd` and the window is
    -- minutes since midnight, so comparing against a UTC clock would refuse yesterday's
    -- meal at 9pm Edku and accept tomorrow's at 1am.
    if not public.meal_is_reservable(v_meal, now()) then
      raise exception 'meal not accepting reservations' using errcode = 'P0001';
    end if;
  end if;

  for v_line in select * from jsonb_array_elements(v_items) loop
    if coalesce((v_line ->> 'quantity')::int, 0) < 1 then
      raise exception 'a line needs at least one item' using errcode = 'P0001';
    end if;
    if coalesce((v_line ->> 'optionsTotal')::int, 0) < 0 then
      raise exception 'extras cannot cost less than nothing' using errcode = 'P0001';
    end if;

    if v_is_preorder then
      -- A daily meal carries no extras. optionsTotal on a pre-order line is ignored
      -- rather than priced in, so what gets stored cannot disagree with what was summed.
      v_subtotal := v_subtotal + v_meal.price * (v_line ->> 'quantity')::int;
    else
      select name, price into strict v_menu
        from public.menu_items
       where id = (v_line ->> 'itemId')::uuid
         and merchant_id = v_merchant.id;

      v_subtotal := v_subtotal +
        (v_menu.price + coalesce((v_line ->> 'optionsTotal')::int, 0))
        * (v_line ->> 'quantity')::int;
    end if;
  end loop;
  if v_subtotal <= 0 then
    raise exception 'an empty basket is not an order' using errcode = 'P0001';
  end if;

  -- The delivery zone and the copied address. An instant order goes somewhere; a
  -- pre-order without an address is collected by the customer who placed it.
  if p_draft ? 'addressId' then
    select jsonb_build_object(
             -- The id rides along even in a frozen copy: the phone's Address model
             -- requires it, and a courier's screen must not crash on a parse.
             'id', a.id::text,
             'zoneId', a.zone_id::text,
             'landmarkId', a.landmark_id::text,
             'landmarkName', a.landmark_name,
             'landmarkNote', a.landmark_note,
             'street', a.street,
             'building', a.building,
             'floor', a.floor,
             'apartment', a.apartment,
             'label', a.label
           )
      into v_address
      from public.addresses a
     where a.id = (p_draft ->> 'addressId')::uuid
       and a.user_id = v_uid;
    if v_address is null then
      raise exception 'address not found' using errcode = 'P0002';
    end if;
    v_zone_id := (v_address ->> 'zoneId')::uuid;
    v_delivery := coalesce(v_merchant.delivery_fee_override,
                           (select default_delivery_fee from public.zones
                             where id = v_zone_id));
    -- The zone row itself has to be there: a missing zone falling through to a zero
    -- fee would be free delivery invented by a deletion.
    if v_delivery is null then
      raise exception 'delivery zone unknown' using errcode = 'P0002';
    end if;
    -- And the merchant has to actually serve it. The phone checks this first and hides
    -- the button; this check is what stops an order that dodged the phone.
    if not exists (
      select 1 from public.merchant_served_zones sz
       where sz.merchant_id = v_merchant.id
         and sz.zone_id = v_zone_id
    ) then
      raise exception 'merchant does not deliver to this zone' using errcode = 'P0001';
    end if;
  else
    v_zone_id := v_merchant.zone_id;
    v_delivery := 0;
  end if;

  -- The coupon, evaluated against rules it carries on itself - validity, ownership,
  -- minimums, first-order-only, per-user and total caps - and applied to this basket.
  -- A rejection names its reason, so the phone can say which sentence to show.
  v_coupon_code := nullif(btrim(p_draft ->> 'couponCode'), '');
  if v_coupon_code is not null then
    select * into v_coupon
      from public.coupons
     where code = upper(translate(v_coupon_code,
                                  '٠١٢٣٤٥٦٧٨٩', '0123456789'))
       and city_id = v_merchant.city_id;
    if not found then
      raise exception 'coupon: notFound' using errcode = 'P0001';
    end if;
    v_coupon_id := v_coupon.id;
    if not v_coupon.is_active then
      raise exception 'coupon: inactive' using errcode = 'P0001';
    end if;
    if v_coupon.valid_from is not null and now() < v_coupon.valid_from then
      raise exception 'coupon: notYetValid' using errcode = 'P0001';
    end if;
    if v_coupon.valid_until is not null and now() > v_coupon.valid_until then
      raise exception 'coupon: expired' using errcode = 'P0001';
    end if;
    if v_coupon.merchant_id is not null
       and v_coupon.merchant_id <> v_merchant.id then
      raise exception 'coupon: wrongMerchant' using errcode = 'P0001';
    end if;
    if v_subtotal < v_coupon.min_order then
      raise exception 'coupon: minOrderNotMet' using errcode = 'P0001';
    end if;
    if v_coupon.first_order_only then
      select not exists (
        select 1 from public.orders where customer_uid = v_uid
      ) into v_first_order;
      if not v_first_order then
        raise exception 'coupon: firstOrderOnly' using errcode = 'P0001';
      end if;
    end if;
    select count(*) into v_user_uses
      from public.coupon_redemptions
     where coupon_id = v_coupon.id and customer_uid = v_uid;
    if v_coupon.per_user_limit > 0
       and v_user_uses >= v_coupon.per_user_limit then
      raise exception 'coupon: alreadyUsed' using errcode = 'P0001';
    end if;
    if v_coupon.total_limit > 0
       and v_coupon.used_count >= v_coupon.total_limit then
      raise exception 'coupon: exhausted' using errcode = 'P0001';
    end if;
    if not public.percentage_coupon_is_capped(v_coupon) then
      raise exception 'coupon: malformed' using errcode = 'P0001';
    end if;

    -- Integer division truncates, rounding in the merchant's favour by at most one
    -- piastre - the direction to err in when the difference is settled in cash.
    v_cap := least(coalesce(v_coupon.max_discount, v_subtotal), v_subtotal);
    if v_coupon.type = 'percentage' then
      v_sub_discount := least(v_subtotal * v_coupon.value / 10000, v_cap);
    elsif v_coupon.type = 'fixedAmount' then
      v_sub_discount := least(v_coupon.value, v_subtotal);
    else
      v_del_discount := coalesce(v_delivery, 0);
    end if;

    if v_coupon.funded_by = 'platform' then
      v_platform_owes := v_sub_discount + v_del_discount;
    end if;
  end if;

  -- The pre-order's portion is taken inside this transaction: the conditional update is
  -- the race being settled. Zero rows means somebody else got the last one first.
  if p_draft ->> 'type' = 'preorder' then
    if p_draft ? 'dailyMealId' then
      for v_line in select * from jsonb_array_elements(v_items) loop
        v_qty := v_qty + (v_line ->> 'quantity')::int;
      end loop;

      update public.daily_meals
         set remaining_qty = remaining_qty - v_qty
       where id = (p_draft ->> 'dailyMealId')::uuid
         and remaining_qty >= v_qty;
      if not found then
        raise exception 'sold out' using errcode = 'P0001';
      end if;
    else
      raise exception 'a pre-order names its meal' using errcode = 'P0001';
    end if;
  end if;

  -- Who carries it, frozen like everything else that decides responsibility: a home
  -- kitchen or a merchant without their own driver means Luqma's courier.
  v_delivery_by := case when v_merchant.delivers_self then 'merchant'
                             else 'platform' end;

  -- The revenue terms in force right now, frozen onto the order.
  select jsonb_build_object(
           'model', v_merchant.revenue_model,
           'value', v_merchant.revenue_value,
           'amount', 0
     ) into v_revenue;

  -- Instant orders only: a pre-order has no countdown to run out of.
  if p_draft ->> 'type' <> 'preorder' then
    select coalesce((value #>> '{}')::int, 5) into v_timeout
      from public.config where key = 'accept_timeout_minutes';
    v_deadline := now() + make_interval(mins => coalesce(v_timeout, 5));
  end if;

  insert into public.orders
    (city_id, customer_uid, customer_name, customer_phone, merchant_id,
     merchant_name, zone_id, address, delivery_by, type, items, pricing, revenue,
     status, daily_meal_id, coupon_code, accept_deadline_at)
  values
    (v_merchant.city_id, v_uid,
     coalesce((select name from public.users where id = v_uid), 'عميل'),
     coalesce((select phone from public.users where id = v_uid), ''),
     v_merchant.id, v_merchant.name, v_zone_id, v_address, v_delivery_by,
     coalesce(p_draft ->> 'type', 'instant'),
     case when v_is_preorder then
       -- Frozen from the day's meal, the same source the subtotal was summed from. The
       -- meal's id rides in itemId, and extras are stored as zero because that is what
       -- was priced - never what arrived.
       (select jsonb_agg(
                  jsonb_build_object(
                    'itemId', p_draft ->> 'dailyMealId',
                    'name', v_meal.name,
                    'unitPrice', v_meal.price,
                    'quantity', (line ->> 'quantity')::int,
                    'optionsTotal', 0,
                    'note', line ->> 'note')
                order by ord)
          from jsonb_array_elements(v_items) with ordinality as t(line, ord))
     else
       (select jsonb_agg(
                  jsonb_build_object(
                    'itemId', m.id::text, 'name', m.name,
                    'unitPrice', m.price, 'quantity',
                    (line ->> 'quantity')::int,
                    'optionsTotal', coalesce((line ->> 'optionsTotal')::int, 0),
                    'note', line ->> 'note')
                order by (line ->> 'sortOrder')::int)
          from jsonb_array_elements(v_items) with ordinality as t(line, ord)
          join public.menu_items m on m.id = (line ->> 'itemId')::uuid)
     end,
     jsonb_build_object(
       'subtotal', v_subtotal,
       'deliveryFee', coalesce(v_delivery, 0),
       'subtotalDiscount', v_sub_discount,
       'deliveryDiscount', v_del_discount,
       'total', greatest(v_subtotal - v_sub_discount
                         + coalesce(v_delivery, 0) - v_del_discount, 0),
       'platformOwesMerchant', v_platform_owes),
     v_revenue,
     'placed',
     nullif(p_draft ->> 'dailyMealId', '')::uuid,
     v_coupon_code,
     v_deadline)
  returning * into v_order;

  -- The coupon remembers it was used, and so does the code itself. The increment is
  -- conditional on the limit being unspent *at update time*: two concurrent orders can
  -- both read used_count below the limit, and only the row-level update serialises
  -- them. Zero rows means the code ran out between the check and here - the whole
  -- transaction, order included, rolls back.
  if v_coupon_id is not null then
    update public.coupons
       set used_count = used_count + 1
     where id = v_coupon_id
       and (v_coupon.total_limit = 0 or used_count < v_coupon.total_limit);
    if not found then
      raise exception 'coupon: exhausted' using errcode = 'P0001';
    end if;

    insert into public.coupon_redemptions
      (coupon_id, order_id, customer_uid)
    values (v_coupon_id, v_order.id, v_uid);
  end if;

  return to_jsonb(v_order);
end;
$$;

-- The priced half keeps the privileges S1 left it with (revoked from everyone; the
-- wrapper reaches it as SECURITY DEFINER). No grant here, so no door beside the door.

-- ---------------------------------------------------------------- H3: the push cap, ended promotions, and a city-wide count

-- Nothing ever wrote `status = 'ended'`, so a campaign that ran its course stayed
-- `approved` for ever — and the weekly push cap, which counts only `ended` rows, never
-- saw a single push. This function is the expiry pass: an approved push whose end date
-- is in the past is over. Extracted into its own function so the cron job and a test
-- (PGlite cannot run cron) both reach the same UPDATE.
create or replace function public.end_expired_promotions()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ended integer := 0;
begin
  with ended as (
    update public.promotions
       set status = 'ended'
     where status = 'approved'
       and end_at < now()
    returning 1
  )
  select count(*) into v_ended from ended;

  return v_ended;
end;
$$;

revoke execute on function public.end_expired_promotions()
  from public, anon, authenticated;
grant execute on function public.end_expired_promotions() to service_role;

-- Whether the city has a marketing push left this week, answered by the server.
--
-- The old client count was blind: a merchant's RLS sees only their own rows, so the
-- count understated every merchant but the caller and the cap never bit. Moving the
-- count server-side is the only way to count the *city* from a client that may only see
-- its own corner of it. "Sent" means ended, or approved and already started — an
-- approved campaign that has not begun has not spent anybody's attention yet.
create or replace function public.push_slot_available(p_city_id text, p_limit int)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sent integer;
begin
  select count(*) into v_sent
    from public.promotions
   where city_id = p_city_id
     and channel = 'push'
     and (status = 'ended'
          or (status = 'approved' and start_at <= now()))
     and start_at >= now() - interval '7 days';

  return v_sent < p_limit;
end;
$$;

revoke execute on function public.push_slot_available(text, int) from public, anon;
grant execute on function public.push_slot_available(text, int) to authenticated, service_role;

-- ---------------------------------------------------------------- M2: the coupon preview refuses what the placement refuses

-- The table constraint stops an uncapped percentage coupon being *written*, but the
-- preview must refuse it too: a discount the preview accepts and the placement refuses
-- is a promise broken at the worst possible moment. place_order checks this; the preview
-- now does as well, in the same `malformed` sentence. The rule lives in its own function
-- so both callers (and the PGlite test, which has no `auth.uid()`) reach the same check.
create or replace function public.percentage_coupon_is_capped(p_coupon public.coupons)
returns boolean
language sql
immutable
as $$
  select p_coupon.type <> 'percentage' or p_coupon.max_discount is not null;
$$;

create or replace function public.evaluate_coupon(
  p_code         text,
  p_merchant_id  uuid,
  p_subtotal     integer,
  p_delivery_fee integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid          uuid := auth.uid();
  v_merchant     public.merchants;
  v_coupon       public.coupons;
  v_uses         integer;
  v_first_order  boolean;
  v_sub_discount integer := 0;
  v_del_discount integer := 0;
begin
  if v_uid is null then
    raise exception 'sign in to price a coupon' using errcode = '42501';
  end if;
  if p_code is null or btrim(p_code) = '' then
    return jsonb_build_object('status', 'rejected', 'reason', 'notFound');
  end if;

  select * into v_merchant from public.merchants where id = p_merchant_id;
  if not found or v_merchant.status <> 'approved' then
    return jsonb_build_object('status', 'rejected', 'reason', 'wrongMerchant');
  end if;

  select * into v_coupon
    from public.coupons
   where code = upper(translate(btrim(p_code),
                                '٠١٢٣٤٥٦٧٨٩', '0123456789'))
     and city_id = v_merchant.city_id;
  if not found then
    return jsonb_build_object('status', 'rejected', 'reason', 'notFound');
  end if;
  if not v_coupon.is_active then
    return jsonb_build_object('status', 'rejected', 'reason', 'inactive');
  end if;
  if v_coupon.valid_from is not null and now() < v_coupon.valid_from then
    return jsonb_build_object('status', 'rejected', 'reason', 'notYetValid');
  end if;
  if v_coupon.valid_until is not null and now() > v_coupon.valid_until then
    return jsonb_build_object('status', 'rejected', 'reason', 'expired');
  end if;
  if v_coupon.merchant_id is not null
     and v_coupon.merchant_id <> v_merchant.id then
    return jsonb_build_object('status', 'rejected', 'reason', 'wrongMerchant');
  end if;
  if p_subtotal < v_coupon.min_order then
    return jsonb_build_object('status', 'rejected', 'reason', 'minOrderNotMet');
  end if;
  if v_coupon.first_order_only then
    select not exists (
      select 1 from public.orders where customer_uid = v_uid
    ) into v_first_order;
    if not v_first_order then
      return jsonb_build_object('status', 'rejected', 'reason', 'firstOrderOnly');
    end if;
  end if;
  select count(*) into v_uses
    from public.coupon_redemptions
   where coupon_id = v_coupon.id and customer_uid = v_uid;
  if v_coupon.per_user_limit > 0 and v_uses >= v_coupon.per_user_limit then
    return jsonb_build_object('status', 'rejected', 'reason', 'alreadyUsed');
  end if;
  if v_coupon.total_limit > 0
     and v_coupon.used_count >= v_coupon.total_limit then
    return jsonb_build_object('status', 'rejected', 'reason', 'exhausted');
  end if;

  -- The same malformed-uncapped check the placement makes. A percentage without a cap
  -- cannot be written through the table, but a preview must never promise a discount
  -- the placement will refuse.
  if not public.percentage_coupon_is_capped(v_coupon) then
    return jsonb_build_object('status', 'rejected', 'reason', 'malformed');
  end if;

  -- Integer division truncates, rounding in the merchant's favour - same arithmetic,
  -- same direction, as place_order.
  if v_coupon.type = 'percentage' then
    v_sub_discount := least(p_subtotal * v_coupon.value / 10000,
                            least(v_coupon.max_discount, p_subtotal));
  elsif v_coupon.type = 'fixedAmount' then
    v_sub_discount := least(v_coupon.value, p_subtotal);
  else
    v_del_discount := coalesce(p_delivery_fee, 0);
  end if;

  return jsonb_build_object(
    'status', 'accepted',
    'subtotalDiscount', v_sub_discount,
    'deliveryDiscount', v_del_discount,
    'platformOwesMerchant',
      case when v_coupon.funded_by = 'platform'
           then v_sub_discount + v_del_discount else 0 end);
end;
$$;

revoke execute on function public.evaluate_coupon(text, uuid, integer, integer)
  from public, anon;
grant execute on function public.evaluate_coupon(text, uuid, integer, integer)
  to authenticated, service_role;

-- ---------------------------------------------------------------- M3: every status change leaves a trace

-- The escalator wrote its own history, but a client that moved an order left none — the
-- audit trail began only where the server had acted. This trigger appends the same
-- `{from, to, by, at}` record the escalator writes, for every client transition, so the
-- admin screen can answer "who moved this and when" for the whole life of an order.
--
-- It deliberately stands down when the server itself is moving the order: the escalator
-- writes its own history, and a second append here would write the transition twice.
create or replace function public.append_order_status_history()
returns trigger
language plpgsql
as $$
declare
  v_by text;
begin
  if new.status is not distinct from old.status then
    return new;
  end if;

  -- The server functions that move orders declare server_mode and write their own
  -- history; appending again here would double every server transition.
  if coalesce(current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  -- The same actor resolution the transition guard uses, in the same order: the claim
  -- decides who is acting, never a value the client could have written.
  v_by := case
    when public.is_admin() then 'admin'
    when auth.uid() = old.customer_uid then 'customer'
    when public.is_merchant_owner(old.merchant_id) then 'merchant'
    when auth.uid() = old.courier_uid
      or public.is_courier_for(old.merchant_id)
      or (public.is_platform_courier() and old.delivery_by = 'platform') then 'courier'
    else 'customer'
  end;

  new.status_history := coalesce(new.status_history, '[]'::jsonb) || jsonb_build_array(
    jsonb_build_object(
      'from', old.status,
      'to', new.status,
      'by', v_by,
      'at', now()
    )
  );

  return new;
end;
$$;

create trigger orders_append_status_history
  before update of status on orders
  for each row execute function public.append_order_status_history();

-- ---------------------------------------------------------------- the expiry schedule

do $body$
declare
  v_cron boolean;
begin
  select count(*) > 0 into v_cron
    from pg_available_extensions
   where name = 'pg_cron';

  if v_cron then
    create extension if not exists pg_cron;

    -- Campaigns end on the hour; the cap only has to be roughly right, and a minute
    -- cron would burn schedule slots for nothing.
    perform cron.unschedule('luqma-end-expired-promotions')
      where exists (select 1 from cron.job where jobname = 'luqma-end-expired-promotions');
    perform cron.schedule('luqma-end-expired-promotions', '0 * * * *',
      'select public.end_expired_promotions()');
  end if;
end;
$body$;
