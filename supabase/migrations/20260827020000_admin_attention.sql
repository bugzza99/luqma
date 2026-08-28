-- What is waiting for the admin, in one round trip.
--
-- The AdminApp home is becoming a grid of every module, and a grid of eleven identical
-- tiles answers the only question somebody opens this app with — "what needs me today?" —
-- with nothing at all. Each tile carries its own count instead.
--
-- One function rather than eleven queries: eleven round trips to draw one screen is eleven
-- chances to be slow on a phone in a shop, and they would arrive at eleven different
-- moments so the grid would fill in raggedly.
--
-- Every count here is a small filtered one — pending photographs, open complaints,
-- requested campaigns. None of them is an aggregate over orders; `admin_today` already
-- owns those, and `docs/16` is explicit that the statistics screen must not read every
-- order in the city to count them.
create or replace function public.admin_attention()
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
    'pendingMedia', (
      select count(*) from public.media where status = 'pending'
    ),
    'openIssues', (
      select count(*) from public.order_issues where status = 'open'
    ),
    'requestedPromotions', (
      select count(*) from public.promotions where status = 'requested'
    ),
    'pendingMerchants', (
      select count(*) from public.merchants where status = 'pending'
    ),
    -- An order nobody answered in time. The merchant's countdown is computed on their
    -- own device, but the escalation is the server's, and this is where the admin finds
    -- out it happened.
    'ordersNeedingAttention', (
      select count(*) from public.orders where status = 'needsAttention'
    )
  );
  -- No landmark-suggestion count here on purpose. Those notes are not a table: they are
  -- a free-text column a customer typed on an address, read back out of `orders` and
  -- grouped in Dart. Counting them would mean scanning orders on every open of the home
  -- screen, which is the one thing `docs/16` says the aggregates must never do.
end;
$$;

revoke all on function public.admin_attention() from public, anon;
grant execute on function public.admin_attention() to authenticated;
