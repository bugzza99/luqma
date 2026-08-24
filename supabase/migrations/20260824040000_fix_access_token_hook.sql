-- The access-token hook could never actually run — found by the first real sign-in.
--
-- S1 wrote this function and its policies, but the stack tests simulated identities with
-- set_config('request.jwt.claims'), which skips the hook entirely. The first genuine
-- sign-in died with a 500: GoTrue calls this function as `supabase_auth_admin`, which had
-- no execute grant on it, no select on `staff`, and no policy that would let it through
-- RLS anyway.
--
-- Rebuilt as SECURITY DEFINER with a locked search_path: it runs as its owner, whose
-- ownership of the table is what lets it read past RLS — the same privilege shape every
-- Supabase auth hook needs. Executable by nobody but the auth server.
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$

declare
  claims jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  meta   jsonb := coalesce(claims -> 'app_metadata', '{}'::jsonb);
  s      record;
begin
  select scope, role, merchant_id
    into s
    from public.staff
   where uid = (event ->> 'user_id')::uuid
     and is_active;

  if found then
    meta := meta || jsonb_build_object('role', s.role, 'scope', s.scope);

    if s.merchant_id is not null then
      meta := meta || jsonb_build_object('merchant_id', s.merchant_id);
    end if;

    if s.role = 'admin' then
      meta := meta || jsonb_build_object('admin', true);
    end if;
  end if;

  return jsonb_set(event, '{claims,app_metadata}', meta);
end;
$$;

revoke execute on function public.custom_access_token_hook(jsonb)
  from public, anon, authenticated;
grant execute on function public.custom_access_token_hook(jsonb)
  to supabase_auth_admin;
