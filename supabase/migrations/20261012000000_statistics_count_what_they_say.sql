-- The statistics count what their labels say (QA review 2026-09-19).
--
--   * «العملاء» counted every user, admins and shop staff included.
--   * «كل الطلبات» counted cancelled orders while «متوسط قيمة الطلب» and «النمو» did not, so
--     the three figures on one screen described three different sets of orders.

create or replace function public.admin_statistics()
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
    -- People who can order, not every account: the admins, shop owners and couriers are
    -- users too, and «العملاء 6» with three of them staff was a number nobody could use.
    'customers', (select count(*) from public.users u
                   where not exists (select 1 from public.staff s where s.uid = u.id)),
    'merchantsByStatus', (
      select coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
        from (select status, count(*) as n
                from public.merchants group by status) s),
    -- The same orders every other figure here counts: cancelled ones are not orders taken.
    'ordersTotal', (select count(*) from public.orders where status not in ('cancelled')),
    'avgOrderValue', (
      select coalesce(round(avg((pricing ->> 'total')::numeric)), 0) from public.orders
       where status not in ('cancelled')),
    'byWeek', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'starting', w.starting, 'count', c.count) order by w.starting),
               '[]'::jsonb)
        from generate_series(
               date_trunc('week', now()) - interval '7 weeks',
               date_trunc('week', now()),
               interval '1 week') as w(starting)
        left join lateral (
          select count(*) as count from public.orders o
           where o.created_at >= w.starting
             and o.created_at < w.starting + interval '1 week'
             and o.status not in ('cancelled')) c on true),
    'byMonth', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'starting', m.starting, 'count', c.count) order by m.starting),
               '[]'::jsonb)
        from generate_series(
               date_trunc('month', now()) - interval '5 months',
               date_trunc('month', now()),
               interval '1 month') as m(starting)
        left join lateral (
          select count(*) as count from public.orders o
           where o.created_at >= m.starting
             and o.created_at < m.starting + interval '1 month'
             and o.status not in ('cancelled')) c on true)
  );
end;
$$;
revoke execute on function public.admin_statistics() from public, anon;
grant execute on function public.admin_statistics() to authenticated;

-- «اليوم» said how much the delivered orders were worth and never what the platform itself
-- took from them — the one figure the owner collects (QA review 2026-09-19). The same
-- function, with `platformToday`: the commission settled today, charges taken back left out.
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
    'platformToday', (
      select coalesce(sum(amount), 0) from public.order_settlements
       where settled_at >= date_trunc('day', now())
         and reversed_at is null),
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
