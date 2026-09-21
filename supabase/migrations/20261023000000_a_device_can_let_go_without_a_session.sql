-- H-10: an installation can take itself off an account without a session.
--
-- Removing a device token needs proof that the caller owns it, and until now that proof
-- was the JWT — so `forget_device_token` only works while somebody is signed in. That is
-- the wrong shape for the one moment it exists for.
--
-- The manager already handles the ordinary races well: registrations are serialised, a
-- generation counter invalidates work in flight, and a registration that lands *after*
-- sign-out has begun is immediately undone. What none of that can do is finish the job
-- once the session is gone. If that last deletion fails — the network drops, the reply is
-- lost, GoTrue has already signed out — the token stays in the client's retry set and is
-- only tried again on the next auth emission. On a phone somebody signed out of and put
-- down, that emission never comes: the old account goes on being woken on a device
-- nobody is signed into, for as long as the installation lives.
--
-- So ownership gets a second proof that does not expire with a session: a secret minted
-- per registration and handed to whoever registered. Presenting the token **and** its
-- secret revokes it, with no JWT at all.
--
-- Why that is safe to expose to `anon`: the secret is the authorisation, and it is only
-- ever returned to the client that registered. The worst a holder can do is stop their
-- own device being woken — which is the thing they were asking for.
--
-- The secret is rotated on every registration, so an account that has handed the
-- installation on cannot revoke it out from under the account that holds it now.

alter table public.device_tokens
  add column if not exists revoke_secret uuid not null default gen_random_uuid();

comment on column public.device_tokens.revoke_secret is
  'Proof of ownership that outlives the session. Returned to whoever registers, rotated '
  'on every registration, and the only thing revoke_device_token accepts.';

-- `register_device_token` returns the secret now. It returned void before, and a reply
-- with a value in it is something an older APK simply ignores — which is what makes this
-- safe to ship ahead of the phones.
-- Dropped rather than replaced: `create or replace` cannot change a return type, and
-- this one goes from void to the secret it now hands back. Nothing in the database calls
-- it — it is a client door — so there is nothing to re-point, and the grants below put
-- back what the drop takes away.
drop function if exists public.register_device_token(text);

create function public.register_device_token(p_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid    uuid := (select auth.uid());
  v_secret uuid;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  if p_token is null or pg_catalog.btrim(p_token) = '' then
    raise exception 'device token must not be empty'
      using errcode = 'invalid_parameter_value';
  end if;

  -- One row per token, because a token names an installation: two owners are
  -- structurally impossible and registering *moves* the device rather than copying it.
  insert into public.device_tokens (token, uid, revoke_secret, updated_at)
  values (pg_catalog.btrim(p_token), v_uid, pg_catalog.gen_random_uuid(), pg_catalog.now())
      on conflict (token) do update
         set uid = excluded.uid,
             -- Rotated on every registration. The account that has handed this
             -- installation on keeps a secret that no longer opens anything.
             revoke_secret = excluded.revoke_secret,
             updated_at = excluded.updated_at
  returning revoke_secret into v_secret;

  -- The legacy array on `users` is still read by an APK that writes nothing else, and is
  -- kept in step so a half-updated fleet does not resurrect an old owner.
  update public.users
     set fcm_tokens = (
       select coalesce(pg_catalog.array_agg(t), '{}')
         from pg_catalog.unnest(coalesce(fcm_tokens, '{}')) t
        where t <> pg_catalog.btrim(p_token))
   where id <> v_uid
     and fcm_tokens is not null
     and pg_catalog.btrim(p_token) = any(fcm_tokens);

  return v_secret;
end;
$fn$;

revoke all on function public.register_device_token(text) from public, anon;
grant execute on function public.register_device_token(text) to authenticated, service_role;

-- Revocation that needs no session.
--
-- Returns whether a row was removed, so a client can tell "it is gone" from "it was
-- never mine" — and a caller that gets `false` must not report a clean sign-out.
create or replace function public.revoke_device_token(p_token text, p_secret uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_deleted integer;
begin
  if p_token is null or p_secret is null then
    return false;
  end if;

  delete from public.device_tokens
   where token = pg_catalog.btrim(p_token)
     and revoke_secret = p_secret;
  get diagnostics v_deleted = row_count;

  return v_deleted > 0;
end;
$fn$;

-- `anon` on purpose: the secret is the authorisation, and the moment this exists for is
-- the moment there is no session to authorise with.
revoke all on function public.revoke_device_token(text, uuid) from public;
grant execute on function public.revoke_device_token(text, uuid)
  to anon, authenticated, service_role;
