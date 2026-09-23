-- A dismissal takes the staff powers and leaves the person a customer (A10).
--
-- `set-staff-active` banned the GoTrue user for a hundred years when somebody was
-- dismissed. Approval turns an applicant's ordinary phone account into the staff account,
-- so the ban took the whole person: a dismissed courier could no longer sign into
-- CustomerApp, order dinner, delete their account, or register the number again as
-- somebody new. The owner decided (2026-09-23) that a dismissal must not do that.
--
-- What the ban was *for* stays done, by other means. Every staff predicate already reads
-- `staff.is_active` (`20260905000000`), so a dismissed account's token opens nothing a
-- staff member can do. And the database now ends the person's sessions when they are
-- dismissed: the next refresh fails, MerchantApp signs out, and signing back in meets the
-- no-access wall — while the same number and password still open CustomerApp. The Edge
-- Function stops banning in the same change, and still lifts a ban when somebody is
-- brought back, so an account banned before this is not stranded.
--
-- Patched in place from the current body: the last-admin guard, the lock and the audit
-- entry are untouched, and the anchor must match exactly once.

do $migrate$
declare
  v_def text;
  v_anchor constant text := '  perform set_config(''app.server_mode'', v_prior_mode, true);';
begin
  select pg_catalog.pg_get_functiondef(p.oid) into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'set_staff_active';

  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'set_staff_active has drifted; re-read it before ending sessions there';
  end if;

  execute replace(v_def, v_anchor,
'  -- Dismissed: end their sessions, so the staff app has to sign in again and meets the
  -- no-access wall. The account itself stays; it is still somebody who can order (A10).
  if not p_active then
    delete from auth.sessions where user_id = p_uid;
  end if;

' || v_anchor);
end;
$migrate$;
