-- SNAPSHOT of public.delete_my_account as it runs — written by snapshot-functions.mjs.
-- Documentation only: never applied. Change it with a migration.

CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_orders_scrubbed integer;
  v_prior_mode text;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  -- An already-deleted GoTrue row makes a retry a success. A phone can lose the first
  -- response after the transaction commits, and asking it to distinguish that from a
  -- failed request would make an irreversible action look uncertain.
  perform 1 from auth.users where id = v_uid for update;
  if not found then
    return;
  end if;

  -- Shop ownership and delivery authority outlive a customer-app screen. Removing either
  -- needs an administrator who can hand the responsibility to somebody else first.
  if exists (select 1 from public.staff where uid = v_uid) then
    raise exception 'staff accounts require administrative deletion'
      using errcode = 'insufficient_privilege';
  end if;

  -- `guard_order_columns` asks whether a trusted server function has declared itself, not
  -- who owns the function -- `security definer` does not satisfy it, and without this the
  -- scrub below is refused outright with "column not yours to change on an order".
  --
  -- It has to cover the deletion as well: `orders.customer_uid` is `on delete set null`,
  -- and that referential action runs as an ordinary update, firing the same guard on a
  -- column no role is ever allowed to write.
  --
  -- Restored rather than left standing, because the setting is transaction-local and this
  -- runs inside the caller's transaction -- leaving it on would stand every guard down for
  -- whatever that transaction did next.
  -- Not while an order is on its way: scrubbing it would take the street and the phone
  -- off an order a courier is carrying. Finished or cancelled first (A9).
  if exists (
    select 1 from public.orders
     where customer_uid = v_uid
       and status in ('placed', 'accepted', 'preparing', 'outForDelivery',
                      'needsAttention')
  ) then
    raise exception 'an order is still on its way' using errcode = 'P0001';
  end if;

  -- An application that never became an account leaves with its applicant: the
  -- name, number and note in it are theirs.
  delete from public.staff_applications
   where applicant_uid = v_uid and status <> 'approved';

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  -- The contact marker explains why the person is gone. The address keeps only the broad
  -- zone needed by the financial record; no empty personal-detail keys survive.
  update public.orders
     set customer_name = 'حساب محذوف',
         customer_phone = 'حساب محذوف',
         address = pg_catalog.jsonb_build_object('zoneId', zone_id),
         note = null,
         items = coalesce(
           (select pg_catalog.jsonb_agg(line.value - 'note' order by line.ordinality)
              from pg_catalog.jsonb_array_elements(items)
                   with ordinality as line(value, ordinality)),
           items)
   where customer_uid = v_uid;
  get diagnostics v_orders_scrubbed = row_count;

  -- The transaction makes this entry proof that the scrub and GoTrue deletion both
  -- completed. Detail keeps only the channel and counts needed to audit the event;
  -- deliberately no uid, name, phone, or other personal data survives in it.
  insert into public.audit_log (action, actor, detail)
  values (
    'customer.account_deleted',
    v_uid,
    pg_catalog.jsonb_build_object(
      'source', 'customer_app',
      'ordersScrubbed', v_orders_scrubbed,
      'authUserDeleted', true
    )
  );

  -- Existing cascades remove the profile, addresses, ratings, tokens and sessions. The
  -- orders reference is set null; settlement rows still restrict deletion of the orders
  -- themselves, so the ledger remains intact.
  delete from auth.users where id = v_uid;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);
end;
$function$;
