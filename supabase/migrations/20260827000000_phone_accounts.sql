-- The customer's identity becomes their phone number.
--
-- Google Sign-In is gone from CustomerApp. A customer now signs up with the number they
-- already give the courier, plus a password of their own choosing.
--
-- GoTrue's *phone* identity is not what carries this: it requires an SMS provider, and
-- the CLI refuses to enable it without one ("no SMS provider is enabled. Disabling phone
-- login") even when no code would ever be sent. So the number is folded into a synthetic
-- address — `01012345678@phone.luqma.app`, see `Phone.toAccountEmail` — and GoTrue holds
-- an ordinary email identity. That domain has no mailbox and nothing is ever sent to it.
--
-- The number itself travels in the signup metadata, and this is what lands it where the
-- rest of the system reads it.

-- `ensure_user_profile` made a bare row and nothing else, because until now the phone was
-- typed at checkout and written by the client afterwards. It arrives at sign-up now, so
-- the row is made with it — `place_order` copies `users.phone` onto the order, and a
-- courier with the right door and no number to call cannot deliver.
--
-- Still idempotent, still SECURITY DEFINER (the inserting role is `supabase_auth_admin`,
-- which has no grant on `public.users`). `nullif(…, '')` on purpose: a metadata key
-- present but empty is the same as absent, and storing '' would make `users.phone` look
-- answered when it is not.
create or replace function public.ensure_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (id, name, phone)
  values (
    new.id,
    nullif(new.raw_user_meta_data ->> 'name', ''),
    nullif(new.raw_user_meta_data ->> 'phone', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;
