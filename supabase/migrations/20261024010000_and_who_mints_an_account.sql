-- H-08, the second half: the four functions that mint or re-point an identity.
--
-- `20261024000000` narrowed the money and the deletions, and took `staff`,
-- `courier_merchants`, `config` and `plans` back with a BEFORE trigger. The trigger is
-- the boundary and it holds — but four functions that write those tables still ask the
-- *wide* question at their own door, so a moderator calling one gets as far as the write
-- and is refused from inside it.
--
-- That is a correct refusal at the wrong depth. The error names a trigger rather than the
-- thing the caller asked for, an audit row may already have been written, and any future
-- work added before the write happens anyway. A door that is going to be shut should be
-- shut at the door.
--
-- `set_staff_active` is deliberately not here: it already reads the actor's row and
-- demands `role = 'admin'`, and it is granted to `service_role` alone because an Edge
-- Function verifies the caller first. It was written strictly before there was a name for
-- strict.
--
-- `review_staff_application` is deliberately not here either, and that is the point of
-- the role. Reading the queue and *rejecting* an application is moderation; it mints
-- nothing. Only approval creates an account, and only approval is taken away.
--
-- Why swapping the question in eighteen functions is safe to do in bulk: for every caller
-- the product can produce, it changes the answer for a moderator and for nobody else.
-- `is_admin()` is the claim plus an active platform row of either role; `is_platform_admin()`
-- is an active platform row of role admin. A service key and a cron job have no
-- `auth.uid()`, so both were already false and stay false — the narrowing cannot break a
-- caller that was never getting through.
--
-- The one case where the narrow question says yes and the wide one said no is a real
-- platform admin holding a token with no `admin` claim. That is unreachable rather than
-- tolerated: the claim is stamped by our own access-token hook, which GoTrue signs, so a
-- client cannot present a token it has taken the claim out of. And if it ever were
-- reachable, the row is the better authority — which is the whole reason
-- `is_platform_admin()` reads the row.

do $body$
declare
  fn  text;
  def text;
  n   integer := 0;
begin
  foreach fn in array array[
    -- The control plane: `default_commission_percent` is money by another name and
    -- `min_supported_version` walls every customer out with no back door.
    'admin_set_config',
    -- Each of these three ends in a `staff` or `courier_merchants` row, which is what
    -- every policy in the database reads to decide who you are.
    'approve_staff_application',
    'attach_courier_by_phone',
    'create_staff_profile'
  ] loop
    for def in
      select pg_catalog.pg_get_functiondef(p.oid)
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace nsp on nsp.oid = p.pronamespace
       where nsp.nspname = 'public' and p.proname = fn
    loop
      if def like '%public.is_admin()%' then
        execute pg_catalog.replace(def, 'public.is_admin()', 'public.is_platform_admin()');
        n := n + 1;
      end if;
    end loop;
  end loop;

  -- Loudly, rather than silently doing nothing. A rename upstream would otherwise leave
  -- this migration applied, green, and having changed nothing at all.
  if n <> 4 then
    raise exception 'expected to narrow 4 functions, narrowed %', n
      using errcode = 'check_violation';
  end if;
end;
$body$;
