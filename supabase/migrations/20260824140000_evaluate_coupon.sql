-- Pricing one coupon against one basket, without placing anything.
--
-- The phone calls this as the customer types a code, so the total on screen is the
-- total the courier will collect - computed by the same server that will recompute it
-- again inside place_order. Coupons themselves stay unreadable; this returns the
-- verdict for one basket and nothing else, so codes cannot be enumerated through it.
--
-- Every rule here mirrors the validation inside place_order line for line - the two
-- must never disagree, because a discount the preview accepts and the placement refuses
-- is a promise broken at the worst possible moment.
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
