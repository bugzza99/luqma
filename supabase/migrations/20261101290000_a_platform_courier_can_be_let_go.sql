-- A platform courier can be deleted, by an admin.
--
-- `delete_my_account` refuses every staff account, and `admin_delete_account` refused
-- every `scope = 'platform'` row, so a courier who delivered for the platform itself had
-- no way out of the product at all. The owner decided (2026-09-23): an admin deletes one
-- exactly as they delete a shop's rider — attachments deactivated, the account removed,
-- their debt and deliveries kept by the rules already written for them. Platform admins
-- and moderators stay undeletable from here.
--
-- A rider carrying an order right now is refused, shop's or platform's: deleting them
-- would null the courier on an order in the street, the same reason a customer with an
-- order on its way waits (A9).
--
-- Patched in place; each anchor must match exactly once.

do $migrate$
declare
  v_def text;
  v_old_refuse constant text := '  if v_staff_scope = ''platform'' then
    raise exception ''cannot delete platform staff''';
  v_old_kind constant text := '  if v_staff_scope = ''merchant'' and v_staff_role in (''owner'', ''courier'') then
    v_kind := v_staff_role;
  else
    v_kind := ''customer'';
  end if;';
begin
  select pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), chr(13), '') into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_delete_account';

  if (length(v_def) - length(replace(v_def, v_old_refuse, ''))) / length(v_old_refuse) <> 1
     or (length(v_def) - length(replace(v_def, v_old_kind, ''))) / length(v_old_kind) <> 1 then
    raise exception 'admin_delete_account has drifted; re-read it before patching.';
  end if;

  v_def := replace(v_def, v_old_refuse, '  if v_staff_scope = ''platform'' and v_staff_role is distinct from ''courier'' then
    raise exception ''cannot delete platform staff''');
  v_def := replace(v_def, v_old_kind, '  if (v_staff_scope = ''merchant'' and v_staff_role in (''owner'', ''courier''))
     or (v_staff_scope = ''platform'' and v_staff_role = ''courier'') then
    v_kind := v_staff_role;
  else
    v_kind := ''customer'';
  end if;

  -- Not from under an order they are carrying: it would lose its courier in the street.
  if v_kind = ''courier'' and exists (
    select 1 from public.orders
     where courier_uid = p_uid
       and status in (''placed'', ''accepted'', ''preparing'', ''outForDelivery'',
                      ''needsAttention'')
  ) then
    raise exception ''a courier carrying an order cannot be deleted until it is finished''
      using errcode = ''P0001'';
  end if;');

  execute v_def;
end;
$migrate$;
