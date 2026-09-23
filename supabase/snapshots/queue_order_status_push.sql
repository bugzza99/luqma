-- SNAPSHOT of public.queue_order_status_push as it runs — written by snapshot-functions.mjs.
-- Documentation only: never applied. Change it with a migration.

CREATE OR REPLACE FUNCTION public.queue_order_status_push()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_title text;
  v_body  text;
begin
  if new.status is not distinct from old.status or new.customer_uid is null then
    return new;
  end if;

  case new.status
    when 'accepted' then
      v_title := 'اتقبل طلبك';
      v_body  := new.merchant_name || ' بدأ يحضّر الأوردر.';
    when 'outForDelivery' then
      v_title := 'الأوردر في الطريق';
      v_body  := 'الطلب خرج من ' || new.merchant_name || ' وجاي لك.';
    when 'cancelled' then
      -- They pressed the button; telling them is telling them what they just did.
      if new.cancelled_by is not distinct from 'customer' then
        return new;
      end if;
      v_title := 'الأوردر اتلغى';
      v_body  := 'الأوردر من ' || new.merchant_name
                 || ' اتلغى. كلّمنا لو محتاج مساعدة.';
    else
      return new;
  end case;

  insert into public.push_outbox (uid, title, body, data, channel)
  values (
    new.customer_uid,
    v_title,
    v_body,
    pg_catalog.jsonb_build_object('kind', 'orderStatus', 'orderId', new.id::text),
    'orders'
  );

  return new;
end;
$function$;
