-- An order nobody answered can be let go by the person waiting for it.
--
-- An order moves to `needsAttention` when the shop lets its accept deadline pass, and
-- only an admin could move it from there. At night nobody does: the customer sat in front
-- of «بيحتاج مراجعة» with no button, and a prepaid shop's hold stayed held. The owner
-- decided (2026-09-23): after fifteen minutes in that state the customer may cancel it
-- themselves. The fifteen minutes are the admin's chance to rescue the order by ringing
-- the shop; after that, waiting helps nobody.
--
-- "In that state since" is read from the order's own history — the last entry that moved
-- it to needsAttention — and falls back to the accept deadline, which is when the
-- escalation would have fired. `needs_attention_since` is the one place that answers it;
-- the phone asks the same question of the same history (`Order.customerMayCancelAt`).
--
-- The customer's cancellation then takes the ordinary path: the coupon comes back, the
-- prepaid hold is released and the shop is told, exactly as for a cancel while `placed`.

create or replace function public.needs_attention_since(p_order public.orders)
returns timestamptz
language sql
stable
set search_path = ''
as $fn$
  select coalesce(
    (select max((entry ->> 'at')::timestamptz)
       from pg_catalog.jsonb_array_elements(
              case when pg_catalog.jsonb_typeof(p_order.status_history) = 'array'
                   then p_order.status_history else '[]'::jsonb end) entry
      where entry ->> 'to' = 'needsAttention'),
    p_order.accept_deadline_at,
    p_order.updated_at);
$fn$;

revoke all on function public.needs_attention_since(public.orders) from public, anon;
grant execute on function public.needs_attention_since(public.orders) to authenticated;

do $migrate$
declare
  v_def text;
  v_old constant text :=
    '(actor = ''customer'' and old.status = ''placed'' and new.status = ''cancelled'')';
begin
  select pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), chr(13), '') into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'enforce_order_transition';

  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'enforce_order_transition has drifted; re-read it before patching.';
  end if;

  execute replace(v_def, v_old, '(actor = ''customer'' and new.status = ''cancelled'' and (
         old.status = ''placed''
      -- Fifteen minutes unanswered after the escalation: the admin had their chance.
      or (old.status = ''needsAttention''
          and public.needs_attention_since(old) <= now() - interval ''15 minutes'')))');
end;
$migrate$;
