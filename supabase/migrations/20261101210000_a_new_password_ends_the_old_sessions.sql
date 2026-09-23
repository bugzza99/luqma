-- A password an admin sets ends every session the old one opened (A17).
--
-- `reset-customer-password` changed the password and left every signed-in device signed
-- in. The call that reaches an admin is often «somebody else has my phone» or «I lent my
-- account» as much as «I forgot» — and a reset that leaves the other device inside the
-- account answers neither. GoTrue's admin sign-out needs the *user's* JWT, which the
-- function does not have; ending the sessions in the database is what `set_staff_active`
-- already does on a dismissal (20261101080000), and the next refresh on any device then
-- fails and signs it out.
--
-- Callable by the service role only: the Edge Function has already checked that the
-- caller is an active platform admin and that the target is not platform staff.

create or replace function public.end_sessions_of(p_uid uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_ended integer;
begin
  if p_uid is null then
    raise exception 'whose sessions' using errcode = '22023';
  end if;
  delete from auth.sessions where user_id = p_uid;
  get diagnostics v_ended = row_count;
  return v_ended;
end;
$fn$;

revoke all on function public.end_sessions_of(uuid) from public, anon, authenticated;
grant execute on function public.end_sessions_of(uuid) to service_role;
