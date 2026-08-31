-- The other two apps get told things too.
--
-- `push_outbox` was built for one message: an order arriving at a shop. That is the one
-- the business cannot run without, so it went first and alone — but the transport, the
-- drain, the token pruning and the Android channels are all general, and nothing about
-- them was ever merchant-specific. What was missing is rows.
--
-- Everything here follows the same rule as the order alarm: the row is written **inside
-- the transaction that caused it**, and something else sends it. A notification that
-- arrives late is a nuisance; a status change that fails because Google had a bad minute
-- is a courier standing in the street unable to close an order.

-- The customer, on the three transitions that change what they should do.
--
-- Not every status. `preparing` tells somebody nothing they cannot infer from having
-- ordered, and a phone that buzzes for each of six steps is a phone whose owner turns the
-- app's notifications off — taking the two that matter with it.
create or replace function public.queue_order_status_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_title text;
  v_body  text;
begin
  if new.status is not distinct from old.status then
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
      v_title := 'الأوردر اتلغى';
      v_body  := 'الأوردر من ' || new.merchant_name || ' اتلغى. كلّمنا لو محتاج مساعدة.';
    else
      return new;
  end case;

  insert into public.push_outbox (uid, title, body, data, channel)
  values (
    new.customer_uid,
    v_title,
    v_body,
    jsonb_build_object('kind', 'orderStatus', 'orderId', new.id::text),
    -- `orders`, not `orders_critical`: the critical channel carries the looping alarm
    -- built for a merchant who is cooking and not looking at their phone. Waking a
    -- customer that way to say their food is on the way is how somebody silences the app.
    'orders'
  );

  return new;
end;
$$;

create trigger orders_push_status
  after update of status on orders
  for each row execute function public.queue_order_status_push();

-- The admin, on the one thing that costs money while nobody is looking.
--
-- An order nobody answered is a customer waiting on food that is not being cooked. The
-- merchant's own alarm already fired and was missed — that is what `needsAttention`
-- means — so this is the second line, and it is a person rather than a retry.
create or replace function public.queue_admin_attention_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin record;
begin
  if new.status is not distinct from old.status or new.status <> 'needsAttention' then
    return new;
  end if;

  -- Every active platform admin, not the first one found: "somebody will see it" is how
  -- a queue goes unwatched on the evening that one person is away.
  for v_admin in
    select uid from public.staff
     where scope = 'platform' and role = 'admin' and is_active
  loop
    insert into public.push_outbox (uid, title, body, data, channel)
    values (
      v_admin.uid,
      'أوردر محدش ردّ عليه',
      new.merchant_name || ' مردّش على أوردر.',
      jsonb_build_object('kind', 'needsAttention', 'orderId', new.id::text),
      'orders_critical'
    );
  end loop;

  return new;
end;
$$;

create trigger orders_push_needs_attention
  after update of status on orders
  for each row execute function public.queue_admin_attention_push();
