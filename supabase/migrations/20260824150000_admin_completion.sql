-- The admin screens' server half.
--
-- Everything here answers one question the client cannot be trusted to ask itself:
-- aggregates over whole tables (PostgREST has no GROUP BY), and one write the column
-- guards rightly refuse to any client — flipping `users.is_blocked`. Each function
-- checks `is_admin()` inside rather than leaning on grants alone, so the failure a
-- customer gets is the classified 42501 the app speaks.

-- ---------------------------------------------------------------- blocking a customer

-- A blocked customer's sessions die at the sign-in boundary; this flag is what the
-- boundary reads. Only the server writes it — the same shape as rejected_orders_count.
create or replace function public.admin_set_customer_blocked(
  p_uid     uuid,
  p_blocked boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin may block a customer' using errcode = '42501';
  end if;

  update public.users
     set is_blocked = p_blocked,
         updated_at = now()
   where id = p_uid;
  if not found then
    raise exception 'no such customer' using errcode = 'P0002';
  end if;

  insert into public.audit_log (action, actor, detail)
    values ('customer.blocked', v_actor,
            jsonb_build_object('uid', p_uid, 'blocked', p_blocked));
end;
$$;
revoke execute on function public.admin_set_customer_blocked(uuid, boolean)
  from public, anon;
grant execute on function public.admin_set_customer_blocked(uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------- today

-- The four numbers the owner opens the app to see, in one round trip. Money counts
-- every order that was not refused or cancelled — a delivered order and an eaten one
-- both moved cash; the escalator's needs_attention does not.
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
       where created_at >= date_trunc('day', now())
         and status not in ('cancelled')),
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

-- ---------------------------------------------------------------- statistics

-- Wider than today: who is on the platform and how it is moving. Read-only by nature,
-- computed in the database because Edku's reports deserve SQL rather than a counters
-- table somebody must remember to maintain.
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
    'customers', (select count(*) from public.users),
    'merchantsByStatus', (
      select coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
        from (select status, count(*) as n
                from public.merchants group by status) s),
    'ordersTotal', (select count(*) from public.orders),
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
