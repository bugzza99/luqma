-- Nobody ever told the courier.
--
-- `queue_new_order_push` selects `role = 'owner'` and stops there, and it is the only
-- thing that has ever written a row for a merchant's staff. So a courier signs in, the
-- app registers their FCM token exactly as the owner's does, and the token sits in
-- `users.fcm_tokens` for ever with nothing addressed to it: the order arrives, the shop
-- cooks it, and the person who has to carry it finds out by opening the app and looking.
--
-- The cue is `preparing`, not `accepted` and not `outForDelivery`.
--
-- `accepted` is too early — the food has not been started and a courier sent then waits
-- in the shop. `outForDelivery` is too late: it is the transition that *means* the food
-- has left, and on the merchant's own board it is the merchant who makes it, so a
-- notification there tells the courier about a journey they are already on.
-- Every delivered order passes through `preparing` — the state machine allows
-- `accepted → preparing` and nothing else on the way to `outForDelivery` — so this fires
-- exactly once per order, at the moment there is something to come for.
create or replace function public.queue_courier_pickup_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_courier record;
  v_platform boolean;
begin
  if new.status is not distinct from old.status or new.status <> 'preparing' then
    return new;
  end if;

  v_platform := new.delivery_by = 'platform';

  -- Whose rider it is depends on who is delivering, and the order carries that as a
  -- frozen copy. A merchant who delivers their own food has couriers under their own
  -- `merchant_id`; a platform delivery is Luqma's own riders, who have no merchant.
  for v_courier in
    select uid from public.staff
     where role = 'courier'
       and is_active
       and case
             when v_platform then scope = 'platform'
             else scope = 'merchant' and merchant_id = new.merchant_id
           end
  loop
    insert into public.push_outbox (uid, title, body, data, channel)
    values (
      v_courier.uid,
      'أوردر جاهز للتوصيل',
      'أوردر من ' || new.merchant_name || ' محتاج توصيل.',
      jsonb_build_object('kind', 'pickup', 'orderId', new.id::text),
      -- The critical channel, like the merchant's. A courier is on a motorbike with the
      -- phone in a pocket, which is the same problem the alarm was built for: an alert
      -- that only shows when somebody is already looking at the screen is no alert.
      'orders_critical'
    );
  end loop;

  return new;
end;
$$;

create trigger orders_push_courier_pickup
  after update of status on orders
  for each row execute function public.queue_courier_pickup_push();
