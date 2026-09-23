-- An application leaves with the person who filed it.
--
-- Somebody who applied to deliver or to open a shop and then deleted their account before
-- anybody approved them left the application behind: `applicant_uid` went to null and the
-- name, the telephone number and what they wrote about themselves stayed in the admin's
-- queue with nobody attached. Both deletion paths now remove every application of theirs
-- that never became an account. An approved one is the record of a hiring and stays.
--
-- Patched in place just before each function declares server mode; each anchor must match
-- exactly once.

do $migrate$
declare
  v_def text;
  v_fn text;
  v_var text;
  v_anchor constant text :=
    '  v_prior_mode := coalesce(pg_catalog.current_setting(''app.server_mode'', true), '''');';
begin
  foreach v_fn in array array['delete_my_account', 'admin_delete_account'] loop
    v_var := case v_fn when 'delete_my_account' then 'v_uid' else 'p_uid' end;

    select pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), chr(13), '') into v_def
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_fn;

    if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
      raise exception '% has drifted; re-read it before patching.', v_fn;
    end if;

    execute replace(v_def, v_anchor,
      '  -- An application that never became an account leaves with its applicant: the
  -- name, number and note in it are theirs.
  delete from public.staff_applications
   where applicant_uid = ' || v_var || ' and status <> ''approved'';

' || v_anchor);
  end loop;
end;
$migrate$;
