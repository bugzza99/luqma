-- The number stays the account's, after signup as well as at it (A5).
--
-- `20261029000000` made `ensure_user_profile` derive a phone account's number from the
-- account address instead of trusting signup metadata. That closed the door at signup and
-- left the one beside it open: `users.phone` has been on the list of columns a customer
-- may write since the first schema (`users_guard_columns`, last set in
-- `20260908000000_marketing_push.sql`). One PATCH put any number on the profile, and
-- `place_order` freezes that number onto every order — the number a courier rings from
-- the street — while the admin's customer search, the only way back from a forgotten
-- password, found this account under somebody else's number.
--
-- The column stays writable, because one caller needs it: an account on a real address
-- (a staff account from `create-staff-account`) has no number to derive, and the
-- checkout asks it for one and saves it here. So the rule is per account, not per column:
-- for a phone account the number *is* the address, and every write of the row puts it
-- back. Put back rather than refused, as at signup — an older APK that sends the number
-- spelled differently is not wrong, it is just not the authority — and on every write,
-- server mode included, because nothing anywhere may make the two disagree.

create or replace function public.keep_the_account_s_number()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_email text;
begin
  select u.email into v_email from auth.users u where u.id = new.id;
  if v_email like '%@phone.luqma.app' then
    new.phone := public.normalise_phone(pg_catalog.split_part(v_email, '@', 1));
  end if;
  return new;
end;
$fn$;

revoke all on function public.keep_the_account_s_number() from public, anon, authenticated;

drop trigger if exists users_keep_the_account_s_number on public.users;
create trigger users_keep_the_account_s_number
  before insert or update of phone on public.users
  for each row execute function public.keep_the_account_s_number();

-- The name was bounded at 80 characters at signup only. `name` is on the same writable
-- list, so an update could put a megabyte in it — the cheap way to fill a free-tier
-- database that the signup bound exists to close. Checked on the table rather than in a
-- trigger, so every writer meets it. Production's longest name was 15 characters when
-- this was written.
alter table public.users
  add constraint users_name_is_a_name check (char_length(name) <= 80);
