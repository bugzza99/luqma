-- An account cannot be deleted while an order of theirs is on its way, and a deleted
-- account leaves no free text behind (A9).
--
-- Both deletion paths — `delete_my_account` from CustomerApp and `admin_delete_account`
-- from AdminApp — scrubbed every order of the departing customer at once, whatever its
-- status. An order out for delivery lost its street and its phone number while a courier
-- was carrying it: food in the street with nowhere to go and nobody to ring. The owner
-- decided (2026-09-23) that deletion waits until the order is finished. The refusal is
-- raised by name, and the apps say it in words: finish or cancel the order first.
--
-- And the scrub left `orders.note` and each line's `note` — free text the customer typed,
-- which is exactly where somebody writes «ورا بيت الحاج فلان، رن على 0100…». H-02 kept
-- the zone and nothing else of the address; the same reasoning takes the notes. The food,
-- the prices and the money stay, because the ledger is built from them.
--
-- Patched in place from the current bodies rather than re-created from a file:
-- `admin_delete_account` was rewritten in place by `20261024000000` (it asks
-- `is_platform_admin()` now), and re-emitting an older definition would quietly hand the
-- delete back to a moderator. Every anchor must match exactly once or nothing changes.

do $migrate$
declare
  v_fn   record;
  v_def  text;
  v_uid  text;
  v_anchor_mode  constant text := '  v_prior_mode := coalesce(';
  v_anchor_scrub constant text :=
    'address = pg_catalog.jsonb_build_object(''zoneId'', zone_id)';
  v_check text;
  v_notes constant text :=
    'address = pg_catalog.jsonb_build_object(''zoneId'', zone_id),
         note = null,
         items = coalesce(
           (select pg_catalog.jsonb_agg(line.value - ''note'' order by line.ordinality)
              from pg_catalog.jsonb_array_elements(items)
                   with ordinality as line(value, ordinality)),
           items)';
begin
  for v_fn in
    select * from (values ('delete_my_account', 'v_uid'),
                          ('admin_delete_account', 'p_uid')) as f(name, uid_var)
  loop
    select pg_catalog.pg_get_functiondef(p.oid) into v_def
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn.name;

    if (length(v_def) - length(replace(v_def, v_anchor_mode, ''))) / length(v_anchor_mode) <> 1
       or (length(v_def) - length(replace(v_def, v_anchor_scrub, ''))) / length(v_anchor_scrub) <> 1
    then
      raise exception '% has drifted; re-read it before patching the deletion rules', v_fn.name;
    end if;

    v_check := format(
'  -- Not while an order is on its way: scrubbing it would take the street and the phone
  -- off an order a courier is carrying. Finished or cancelled first (A9).
  if exists (
    select 1 from public.orders
     where customer_uid = %s
       and status in (''placed'', ''accepted'', ''preparing'', ''outForDelivery'',
                      ''needsAttention'')
  ) then
    raise exception ''an order is still on its way'' using errcode = ''P0001'';
  end if;

', v_fn.uid_var);

    v_def := replace(v_def, v_anchor_mode, v_check || v_anchor_mode);
    v_def := replace(v_def, v_anchor_scrub, v_notes);
    execute v_def;
  end loop;
end;
$migrate$;
