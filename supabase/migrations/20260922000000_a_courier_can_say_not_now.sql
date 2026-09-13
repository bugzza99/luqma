-- A courier had no way to say "not now".
--
-- A merchant can pause intake — `merchants.paused_until`, four options in a sheet, each
-- showing the exact time the shop reopens. A courier had nothing. A rider who finished
-- their shift, or stopped to eat, stayed in every shop's roster as though they were on the
-- road, and the only way anyone found out was ringing them.
--
-- The same shape as the merchant's, deliberately: this product already has a word for
-- "paused until a moment you can read off the screen", and inventing a second one — an
-- `is_available` flag somebody has to remember to turn back on — is how a rider ends up
-- invisible for three days.
alter table staff
  add column paused_until timestamptz;

comment on column public.staff.paused_until is
  'When a courier expects to be back. Null or past means available. Informational: '
  'nothing assigns orders, so this is what a shop reads before ringing them.';

-- ---------------------------------------------------------------- who may write it

-- A courier sets their own, and that is the whole of the new privilege.
--
-- `staff` is the table every policy in the database reads to decide who you are, so
-- opening it to its own subjects at all is the part worth being careful about. The policy
-- is `using` the caller's own row and `with check` the same, and the guard below refuses
-- every column but this one — so a courier may say when they are back and may not say what
-- they are.
create policy courier_pauses_self on staff
  for update to authenticated
  using (uid = (select auth.uid()))
  with check (uid = (select auth.uid()));

-- `using` alone would let a courier rewrite their own role to `owner`, or move their
-- `merchant_id` to a shop they have never worked for, both of which every predicate in
-- `20260905000000` then believes. The guard is the real boundary; the policy is what lets
-- the statement reach it at all.
create or replace function public.guard_staff_self_edit()
returns trigger
language plpgsql
as $fn$
declare
  touched text[];
begin
  -- A trusted server function, or an admin, may write anything here.
  if coalesce(current_setting('app.server_mode', true), '') = 'on'
     or public.is_admin() then
    return new;
  end if;

  -- Not the caller's own row: the policies decide that, and there is nothing to narrow.
  if new.uid is distinct from (select auth.uid()) then
    return new;
  end if;

  select coalesce(array_agg(k), '{}')
    into touched
    from jsonb_each(to_jsonb(new)) as changes(k, v)
   where v is distinct from (to_jsonb(old) -> changes.k);

  if not (touched <@ array['paused_until', 'updated_at']) then
    raise exception 'a staff account may only pause itself, not change what it is: %',
      array_to_string(
        array(select unnest(touched)
              except select unnest(array['paused_until', 'updated_at'])), ', ')
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$fn$;

create trigger staff_guard_self_edit
  before update on public.staff
  for each row execute function public.guard_staff_self_edit();
