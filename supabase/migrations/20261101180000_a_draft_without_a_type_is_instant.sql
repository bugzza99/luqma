-- A draft that names no type is an instant order, and is judged as one.
--
-- `place_order_priced` stored a missing `type` as 'instant' (`coalesce(... , 'instant')`)
-- but asked every question about it as `p_draft ->> 'type' = 'preorder'` — NULL, not
-- false, when the key is absent. `not NULL` is NULL, so the pause check, the hours check
-- and the minimum order were each skipped, and `<> 'preorder'` skipped the accept
-- deadline: an order a paused shop could not refuse and no timer would ever escalate.
-- The app always sends a type; a hand-written request did not have to. A type that is
-- neither is still refused by the column's own check, with everything else rolled back.
--
-- Patched in place from the current body, as every amendment to this function is. Each
-- replacement must match exactly once or the migration fails. Carriage returns are taken
-- out first: a body stored through a Windows client carries them, and an anchor that
-- straddles a line then matches nothing.

do $migrate$
declare
  v_def text;
  v_old_flag constant text :=
    'v_is_preorder boolean := p_draft ->> ''type'' = ''preorder'';';
  v_old_take constant text :=
    'if p_draft ->> ''type'' = ''preorder'' then';
  v_old_deadline constant text :=
    'if p_draft ->> ''type'' <> ''preorder'' then';
begin
  select pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), chr(13), '') into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'place_order_priced';

  if (length(v_def) - length(replace(v_def, v_old_flag, ''))) / length(v_old_flag) <> 1
     or (length(v_def) - length(replace(v_def, v_old_take, ''))) / length(v_old_take) <> 1
     or (length(v_def) - length(replace(v_def, v_old_deadline, ''))) / length(v_old_deadline) <> 1 then
    raise exception 'place_order_priced type checks have drifted; re-read them before patching.';
  end if;

  v_def := replace(v_def, v_old_flag,
    'v_is_preorder boolean := coalesce(p_draft ->> ''type'', ''instant'') = ''preorder'';');
  v_def := replace(v_def, v_old_take, 'if v_is_preorder then');
  v_def := replace(v_def, v_old_deadline, 'if not v_is_preorder then');

  execute v_def;
end;
$migrate$;
