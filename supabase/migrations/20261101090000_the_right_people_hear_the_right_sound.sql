-- Who is woken, and how loudly (D5, A16).
--
-- D5. An order nobody answered alerted platform admins only, while AdminApp's banner
-- told a moderator «أوردر محدش ردّ عليه بيوصلك بتنبيه». Watching that queue is what the
-- role is for, and the owner decided (2026-09-23) that a moderator is alerted too.
--
-- A16. A new join application — and the «حسابك اتفعّل» that answers one — went out on
-- `orders_critical`: the alarm channel, created at MAX importance, which bypasses Do Not
-- Disturb. Anybody able to sign up could ring every admin's phone at three in the
-- morning, the lesson the Saturday commission reminder already taught once. Neither is an
-- order waiting on a kitchen. Both go on the quiet `orders` channel, which AdminApp and
-- MerchantApp both create (`push_channels_test.dart` checks that they do).
--
-- Patched in place from the current bodies, each anchor matched exactly once.

do $migrate$
declare
  v_def text;

begin
  -- D5: the unanswered-order alert, to moderators as well.
  select pg_catalog.pg_get_functiondef('public.queue_admin_attention_push()'::regprocedure)
    into v_def;
  if (length(v_def) - length(replace(v_def,
        'where scope = ''platform'' and role = ''admin'' and is_active', '')))
     / length('where scope = ''platform'' and role = ''admin'' and is_active') <> 1 then
    raise exception 'queue_admin_attention_push has drifted';
  end if;
  execute replace(v_def,
    'where scope = ''platform'' and role = ''admin'' and is_active',
    'where scope = ''platform'' and role in (''admin'', ''moderator'') and is_active');

  -- A16: a new application, on the quiet channel.
  select pg_catalog.pg_get_functiondef('public.notify_admins_of_application()'::regprocedure)
    into v_def;
  if (length(v_def) - length(replace(v_def, '''orders_critical''', '')))
     / length('''orders_critical''') <> 1 then
    raise exception 'notify_admins_of_application has drifted';
  end if;
  execute replace(v_def, '''orders_critical''', '''orders''');

  -- A16: «حسابك اتفعّل», on the quiet channel.
  select pg_catalog.pg_get_functiondef(p.oid) into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'approve_staff_application';
  if (length(v_def) - length(replace(v_def, '''orders_critical''', '')))
     / length('''orders_critical''') <> 1 then
    raise exception 'approve_staff_application has drifted';
  end if;
  execute replace(v_def, '''orders_critical''', '''orders''');
end;
$migrate$;
