-- SNAPSHOT of public.place_order_priced as it runs — written by snapshot-functions.mjs.
-- Documentation only: never applied. Change it with a migration.

CREATE OR REPLACE FUNCTION public.place_order_priced(p_draft jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid        uuid := auth.uid();
  v_merchant   public.merchants;
  v_zone_id    uuid;
  v_fee_min    int;
  v_fee_max    int;
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
  v_is_preorder boolean := coalesce(p_draft ->> 'type', 'instant') = 'preorder';
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
  if not v_is_preorder and v_merchant.paused_until is not null and v_merchant.paused_until > now() then
    raise exception 'merchant not accepting orders' using errcode = 'P0001';
  end if;

  -- Outside the posted hours, no order. The same question the phone asks through
  -- Merchant.acceptsOrdersAt, asked again where a stale or hand-written request
  -- cannot talk its way past it.
  if not v_is_preorder and not public.merchant_open_at(v_merchant.opening_hours, now()) then
    raise exception 'merchant not accepting orders' using errcode = 'P0001';
  end if;

  -- Prepaid: the platform stops carrying a merchant who has run out, before the order
  -- rather than after - one order going out unpaid for is one too many.
  if not (v_merchant.plan_id is not null and v_merchant.plan_expires_at > now())
     and v_merchant.revenue_model = 'prepaid'
     and v_merchant.wallet_balance - v_merchant.wallet_held < v_merchant.revenue_value then
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
      select name, price, options, is_available into strict v_menu
        from public.menu_items
       where id = (v_line ->> 'itemId')::uuid
         and merchant_id = v_merchant.id;

      -- A basket sits open while a kitchen runs out. The phone greys the row the moment
      -- it hears; this is what stops the order that was already in the basket when it
      -- did, and the request that never asked the phone at all.
      if not v_menu.is_available then
        raise exception 'that dish is not available right now' using errcode = 'P0001';
      end if;

      v_subtotal := v_subtotal +
        (v_menu.price
         + public.price_line_options(v_menu.options, v_line -> 'optionIds'))
        * (v_line ->> 'quantity')::int;
    end if;
  end loop;
  if v_subtotal <= 0 then
    raise exception 'an empty basket is not an order' using errcode = 'P0001';
  end if;

  -- The merchant's floor, which until now only the phone knew. The only `min_order` this
  -- function checked was the *coupon's*, so a basket left open while a kitchen raised its
  -- minimum went through — and so did anything that never asked the phone.
  --
  -- Measured against the food alone, matching `Cart.shortfallFrom`: a delivery fee is not
  -- part of what a kitchen means by a small order. Pre-orders are exempt because a
  -- published meal sets its own price and the floor is about assembling a basket.
  if not v_is_preorder and v_subtotal < coalesce(v_merchant.min_order, 0) then
    raise exception 'below the shop minimum' using errcode = 'P0001';
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
             'label', a.label,
             -- Both halves or neither, which the column check already enforces
             -- on the row this is copied from. An address with no pin freezes two
             -- JSON nulls, which is what the phone's model expects; leaving the
             -- keys out entirely would be the same thing to Dart and a different
             -- thing to anything reading the jsonb directly.
             'lat', a.lat,
             'lng', a.lng
           )
      into v_address
      from public.addresses a
     where a.id = (p_draft ->> 'addressId')::uuid
       and a.user_id = v_uid;
    if v_address is null then
      raise exception 'address not found' using errcode = 'P0002';
    end if;
    v_zone_id := (v_address ->> 'zoneId')::uuid;
    -- Clamped into the admin's configured range, exactly as `Delivery.quotedOverride`
    -- clamps it on the phone. Read raw, this column made the screen and the door disagree
    -- whenever an override sat outside that range — quoted 110, collected 125 — and the
    -- door is what a customer actually pays. Zero survives the clamp on purpose: free
    -- delivery is an offer a merchant makes, not a value out of range.
    if v_merchant.delivery_fee_override is not null then
      if v_merchant.delivery_fee_override = 0 then
        v_delivery := 0;
      else
        -- `config` is key/value, and the same two rows the phones read through
        -- `LuqmaConfig`, so the range lives in one place rather than two that drift.
        -- A missing or unreadable bound falls back to the compiled-in default the phone
        -- would have used, not to no clamp at all.
        select coalesce((select (value #>> '{}')::int from public.config
                          where key = 'delivery_fee_min'), 0),
               coalesce((select (value #>> '{}')::int from public.config
                          where key = 'delivery_fee_max'), 100000)
          into v_fee_min, v_fee_max;
        v_delivery := greatest(v_fee_min,
                               least(v_fee_max, v_merchant.delivery_fee_override));
      end if;
    else
      select default_delivery_fee into v_delivery
        from public.zones where id = v_zone_id;
    end if;
    -- The zone row itself has to be there: a missing zone falling through to a zero
    -- fee would be free delivery invented by a deletion.
    if v_delivery is null then
      raise exception 'delivery zone unknown' using errcode = 'P0002';
    end if;
    -- And the merchant has to actually serve it. The phone checks this first and hides
    -- the button; this check is what stops an order that dodged the phone.
    -- Its own zone counts, without a row saying so. `Delivery.serves` has always applied
    -- that rule and says why in a comment — "filling in servedZones to reach further can
    -- never accidentally cut off the street the merchant is standing on" — and this
    -- function had never been told. Nothing in the product writes `merchant_served_zones`
    -- at all: creating a merchant through AdminApp inserts the merchant and stops. So
    -- every shop the owner made was one the phone offered and the server refused, on an
    -- address across the road from it.
    if v_zone_id <> v_merchant.zone_id and not exists (
      select 1 from public.merchant_served_zones sz
       where sz.merchant_id = v_merchant.id
         and sz.zone_id = v_zone_id
    ) then
      raise exception 'merchant does not deliver to this zone' using errcode = 'P0001';
    end if;
  elsif not v_is_preorder then
    raise exception 'an order to be delivered names its address' using errcode = '22023';
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
  if v_is_preorder then
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
  select case
           when v_merchant.plan_id is not null and v_merchant.plan_expires_at > now() then
             jsonb_build_object('model', 'subscription', 'value', 0, 'amount', 0)
           else
             jsonb_build_object('model', v_merchant.revenue_model, 'value', v_merchant.revenue_value, 'amount', 0)
         end into v_revenue;

  -- Instant orders only: a pre-order has no countdown to run out of.
  if not v_is_preorder then
    select coalesce((value #>> '{}')::int, 5) into v_timeout
      from public.config where key = 'accept_timeout_minutes';
    v_deadline := now() + make_interval(mins => coalesce(v_timeout, 5));
  end if;

  insert into public.orders
    (city_id, customer_uid, customer_name, customer_phone, merchant_id,
     merchant_name, zone_id, address, delivery_by, type, items, pricing, revenue,
     status, daily_meal_id, coupon_code, accept_deadline_at, note)
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
                    'options', '[]'::jsonb,
                    'note', line ->> 'note')
                order by ord)
          from jsonb_array_elements(v_items) with ordinality as t(line, ord))
     else
       (select jsonb_agg(
                  jsonb_build_object(
                    'itemId', m.id::text, 'name', m.name,
                    'unitPrice', m.price, 'quantity',
                    (line ->> 'quantity')::int,
                    'optionsTotal', public.price_line_options(
                      (select mi.options from public.menu_items mi
                        where mi.id = (line ->> 'itemId')::uuid),
                      line -> 'optionIds'),
                    'optionIds', coalesce(line -> 'optionIds', '[]'::jsonb),
                    'options', coalesce((
                      select jsonb_agg(jsonb_build_object(
                        'id', o ->> 'id', 'name', o ->> 'name',
                        'price', (o ->> 'price')::int) order by option_ord)
                      from jsonb_array_elements(m.options) with ordinality as chosen(o, option_ord)
                      where jsonb_typeof(line -> 'optionIds') = 'array'
                        and (line -> 'optionIds') ? (o ->> 'id')
                    ), '[]'::jsonb),
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
     v_deadline, nullif(btrim(p_draft ->> 'note', E' \t\n\r\f' || chr(11)), ''))
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
$function$;
