-- "فلوس النهارده" means the cash that came in, not the value of what was ordered.
--
-- The owner's decision, asked and answered. It is worth writing down because the two
-- readings are both defensible and the label does not distinguish them:
--
--   * value ordered — every order placed today that was not cancelled. Useful for
--     demand, and what this function returned.
--   * cash in — every order actually handed over today. What the owner counts at the
--     end of the day, and what they will compare against the money in the drawer.
--
-- The old rule counted an order the moment it was placed, so the figure included food
-- still on the stove, orders the shop had not answered, and orders that would be
-- cancelled an hour later. It was highest at the moment the least was certain, and it
-- fell during the evening as those resolved — which reads as a bad night rather than as
-- the number correcting itself.
--
-- Two changes follow from the decision, not one:
--
--   * the status must be `delivered`. That is the transition that moves money, which is
--     why it is the courier's alone and why `onOrderDelivered` hangs off it.
--   * the day must be measured on `delivered_at`, not `created_at`. Cash arrives when
--     the courier is handed it, whatever day the order was made — an order placed at
--     eleven at night and delivered after midnight is the second day's money, and an
--     order placed yesterday and delivered this morning is today's.
--
-- `ordersToday` is deliberately left alone. It answers a different question — how much
-- was asked for today — and an owner reading "طلبات النهارده" means orders placed, not
-- orders completed. The two figures now count on different rules on purpose.
--
-- Known and accepted: `delivered_at` is stamped from the courier's own device (audit
-- L3). A phone with the wrong date puts its cash on the wrong day. Moving it to server
-- time needs a `SECURITY DEFINER` RPC and is recorded as its own debt.
create or replace function public.admin_today()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'only an admin' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'ordersToday', (
      select count(*) from public.orders
       where created_at >= date_trunc('day', now())
         and status not in ('cancelled')),
    'moneyToday', (
      select coalesce(sum((pricing ->> 'total')::bigint), 0) from public.orders
       where status = 'delivered'
         and delivered_at >= date_trunc('day', now())),
    'needsAttention', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', o.id, 'number', o.order_number, 'merchantId', o.merchant_id,
               'merchantName', m.name) order by o.updated_at), '[]'::jsonb)
        from public.orders o
        join public.merchants m on m.id = o.merchant_id
       where o.status = 'needsAttention'),
    'openIssues', (
      select count(*) from public.order_issues where status = 'open')
  );
end;
$$;

revoke execute on function public.admin_today() from public, anon;
grant execute on function public.admin_today() to authenticated;

-- The day's takings are read on every visit to the dashboard, and this is now a range
-- scan over a column that had no index.
create index if not exists orders_delivered_at_idx
  on public.orders (delivered_at)
  where status = 'delivered';
