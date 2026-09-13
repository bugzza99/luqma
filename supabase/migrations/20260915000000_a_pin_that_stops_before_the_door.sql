-- The pin reached the customer's own map and stopped there.
--
-- `20260910000000_a_pin_needs_a_column.sql` gave `addresses` and `landmarks` somewhere to
-- hold a coordinate, and `SupabaseAddressRepository` writes both. What nothing did was
-- carry one across the handoff: an order freezes a **copy** of the address, because a
-- courier cannot read another person's address row and a reference would render as
-- nothing in the street — and that copy is built field by field, from a list written when
-- the columns did not exist. It named ten fields and not these two.
--
-- So the pin was saved, drawn on the customer's own map, and absent from every screen
-- that had to drive to it. The whole point of a coordinate in a city whose streets carry
-- no numbers is the person trying to find the door.
--
-- Edited by string replacement rather than rewritten. `place_order_priced` has been
-- amended four times since it was last written out in full, most recently by
-- `20260913000000` — which did the same thing for the same reason. Re-emitting a body
-- read from an older migration would silently revert whatever landed after it, and the
-- reverted parts are prepaid holds and a delivery-fee clamp: money, in both directions.
do $migrate$
declare
  v_src text;
  v_new text;
begin
  select prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'place_order_priced';

  -- `label` is the last field of the frozen copy and appears once in the function.
  v_new := replace(
    v_src,
    E'             \'apartment\', a.apartment,\n             \'label\', a.label\n           )',
    E'             \'apartment\', a.apartment,\n             \'label\', a.label,\n'
    || E'             -- Both halves or neither, which the column check already enforces\n'
    || E'             -- on the row this is copied from. An address with no pin freezes two\n'
    || E'             -- JSON nulls, which is what the phone\'s model expects; leaving the\n'
    || E'             -- keys out entirely would be the same thing to Dart and a different\n'
    || E'             -- thing to anything reading the jsonb directly.\n'
    || E'             \'lat\', a.lat,\n             \'lng\', a.lng\n           )'
  );

  if v_new = v_src then
    raise exception
      'place_order_priced no longer builds the frozen address the way this migration '
      'edits. Re-read the function and add lat/lng to the copied address by hand, or '
      'the courier keeps getting an order with no coordinate on it.';
  end if;

  execute format(
    'create or replace function public.place_order_priced(p_draft jsonb) '
    'returns jsonb language plpgsql security definer set search_path = '''' as %L',
    v_new);
end;
$migrate$;
