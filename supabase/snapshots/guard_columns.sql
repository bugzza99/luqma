-- SNAPSHOT of public.guard_columns as it runs — written by snapshot-functions.mjs.
-- Documentation only: never applied. Change it with a migration.

CREATE OR REPLACE FUNCTION public.guard_columns()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  allowed text[] := tg_argv[0]::text[] || array['updated_at'];
  touched text[];
begin
  -- A trusted server function has declared itself; every column is theirs to move.
  if coalesce(current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  if public.is_admin() then
    return new;
  end if;

  select coalesce(array_agg(k), '{}')
    into touched
    from jsonb_each(to_jsonb(new)) as changes(k, v)
   where v is distinct from (to_jsonb(old) -> changes.k)
     and changes.k not in (
           select a.attname from pg_catalog.pg_attribute a
            where a.attrelid = tg_relid and a.attgenerated <> '');

  if not (touched <@ allowed) then
    raise exception 'column not yours to change on %: %',
      tg_table_name,
      array_to_string(
        array(select unnest(touched) except select unnest(allowed)), ', '
      )
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$function$;
