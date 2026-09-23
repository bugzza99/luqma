-- A second charge on the same order is written with its own figures (A15).
--
-- Both settlement functions keep one row per order and upsert it: a reversal marks it,
-- and a later re-delivery charges again. The `on conflict` clause reset the two
-- timestamps and nothing else. So an order that was delivered, reopened by an admin,
-- handed to a different courier and delivered again charged the *second* courier on their
-- balance while the row still named the first, with the first charge's basis and rate —
-- and the next reversal read that row back and refunded the first courier an amount the
-- second had been charged. The same shape on the shop's side: a re-charge under a rate
-- that had changed moved `commission_owed` by the new amount while the row kept the old.
--
-- The row now takes the figures of the charge that is actually being made. On a reversal
-- those are the figures read back off the row itself, so writing them again changes
-- nothing there; on a charge they are the fresh ones.
--
-- Patched in place from the current bodies, each anchor matched exactly once.

do $migrate$
declare
  v_def text;
  v_anchor text;
begin
  select pg_catalog.pg_get_functiondef('public.apply_courier_settlement(uuid, boolean)'::regprocedure)
    into v_def;
  v_anchor := 'on conflict (order_id) do update
         set reversed_at = case when p_charged then null else pg_catalog.now() end,';
  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'apply_courier_settlement has drifted; re-read its upsert';
  end if;
  execute replace(v_def, v_anchor,
'on conflict (order_id) do update
         set courier_uid = excluded.courier_uid,
             basis       = excluded.basis,
             bps         = excluded.bps,
             amount      = excluded.amount,
             ground      = excluded.ground,
             reversed_at = case when p_charged then null else pg_catalog.now() end,');

  select pg_catalog.pg_get_functiondef('public.apply_order_settlement(uuid, boolean)'::regprocedure)
    into v_def;
  v_anchor := 'on conflict (order_id) do update
         set reversed_at = case when p_charged then null else now() end,';
  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'apply_order_settlement has drifted; re-read its upsert';
  end if;
  execute replace(v_def, v_anchor,
'on conflict (order_id) do update
         set merchant_id   = excluded.merchant_id,
             model         = excluded.model,
             basis         = excluded.basis,
             amount        = excluded.amount,
             platform_owes = excluded.platform_owes,
             reversed_at   = case when p_charged then null else now() end,');
end;
$migrate$;
