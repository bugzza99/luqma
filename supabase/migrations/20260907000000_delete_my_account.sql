-- A paid order is a financial record, not an account profile.
--
-- The customer reference used to make those two things inseparable: deleting the
-- GoTrue user was refused as soon as they had placed one order. The order now survives
-- without an owner, while the two frozen contact fields stop identifying the person.
alter table public.orders
  drop constraint orders_customer_uid_fkey;

alter table public.orders
  alter column customer_uid drop not null;

alter table public.orders
  add constraint orders_customer_uid_fkey
  foreign key (customer_uid) references auth.users on delete set null;

-- A merchant already has to own the promoted shop, but the old policy did not bind the
-- requester column to that owner. Without this equality a forged customer uid could put
-- the unrelated customer behind this table's deliberate delete restriction.
drop policy merchant_requests_promotion on public.promotions;
create policy merchant_requests_promotion on public.promotions
  for insert to authenticated
  with check (
    public.is_merchant_owner(merchant_id)
    and requested_by = auth.uid()
    and status = 'requested'
  );

-- An order may still move after its account is gone. `push_outbox.uid` is correctly not
-- nullable, so trying to notify nobody would otherwise abort the merchant or courier's
-- status change and turn anonymisation into an operational lock on the retained order.
create or replace function public.queue_order_status_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_title text;
  v_body  text;
begin
  if new.status is not distinct from old.status or new.customer_uid is null then
    return new;
  end if;

  case new.status
    when 'accepted' then
      v_title := 'اتقبل طلبك';
      v_body  := new.merchant_name || ' بدأ يحضّر الأوردر.';
    when 'outForDelivery' then
      v_title := 'الأوردر في الطريق';
      v_body  := 'الطلب خرج من ' || new.merchant_name || ' وجاي لك.';
    when 'cancelled' then
      v_title := 'الأوردر اتلغى';
      v_body  := 'الأوردر من ' || new.merchant_name
                 || ' اتلغى. كلّمنا لو محتاج مساعدة.';
    else
      return new;
  end case;

  insert into public.push_outbox (uid, title, body, data, channel)
  values (
    new.customer_uid,
    v_title,
    v_body,
    pg_catalog.jsonb_build_object('kind', 'orderStatus', 'orderId', new.id::text),
    -- `orders`, not `orders_critical`: the critical channel carries the looping alarm
    -- built for a merchant who is cooking and not looking at their phone. Waking a
    -- customer that way to say their food is on the way is how somebody silences the app.
    'orders'
  );

  return new;
end;
$fn$;

-- A customer may remove only the account represented by the caller's JWT. There is no
-- uid argument because an identifier supplied by the phone would turn self-service into
-- a way to ask for somebody else's deletion.
create function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
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
  -- who owns the function — `security definer` does not satisfy it, and without this the
  -- scrub below is refused outright with "column not yours to change on an order".
  --
  -- It has to cover the deletion as well: `orders.customer_uid` is `on delete set null`,
  -- and that referential action runs as an ordinary update, firing the same guard on a
  -- column no role is ever allowed to write.
  --
  -- Restored rather than left standing, because the setting is transaction-local and this
  -- runs inside the caller's transaction — leaving it on would stand every guard down for
  -- whatever that transaction did next.
  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  -- One visible marker in both fields is deliberate: a blank name looks like a broken
  -- courier screen, while this says why neither a person nor a callable number remains.
  update public.orders
     set customer_name = 'حساب محذوف',
         customer_phone = 'حساب محذوف'
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
$fn$;

revoke all on function public.delete_my_account() from public, anon, service_role;
grant execute on function public.delete_my_account() to authenticated;
