-- A reservation is for later, so the kitchen's "not right now" does not refuse it (B9).
--
-- `place_order_priced` refused every order — pre-orders included — while the shop was
-- paused or outside its posted hours. A home kitchen that tapped the busy toggle at
-- lunch, or published a meal outside the hours on its shop, had every reservation
-- refused, and the customer was told the meal had sold out beside a counter still
-- showing portions left. The owner's decision (2026-09-23): a pre-order stays open
-- whatever the kitchen's "now" is. What decides a reservation is the meal itself — its
-- status, its day, its collection window (`meal_is_reservable`) and its portions — and
-- whether the shop is approved at all. An instant order is untouched: it is food cooked
-- now, and a kitchen that is not cooking now refuses it.
--
-- Patched in place from the current body, as every amendment to this function is: its
-- definition exists only in the database, and re-emitting an older one would revert the
-- money and availability rules that followed it. Each replacement must match exactly
-- once or the migration fails, rather than corrupting the function quietly.

do $migrate$
declare
  v_def text;
  v_new text;
  v_old_pause constant text :=
    'if v_merchant.paused_until is not null and v_merchant.paused_until > now() then';
  v_old_hours constant text :=
    'if not public.merchant_open_at(v_merchant.opening_hours, now()) then';
begin
  select pg_catalog.pg_get_functiondef(p.oid) into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'place_order_priced';

  if (length(v_def) - length(replace(v_def, v_old_pause, ''))) / length(v_old_pause) <> 1
     or (length(v_def) - length(replace(v_def, v_old_hours, ''))) / length(v_old_hours) <> 1 then
    raise exception 'place_order_priced pause/hours checks have drifted; re-read them before exempting pre-orders.';
  end if;

  v_new := replace(v_def, v_old_pause,
    'if not v_is_preorder and v_merchant.paused_until is not null and v_merchant.paused_until > now() then');
  v_new := replace(v_new, v_old_hours,
    'if not v_is_preorder and not public.merchant_open_at(v_merchant.opening_hours, now()) then');

  execute v_new;
end;
$migrate$;
