-- Account totals, independently of the newest-100 evidence pages.
-- SECURITY INVOKER: both ledgers already grant SELECT to authenticated callers;
-- no privileged reads or writes are needed. Existing RLS remains in force.
-- Check identity explicitly as well: otherwise an unauthorized aggregate would
-- return a zero account after RLS filtered every row. NULL means no account read.
-- The shared predicates require active staff and server-issued claims. The actual
-- database service_role is trusted; a client-supplied claim cannot impersonate it.
create or replace function public.settlement_summary(p_merchant_id uuid)
returns jsonb
language sql stable
security invoker
set search_path = ''
as $fn$
  select jsonb_build_object(
    'orders', count(*),
    'taken', coalesce(sum(s.amount), 0),
    'platform_owes', coalesce(sum(s.platform_owes), 0),
    'paid', (select coalesce(sum(p.amount), 0)
             from public.commission_payments p where p.merchant_id = p_merchant_id)
  )
  from public.order_settlements s
  where s.merchant_id = p_merchant_id and s.reversed_at is null
  having current_user = 'service_role'
      or public.is_admin()
      or public.is_merchant_owner(p_merchant_id);
$fn$;

revoke execute on function public.settlement_summary(uuid) from public, anon;
grant execute on function public.settlement_summary(uuid) to authenticated, service_role;

-- The invoker needs table privileges too. Spell these out rather than relying on
-- hosted default privileges, so service_role can use the RPC on a fresh restore.
grant select on public.order_settlements, public.commission_payments to service_role;
