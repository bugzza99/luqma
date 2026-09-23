-- Food to be delivered names where it goes.
--
-- `place_order_priced` took an instant order with no `addressId` down the pre-order's
-- collection branch: the shop's own zone, a delivery fee of zero and a null address — a
-- courier sent out with nowhere to go, and the trip charged at nothing. The app never
-- sends one; a hand-written request could. A reservation without an address is still
-- collected by the person who made it, so only the instant order is refused, and as a
-- bad request (22023) rather than as a shop saying no.
--
-- Patched in place from the current body, after 20261101180000 made `v_is_preorder`
-- mean what it says for a draft with no type. The anchor must match exactly once.

do $migrate$
declare
  v_def text;
  v_old constant text := '  else
    v_zone_id := v_merchant.zone_id;
    v_delivery := 0;
  end if;';
begin
  select pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), chr(13), '') into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'place_order_priced';

  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'place_order_priced address branch has drifted; re-read it before patching.';
  end if;

  v_def := replace(v_def, v_old, '  elsif not v_is_preorder then
    raise exception ''an order to be delivered names its address'' using errcode = ''22023'';
  else
    v_zone_id := v_merchant.zone_id;
    v_delivery := 0;
  end if;');

  execute v_def;
end;
$migrate$;
