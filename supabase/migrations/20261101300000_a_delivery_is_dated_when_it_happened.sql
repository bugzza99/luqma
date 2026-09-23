-- A delivery is dated when it happened, and never outside what the server can vouch for
-- (audit L3).
--
-- `markDelivered` stamped `delivered_at` from the phone at the moment the request was
-- sent: a tap queued offline at 23:50 and sent at 01:10 landed on the next day's
-- statement, and a phone with a wrong clock wrote any date at all — into the column the
-- statements, the courier's day and «اليوم» all count by. The phone now sends the moment
-- of the tap; this keeps it only between the moment the order went out for delivery and
-- now, takes the nearer edge outside that, and takes now when nothing was sent.
--
-- "Went out" is the last `outForDelivery` entry in the order's own history, falling back
-- to when the order was made. BEFORE UPDATE, on the move into delivered only.

create or replace function public.date_the_delivery()
returns trigger
language plpgsql
set search_path = ''
as $fn$
declare
  v_out timestamptz;
begin
  if new.status is distinct from 'delivered' or old.status = 'delivered' then
    return new;
  end if;

  select max((entry ->> 'at')::timestamptz) into v_out
    from pg_catalog.jsonb_array_elements(
           case when pg_catalog.jsonb_typeof(old.status_history) = 'array'
                then old.status_history else '[]'::jsonb end) entry
   where entry ->> 'to' = 'outForDelivery';

  new.delivered_at := least(
    pg_catalog.now(),
    greatest(coalesce(new.delivered_at, pg_catalog.now()),
             coalesce(v_out, old.created_at, pg_catalog.now())));
  return new;
end;
$fn$;

revoke all on function public.date_the_delivery() from public, anon, authenticated;

drop trigger if exists orders_date_the_delivery on public.orders;
create trigger orders_date_the_delivery
  before update of status on public.orders
  for each row execute function public.date_the_delivery();
