-- H-01, the half that is code: a customer's number comes from their account, not from
-- what the app said about them.
--
-- The owner settled the other half on 2026-09-21: **no OTP and no SMS provider**, which
-- was already the standing decision from 2026-09-04 and is now closed for signup too.
-- Public signup stays open. So the question is what the server can check without one, and
-- the answer turned out not to be about rate limits at all.
--
-- ------------------------------------------------------------------ the rate limit already exists
--
-- GoTrue caps sign-up and sign-in at **30 per five minutes per IP address**
-- (`[auth.rate_limit] sign_in_sign_ups` in `supabase/config.toml`), which is per-IP
-- limiting at the only layer that can see an IP at all. Nothing in Postgres can: a trigger
-- on `auth.users` is handed a row, not a request. A database-side cap could therefore only
-- be global, and a global cap is a switch that turns real customers away during the launch
-- in order to slow down an attacker who can simply wait. It is not built, deliberately.
--
-- ------------------------------------------------------------------ what was actually wrong
--
-- `ensure_user_profile` copied `raw_user_meta_data ->> 'phone'` onto the profile with no
-- check of any kind. That column is where `place_order` reads the number it freezes onto
-- the order — **the number the courier rings from the street** — and it is also what the
-- admin's customer search matches when somebody telephones having forgotten their
-- password.
--
-- The account's real identity is elsewhere: a customer signs in with a number folded into
-- a synthetic address, `01012345678@phone.luqma.app`. Nothing made the two agree. So an
-- app — or anything posting to GoTrue — could hold an account on one number and put a
-- different one on the profile, and every order would carry a number that reaches somebody
-- else. Not a theft so much as a courier at the right door ringing the wrong person, and a
-- support call that finds no account.
--
-- The number is derived from the address now. One source of truth rather than two that can
-- disagree, and it is the check `application_phone_is_the_applicant_s` already makes for a
-- staff application — reached from the other end.
--
-- An account on a real address — staff made by `create-staff-account` — keeps the metadata
-- number, because for those the address is an email and carries no number to derive.
create or replace function public.ensure_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_phone text;
  v_name  text;
begin
  if new.email like '%@phone.luqma.app' then
    -- The address is the account. Whatever the client said about itself is ignored
    -- rather than refused: an older APK that sends the number formatted differently is
    -- not wrong, it is just not the authority.
    v_phone := public.normalise_phone(pg_catalog.split_part(new.email, '@', 1));
  else
    v_phone := public.normalise_phone(
      nullif(new.raw_user_meta_data ->> 'phone', ''));
  end if;

  -- A name is the one thing here that is genuinely the person's to choose, so it is kept
  -- — bounded. Signup metadata is client-controlled and unbounded, and a profile row with
  -- a megabyte in it is a cheap way to fill a free-tier database.
  v_name := nullif(
    pg_catalog.left(pg_catalog.btrim(coalesce(new.raw_user_meta_data ->> 'name', '')), 80),
    '');

  insert into public.users (id, name, phone)
  values (new.id, v_name, nullif(v_phone, ''))
  on conflict (id) do nothing;

  return new;
end;
$$;

comment on function public.ensure_user_profile() is
  'Makes the profile row for a new account. The phone is derived from the account address '
  'for a customer, never taken from signup metadata: it is the number a courier rings and '
  'the number an admin searches, and two sources that can disagree is one too many.';
