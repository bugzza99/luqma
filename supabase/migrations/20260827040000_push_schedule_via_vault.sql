-- Where the drain gets its URL and its secret.
--
-- The first version read them from `current_setting('app.functions_url')`, set by
-- `alter database postgres set …`. That works on the local stack and **is refused on the
-- hosted project**: setting a custom parameter needs superuser, and Supabase's `postgres`
-- role is not one.
--
--     ERROR: 42501: permission denied to set parameter "app.functions_url"
--
-- Found by running it rather than by reading about it. Vault is the place Supabase
-- provides for this, and it is a better one anyway: the secret is encrypted at rest
-- instead of sitting in a database-level setting that every session can read with
-- `current_setting`.

-- The reader. `vault.decrypted_secrets` is readable only by roles with explicit access,
-- and this function is the one thing that needs these two — so it fetches them rather
-- than the job embedding them.
create or replace function public.push_endpoint()
returns table (url text, secret text)
language plpgsql
security definer
set search_path = ''
stable
as $fn$
begin
  -- Vault is not everywhere. PGlite runs the local migration suite and has no such
  -- schema, and a `language sql` body would be parsed at creation and fail there — so
  -- the lookup is built at run time and simply returns nothing when vault is absent.
  if to_regclass('vault.decrypted_secrets') is null then
    return;
  end if;

  return query execute $q$
    select
      (select decrypted_secret from vault.decrypted_secrets
        where name = 'luqma_functions_url'),
      (select decrypted_secret from vault.decrypted_secrets
        where name = 'luqma_cron_secret')
  $q$;
end;
$fn$;

revoke all on function public.push_endpoint() from public, anon, authenticated;

-- The job, rewritten against it.
--
-- Still guarded by availability — PGlite runs the local migration suite and has neither
-- pg_cron nor vault — and still a no-op until both secrets exist, which is the right
-- failure: notifications that have not been configured yet, rather than a migration that
-- refuses to run or a job that errors every minute into the log.
do $$
declare v_cron boolean;
begin
  select count(*) > 0 into v_cron from pg_available_extensions where name = 'pg_cron';
  if not v_cron then return; end if;

  create extension if not exists pg_cron;
  create extension if not exists pg_net;

  perform cron.unschedule('luqma-send-push')
    where exists (select 1 from cron.job where jobname = 'luqma-send-push');

  perform cron.schedule('luqma-send-push', '* * * * *', $c$
    select net.http_post(
      url := e.url || '/send-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', e.secret
      ),
      body := '{}'::jsonb
    )
      from public.push_endpoint() e
     where e.url is not null and e.secret is not null
  $c$);
end;
$$;
