-- SNAPSHOT of public.set_staff_active as it runs — written by snapshot-functions.mjs.
-- Documentation only: never applied. Change it with a migration.

CREATE OR REPLACE FUNCTION public.set_staff_active(p_uid uuid, p_active boolean, p_actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_target public.staff;
  v_prior_mode text;
begin
  perform pg_advisory_xact_lock(20260905);

  if not exists (
    select 1
      from public.staff s
     where s.uid = p_actor
       and s.scope = 'platform'
       and s.role = 'admin'
       and s.is_active
  ) then
    raise exception 'only an active platform admin changes staff access'
      using errcode = 'insufficient_privilege';
  end if;

  select *
    into v_target
    from public.staff
   where uid = p_uid
   for update;

  if not found then
    raise exception 'no such staff account' using errcode = 'P0002';
  end if;

  if not p_active
     and v_target.is_active
     and v_target.scope = 'platform'
     and v_target.role = 'admin'
     and not exists (
       select 1
         from public.staff s
        where s.scope = 'platform'
          and s.role = 'admin'
          and s.is_active
          and s.uid <> p_uid
     ) then
    raise exception 'last active platform admin' using errcode = 'check_violation';
  end if;

  v_prior_mode := coalesce(current_setting('app.server_mode', true), '');
  perform set_config('app.server_mode', 'on', true);

  update public.staff
     set is_active = p_active,
         updated_at = now()
   where uid = p_uid;

  -- Dismissed: end their sessions, so the staff app has to sign in again and meets the
  -- no-access wall. The account itself stays; it is still somebody who can order (A10).
  if not p_active then
    delete from auth.sessions where user_id = p_uid;
  end if;

  perform set_config('app.server_mode', v_prior_mode, true);

  insert into public.audit_log (action, actor, merchant_id, detail)
  values ('staff.active_changed', p_actor, v_target.merchant_id,
          jsonb_build_object(
            'uid', p_uid,
            'active', p_active,
            'previous', v_target.is_active
          ));
end;
$function$;
