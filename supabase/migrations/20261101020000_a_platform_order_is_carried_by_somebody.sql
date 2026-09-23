-- A platform order is never delivered without a courier on it.
--
-- MerchantApp's live board offered the owner «خرج للتوصيل» from `preparing` on every order,
-- and this function allowed the move. On a platform order (`delivery_by = 'platform'`)
-- that tap wrote the status and nothing else — and `markOnTheWay`, the only path that puts
-- a rider's name on the order, starts from `preparing`, so once the shop had moved it no
-- rider could take it any more. `is_courier_for_order` still lets any platform courier act
-- on an order whose `courier_uid` is null, `markDelivered` writes no name, and
-- `apply_courier_settlement` reads a null courier as `merchantDelivery`. So the default
-- flow ended with a platform order delivered by nobody on record: a zero-commission row
-- labelled "the shop delivered", nothing on any rider's statement, and no record of who
-- is holding the customer's cash.
--
-- Two rules close it, both here:
--
--   * a shop owner sends out only an order its own rider carries. A platform order leaves
--     the kitchen when a platform courier takes it, which writes the status and their
--     name in one update;
--   * a platform order reaches `outForDelivery` or `delivered` only with a courier on the
--     row as it will be — its mode and its courier both read from `new`. That is the
--     invariant itself rather than a list of who may break it, so it holds for the next
--     path somebody writes as well as for these two.
--
-- `apply_courier_settlement` is deliberately untouched. With these in place a delivered
-- platform order always carries a name, its `v_uid is null` arm is unreachable through a
-- delivery, and the settlement stays the single writer of its own grounds.
--
-- Written into `enforce_order_transition` rather than a trigger of its own: it is a rule
-- about which status an order may move to, and a second trigger saying half of it would
-- be a second place for the next transition to be added to only one of. Copied from
-- `20261101010000_a_moderator_cannot_move_money.sql`, the latest definition, with those
-- two changes and nothing else.
create or replace function public.enforce_order_transition()
returns trigger
language plpgsql
as $fn$
declare
  actor text;
begin
  if new.status = old.status then
    return new;
  end if;

  if coalesce(current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  -- Before the admin's exit, and on purpose. Nothing in AdminApp moves an order to
  -- `outForDelivery` or `delivered` — its one order write is the moderator's cancellation
  -- below — and an admin who did would be settling a delivery nobody is on record as
  -- having made. An admin puts a courier on the order first. Judged on `new` throughout,
  -- because this is a rule about the row as it will be: the name arrives in the same
  -- update as the status, and a rider must not be able to take it off in the one that
  -- delivers. The mode is `new` for the same reason — read from `old`, an admin could
  -- write `delivery_by = 'platform'` and `delivered` in one statement on a shop's order,
  -- this check would see a merchant order, the exit below would let it through, and the
  -- settlement would record `merchantDelivery` at zero on a platform order nobody carried.
  if new.delivery_by = 'platform'
     and new.status in ('outForDelivery', 'delivered')
     and new.courier_uid is null then
    raise exception 'a platform order goes out only with a courier on it'
      using errcode = 'check_violation';
  end if;

  if public.is_platform_admin() then
    return new;
  end if;

  -- A moderator, since `is_admin()` answers for both roles and the line above has taken
  -- the admin out.
  if public.is_admin() then
    if old.status in ('placed', 'needsAttention') and new.status = 'cancelled' then
      return new;
    end if;
    raise exception 'a moderator may cancel an order nobody answered, and move nothing else'
      using errcode = '42501';
  end if;

  if old.status in ('delivered', 'cancelled') then
    raise exception 'order % is finished (%), and cannot be moved', old.id, old.status
      using errcode = 'check_violation';
  end if;

  actor := case
    when auth.uid() = old.customer_uid then 'customer'
    when public.is_merchant_owner(old.merchant_id) then 'merchant'
    when public.is_courier_for_order(
      old.courier_uid, old.merchant_id, old.delivery_by
    ) then 'courier'
    else 'nobody'
  end;

  if not (
    (actor = 'customer' and old.status = 'placed' and new.status = 'cancelled')
    or (actor = 'merchant' and (
         (old.status = 'placed' and new.status in ('accepted', 'cancelled'))
      or (old.status = 'accepted' and new.status in ('preparing', 'cancelled'))
      -- Only an order the shop's own rider carries. The check above would refuse a
      -- platform one anyway, since an owner may not write `courier_uid`; saying it here
      -- as well keeps the table honest about what a shop may do. `old` on purpose, unlike
      -- the invariant: this is a permission, and a permission is judged on the order the
      -- shop found, as `actor` is. An owner cannot write `delivery_by` today, so the two
      -- read the same — but if that ever changed, `old` still refuses turning a platform
      -- order into the shop's own and sending it out, and the invariant above refuses
      -- the other direction, where `new` here would have let the first one through.
      or (old.status = 'preparing' and new.status = 'outForDelivery'
          and old.delivery_by = 'merchant')))
    or (actor = 'courier' and (
         (old.status = 'preparing' and new.status = 'outForDelivery')
      or (old.status = 'outForDelivery' and new.status in ('delivered', 'cancelled'))))
  ) then
    raise exception '% may not move an order from % to %', actor, old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$fn$;
