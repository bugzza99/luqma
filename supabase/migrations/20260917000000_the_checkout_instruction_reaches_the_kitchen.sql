-- The customer has been typing this since Phase 3, but only the dish notes had a
-- column to land in. This is the instruction for the whole order: it must survive
-- placement before either the person accepting it or the person cooking can read it.
--
-- Deliberately absent from guard_order_columns' allowed arrays. Placement writes the
-- snapshot once; a customer must not change the request after it has been read, and
-- a merchant must not rewrite what was asked for. The existing server/admin exception
-- stays as it is for the same reasons it exists for the other frozen order fields.
alter table public.orders add column note text;

-- Match check_draft_bounds' existing five-hundred-character input limit. Refuse
-- excess rather than silently cutting off the last instruction; the column constraint
-- also covers trusted direct writes, which never pass through the draft validator.
alter table public.orders add constraint orders_note_length
  check (char_length(note) <= 500);

-- Read the current body, as the address-pin migration does. Re-emitting an older
-- definition here would revert the money and availability amendments that followed it.
do $migrate$
declare
  v_src text;
  v_new text;
begin
  select prosrc into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'place_order_priced';

  v_new := replace(
    v_src,
    'status, daily_meal_id, coupon_code, accept_deadline_at)',
    'status, daily_meal_id, coupon_code, accept_deadline_at, note)'
  );
  if v_new = v_src or v_new is null then
    raise exception 'place_order_priced order columns have drifted; re-read the insert before adding note.';
  end if;
  v_src := v_new;
  -- `v_deadline)` closes the insert's value list and occurs nowhere else in this body.
  -- A pattern that matched twice would corrupt the function rather than fail loudly, so
  -- keep it that specific if it ever has to be re-aimed.
  v_new := replace(
    v_src,
    'v_deadline)',
    'v_deadline, nullif(btrim(p_draft ->> ''note'', E'' \t\n\r\f'' || chr(11)), ''''))'
  );
  if v_new = v_src then
    raise exception 'place_order_priced order values have drifted; re-read the insert before adding note.';
  end if;

  execute format(
    'create or replace function public.place_order_priced(p_draft jsonb) '
    'returns jsonb language plpgsql security definer set search_path = '''' as %L',
    v_new);
end;
$migrate$;
