-- A deleted customer's address keeps a shape every installed app can read.
--
-- H-02 reduced a departing customer's frozen address to `{"zoneId": …}`: the zone because
-- the statements need it, and nothing personal. The apps parse an order's address with a
-- required `id`, so that row could not be read — and a row that cannot be read takes the
-- whole list it is in down: a shop's history, a courier's statement, the admin's customer
-- page, from the first account ever deleted. The build after this reads it either way;
-- the builds already on phones do not, so the scrub writes an empty id beside the zone.
-- An empty string names nothing and belongs to nobody.
--
-- Patched in place in both deletion paths; each must hold the expression exactly once.

do $migrate$
declare
  v_def text;
  v_fn text;
  v_old constant text := 'pg_catalog.jsonb_build_object(''zoneId'', zone_id)';
begin
  foreach v_fn in array array['delete_my_account', 'admin_delete_account'] loop
    select pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), chr(13), '') into v_def
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;

    if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
      raise exception '% has drifted; re-read it before patching.', v_fn;
    end if;

    execute replace(v_def, v_old,
      'pg_catalog.jsonb_build_object(''id'', '''', ''zoneId'', zone_id)');
  end loop;
end;
$migrate$;

-- Rows already scrubbed the old way — none on production when this was written, but a
-- restore or a test project may carry some.
do $backfill$
begin
  perform pg_catalog.set_config('app.server_mode', 'on', true);
  update public.orders
     set address = address || '{"id": ""}'::jsonb
   where address is not null
     and not (address ? 'id');
  perform pg_catalog.set_config('app.server_mode', '', true);
end;
$backfill$;
