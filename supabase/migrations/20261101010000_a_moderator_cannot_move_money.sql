-- A moderator is an admin except money — and three doors to the money were still open.
--
-- `20261024000000` widened `is_admin()` to answer for a moderator and then took the money
-- back by narrowing fourteen named functions. Three things it did not reach:
--
--   * `admin_set_revenue_model` was not on the list. It was written four migrations
--     earlier (H-09) and asks the wide question, so a moderator could open a shop's billing
--     screen and set prepaid at one piastre an order — or a fee larger than the wallet, so
--     the shop stops taking orders at all.
--   * `guard_columns()` steps aside for `is_admin()`, and `merchants` carries a `for all`
--     policy gated on the same question. So a moderator could PATCH `wallet_balance`,
--     `commission_owed` or `plan_expires_at` straight through PostgREST. The narrow trigger
--     H-09 added closes `status` and the revenue model and nothing else.
--   * `guard_order_columns()` and `enforce_order_transition()` both return early for
--     `is_admin()`. A moderator could rewrite an order's `pricing` and then mark it
--     `delivered` — the transition that fires settlement, on the rewritten figures.
--
-- None of those direct writes reached `audit_log`.
--
-- The second half of this file answers Astra's review of the first: every guard above runs
-- on UPDATE, and the same `for all` policies hand out INSERT. An order written from
-- nothing, a shop born with a balance, and a subscription term typed straight into its
-- table all went round them — and the one order write a moderator is meant to keep, the
-- «اليوم» cancel, had never worked at all.

-- ------------------------------------------------------------------ the revenue model

-- The same rewrite-in-place as `20261024000000`: read the body, swap the question, put it
-- back, so the grants, the owner and any default survive a `create or replace`.
do $body$
declare
  def text;
  n   integer := 0;
begin
  for def in
    select pg_catalog.pg_get_functiondef(p.oid)
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace nsp on nsp.oid = p.pronamespace
     where nsp.nspname = 'public' and p.proname = 'admin_set_revenue_model'
  loop
    if def like '%public.is_admin()%' then
      execute pg_catalog.replace(def, 'public.is_admin()', 'public.is_platform_admin()');
      n := n + 1;
    end if;
  end loop;

  -- Loudly, rather than silently doing nothing: a rename upstream would otherwise leave
  -- this migration applied, green, and the door still open.
  if n <> 1 then
    raise exception 'expected to narrow 1 function, narrowed %', n
      using errcode = 'check_violation';
  end if;

  -- And read back, rather than trusting the loop: every overload, not just the one it met.
  if exists (
    select 1
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace nsp on nsp.oid = p.pronamespace
     where nsp.nspname = 'public'
       and p.proname = 'admin_set_revenue_model'
       and pg_catalog.pg_get_functiondef(p.oid) like '%public.is_admin()%'
  ) then
    raise exception 'admin_set_revenue_model still asks is_admin()'
      using errcode = 'check_violation';
  end if;
end;
$body$;

-- ------------------------------------------------------------------ a shop's money

-- Refused to *every* authenticated caller, platform admin included, and not only to a
-- moderator. H-09 settled that a sensitive admin write goes through a function that writes
-- its evidence with it, and a wallet or a commission balance is the most sensitive column
-- in the product: `top_up_wallet`, `record_commission_payment` and
-- `record_subscription_payment` each write a receipt and an audit row beside the balance,
-- and a PATCH does neither.
--
-- That is safe to do because nothing on a phone writes these columns with a changed
-- value. They move only inside functions that declare server mode — settlement, the
-- prepaid hold, the three payment functions, `admin_set_shop_commission` and the nightly
-- plan pass. A whole-row save (`MerchantRepository.rowFor`) re-sends `plan_id` unchanged,
-- and `is distinct from` lets an unchanged value through.
--
-- The existing function is widened rather than a second trigger added beside it. It is
-- the same rule — "this column moves through an admin RPC" — asked of more columns, and
-- two triggers saying it would be two places for the next column to be added to only one.
create or replace function public.require_merchant_decision_rpc()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if coalesce(pg_catalog.current_setting('role', true), '') = 'authenticated'
     and coalesce(pg_catalog.current_setting('app.server_mode', true), '') <> 'on' then
    if new.status is distinct from old.status
       or new.revenue_model is distinct from old.revenue_model
       or new.revenue_value is distinct from old.revenue_value then
      raise exception 'merchant status and revenue require an admin RPC'
        using errcode = '42501';
    end if;

    if new.wallet_balance is distinct from old.wallet_balance
       or new.wallet_held is distinct from old.wallet_held
       or new.commission_owed is distinct from old.commission_owed
       or new.commission_custom is distinct from old.commission_custom
       or new.plan_id is distinct from old.plan_id
       or new.plan_expires_at is distinct from old.plan_expires_at then
      raise exception 'a shop''s money and plan move only through an audited admin function'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$fn$;

revoke all on function public.require_merchant_decision_rpc()
  from public, anon, authenticated;

-- `update of` fires on the columns a statement names, so a PATCH naming only
-- `commission_owed` would never have reached the function at all. The list has to grow
-- with it.
drop trigger if exists merchants_require_decision_rpc on public.merchants;
create trigger merchants_require_decision_rpc
  before update of status, revenue_model, revenue_value,
                   wallet_balance, wallet_held, commission_owed, commission_custom,
                   plan_id, plan_expires_at
  on public.merchants
  for each row execute function public.require_merchant_decision_rpc();

-- ------------------------------------------------------------------ an order

-- Copied from `20260905000000_disabled_staff_lose_access.sql`, the latest definition, with
-- one change: the early exit is a platform admin's, and a moderator gets exactly the one
-- transition AdminApp asks of them.
--
-- That transition is «إلغي الأوردر» on «اليوم»: an order nobody answered, cancelled so
-- the customer is not left waiting. It starts from `placed` or from `needsAttention` —
-- the escalator moves an unanswered order to the second, and that queue is what the sheet
-- is drawn from. Nothing else: not into `delivered`, which fires settlement, not out of
-- `delivered`, which reverses one, and not a cancellation once a kitchen has started
-- cooking, which costs somebody food.
create or replace function public.enforce_order_transition()
returns trigger
language plpgsql
as $fn$
declare
  actor text;
begin
  if new.status = old.status then
    return new;
  end if;

  if coalesce(current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  if public.is_platform_admin() then
    return new;
  end if;

  -- A moderator, since `is_admin()` answers for both roles and the line above has taken
  -- the admin out.
  if public.is_admin() then
    if old.status in ('placed', 'needsAttention') and new.status = 'cancelled' then
      return new;
    end if;
    raise exception 'a moderator may cancel an order nobody answered, and move nothing else'
      using errcode = '42501';
  end if;

  if old.status in ('delivered', 'cancelled') then
    raise exception 'order % is finished (%), and cannot be moved', old.id, old.status
      using errcode = 'check_violation';
  end if;

  actor := case
    when auth.uid() = old.customer_uid then 'customer'
    when public.is_merchant_owner(old.merchant_id) then 'merchant'
    when public.is_courier_for_order(
      old.courier_uid, old.merchant_id, old.delivery_by
    ) then 'courier'
    else 'nobody'
  end;

  if not (
    (actor = 'customer' and old.status = 'placed' and new.status = 'cancelled')
    or (actor = 'merchant' and (
         (old.status = 'placed' and new.status in ('accepted', 'cancelled'))
      or (old.status = 'accepted' and new.status in ('preparing', 'cancelled'))
      or (old.status = 'preparing' and new.status = 'outForDelivery')))
    or (actor = 'courier' and (
         (old.status = 'preparing' and new.status = 'outForDelivery')
      or (old.status = 'outForDelivery' and new.status in ('delivered', 'cancelled'))))
  ) then
    raise exception '% may not move an order from % to %', actor, old.status, new.status
      using errcode = 'check_violation';
  end if;

  return new;
end;
$fn$;

-- The same copy, the same one change. A moderator's columns are the cancellation's and
-- nothing else: `pricing`, `revenue`, `items` and `courier_uid` are what settlement reads,
-- and `status_history` is here only because `append_order_status_history` fires first and
-- has already written the entry this cancellation earns.
create or replace function public.guard_order_columns()
returns trigger
language plpgsql
as $fn$
declare
  allowed text[];
  touched text[];
begin
  if coalesce(current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  if public.is_platform_admin() then
    return new;
  end if;

  allowed := case
    when public.is_admin()
      then array['status', 'status_history', 'cancel_reason', 'cancelled_by']
    when auth.uid() = old.customer_uid
      then array['status', 'status_history', 'cancel_reason', 'cancelled_by']
    when public.is_merchant_owner(old.merchant_id)
      then array['status', 'status_history', 'prep_minutes', 'cancel_reason', 'cancelled_by']
    when public.is_courier_for_order(
      old.courier_uid, old.merchant_id, old.delivery_by
    )
      then array['status', 'status_history', 'courier_uid', 'delivered_at',
                 'cancel_reason', 'cancelled_by']
    else array[]::text[]
  end || array['updated_at'];

  select coalesce(array_agg(k), '{}')
    into touched
    from jsonb_each(to_jsonb(new)) as changes(k, v)
   where v is distinct from (to_jsonb(old) -> changes.k);

  if not (touched <@ allowed) then
    raise exception 'column not yours to change on an order: %',
      array_to_string(array(select unnest(touched) except select unnest(allowed)), ', ')
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$fn$;

-- ------------------------------------------------------------------ an order from nothing

-- `admin_orders` is `for all`, so it grants INSERT with everything else, and both order
-- guards above are UPDATE triggers. A moderator could POST an order carrying whatever
-- `pricing` and `revenue` they liked: a prepaid order whose frozen terms say a fortune
-- drives `hold_prepaid_credit` to hold it against the shop's wallet, which stops the shop
-- taking orders; one inserted as `delivered` never passes through the UPDATE that
-- settles, so the order and the money records disagree for good.
--
-- A trigger of its own rather than a change to the two above: `enforce_order_transition`
-- has been copied verbatim by another migration since, and a rule about *creating* an order
-- is not a rule about moving one. Server mode passes, because `place_order` declares it —
-- that is the one way an order is made. A platform admin is left as they were: the policy
-- has always let them, and nothing in AdminApp does it.
--
-- A customer never could: the only insert policy on `orders` is `admin_orders`.
create or replace function public.refuse_moderator_order_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if coalesce(pg_catalog.current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  if public.is_admin() and not public.is_platform_admin() then
    raise exception 'a moderator does not write orders; an order is made by place_order'
      using errcode = '42501';
  end if;

  return new;
end;
$fn$;

revoke all on function public.refuse_moderator_order_insert()
  from public, anon, authenticated;

drop trigger if exists orders_refuse_moderator_insert on public.orders;
create trigger orders_refuse_moderator_insert
  before insert on public.orders
  for each row execute function public.refuse_moderator_order_insert();

-- ------------------------------------------------------------------ a shop from nothing

-- AdminApp adds a shop with a plain insert (`MerchantRepository.createMerchant`), so the
-- verb stays. What a moderator may *put* in the money columns of a new shop is what every
-- new shop starts with, and nothing else: an empty wallet, no debt, no plan, and the one
-- commission rate.
--
-- The rate is not checked against what was sent. `merchants_start_on_the_rate` turns the
-- `subscription` the form sends into `commission` at the city's rate — but it keeps a
-- commission that arrives already written, so relying on it alone would let a moderator
-- create a shop at one basis point. This trigger is named to fire after that one (BEFORE
-- triggers run in name order, and `start_on_the_rate` < `start_with_nothing`), so it
-- judges the row as it will be stored: at the rate, or refused.
create or replace function public.merchants_start_with_nothing()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if coalesce(pg_catalog.current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  if public.is_admin() and not public.is_platform_admin()
     and (new.wallet_balance <> 0
          or new.wallet_held <> 0
          or new.commission_owed <> 0
          or new.commission_custom
          or new.plan_id is not null
          or new.plan_expires_at is not null
          or new.revenue_model <> 'commission'
          or new.revenue_value <> public.default_commission_bps()) then
    raise exception 'a new shop starts with no money and the one rate; billing is an admin''s'
      using errcode = '42501';
  end if;

  return new;
end;
$fn$;

revoke all on function public.merchants_start_with_nothing()
  from public, anon, authenticated;

drop trigger if exists merchants_start_with_nothing on public.merchants;
create trigger merchants_start_with_nothing
  before insert on public.merchants
  for each row execute function public.merchants_start_with_nothing();

-- ------------------------------------------------------------------ a subscription term

-- `admin_subscriptions` is `for all`. A moderator could insert a term with any expiry, or
-- push an existing one years ahead — and `record_subscription_payment` extends from the
-- latest term, so the next genuine payment carries the fabricated date onto
-- `merchants.plan_expires_at`, where it is the shop's plan.
--
-- Taken from everybody, platform admin included, not narrowed to a moderator: no client
-- writes this table (AdminApp calls `record_subscription_payment`), and a term is a
-- receipt, which H-09 says is written by the function that writes its evidence with it.
-- Every writer that remains is `security definer` and runs as the table's owner —
-- `record_subscription_payment`, `remind_expiring_subscriptions`, the nightly
-- `downgrade_expired_subscriptions` — as are the foreign key's `set null` and the name
-- stamp. SELECT stays: both the admin's billing screen and a shop read their own term.
revoke insert, update, delete on public.subscriptions from authenticated;

-- ------------------------------------------------------------------ the «اليوم» cancel

-- The sheet cancelled through `OrderRepository.cancel` — the customer's path, which only
-- matches `status = 'placed'` and signs the cancellation `customer`. The queue it is drawn
-- from holds `needsAttention` orders, so every tap matched nothing and said
-- «مقدرناش نلغيه». It is its own function now, audited like every other staff mutation,
-- and it leaves the customer's rights exactly as they were.
--
-- `is_admin()`, not the narrow question: cancelling an order nobody answered is the
-- operational work a moderator exists for. From `placed` or `needsAttention` only — once a
-- kitchen has started, cancelling costs somebody food.
--
-- Signed `admin` for both roles. It is the actor value the column has carried since the
-- first schema, and it says what the customer and the shop need to know — the platform
-- cancelled it, not the kitchen and not them. Which person did is the audit row's job.
create or replace function public.admin_cancel_order(
  p_order_id uuid,
  p_reason   text
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor  uuid := auth.uid();
  v_prior  text;
  v_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
  v_old    public.orders;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only staff cancel an order from the queue' using errcode = '42501';
  end if;
  if v_reason = '' then
    raise exception 'a cancellation needs a reason' using errcode = 'check_violation';
  end if;

  select * into v_old from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'no such order' using errcode = 'P0002';
  end if;

  -- 23505 is what this schema answers "somebody got there first" with, and what
  -- `Failure.from` reads as a conflict: the order moved while the sheet was open.
  if v_old.status not in ('placed', 'needsAttention') then
    raise exception 'order % has already moved (%)', p_order_id, v_old.status
      using errcode = '23505';
  end if;

  -- Server mode because the column guard and the transition guard judge the caller, and
  -- this function has already judged it more narrowly than either. Put back afterwards:
  -- it is transaction-local, inside the caller's transaction.
  v_prior := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);
  update public.orders
     set status = 'cancelled',
         cancel_reason = v_reason,
         cancelled_by = 'admin'
   where id = p_order_id;
  perform pg_catalog.set_config('app.server_mode', v_prior, true);

  insert into public.audit_log (action, actor, merchant_id, detail)
  values (
    'order.cancelled_by_staff', v_actor, v_old.merchant_id,
    pg_catalog.jsonb_build_object(
      'orderId', p_order_id,
      'orderNumber', v_old.order_number,
      'from', v_old.status,
      'reason', v_reason
    )
  );
end;
$fn$;

revoke all on function public.admin_cancel_order(uuid, text) from public, anon;
grant execute on function public.admin_cancel_order(uuid, text)
  to authenticated, service_role;
