-- Seven tables had row level security enabled and not forced.
--
-- The original schema opens with a loop over a fixed list of table names doing both:
-- `enable row level security` and `force row level security`, under a comment saying new
-- tables start denied and are opened deliberately. Every table added after that day was
-- created in its own migration and got `enable` alone — `commission_payments`,
-- `cuisines`, `device_tokens`, `item_ratings`, `merchant_cuisines`, `order_settlements`
-- and `push_outbox`.
--
-- Nothing reachable from a phone was exposed by it, and saying otherwise would overstate
-- the finding: a client connects as `anon` or `authenticated` and is never the table
-- owner, so `force` changes nothing for either. What it changes is what happens *next*.
-- Without it the owner bypasses RLS, and `security definer` functions run as the owner —
-- so a function written six months from now silently gets unrestricted access to exactly
-- these seven tables, while the same function against any of the original twenty-three
-- would still be filtered. That asymmetry is invisible at the call site, which is what
-- makes it worth closing before somebody relies on it by accident rather than on purpose.
--
-- The real fix is the test beside this migration: `supabase/test/local/rls_forced.test.js`
-- asserts the invariant over every table in `public`, so table thirty-one cannot drift
-- the way these seven did. A rule with no reader is how all seven got here.
do $$
declare t text;
begin
  foreach t in array array[
    'commission_payments', 'cuisines', 'device_tokens', 'item_ratings',
    'merchant_cuisines', 'order_settlements', 'push_outbox'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop;
end $$;
