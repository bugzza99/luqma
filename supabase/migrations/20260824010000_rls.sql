-- Luqma — the boundary.
--
-- The port of `firebase/firestore.rules`, including everything the pre-launch audit
-- fixed. Read `supabase/test/rls.test.js` beside it: every policy below exists because a
-- test says what happens without it.
--
-- Three layers, because a policy alone cannot express what the Firestore rules did:
--
-- **Rows** are policies. `using` decides which rows a statement may see, `with check`
-- what they may become. Together they say things like "only your own menu items, and
-- they have to stay yours" — which is the cross-merchant hole the audit found, closed by
-- construction rather than by a second condition somebody has to remember.
--
-- **Columns** are triggers, not grants. Column privileges were the obvious tool and are
-- the wrong one: `authenticated` is a single Postgres role for every signed-in person,
-- so a grant wide enough for an admin is wide enough for a merchant, and the narrow
-- grant is simply superseded. A trigger reads the token *and* diffs old against new,
-- which is exactly what `onlyChanges([...])` did.
--
-- **Transitions** are triggers too. A policy sees the existing row in `using` and the new
-- row in `with check`, but never both in one expression — so the order state machine
-- cannot be a policy at all.
--
-- One consequence worth knowing: the column guards diff, so writing the value a column
-- already holds is not a change and is not refused. Nothing moved, so nothing was denied.

-- ---------------------------------------------------------------- identity

-- Copies the staff record into the token at sign-in.
--
-- This is what replaces Firebase custom claims, and the property that matters is the
-- same one: **only a server can issue it.** A role in a table a client can write is a
-- role a client can grant itself.
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
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

-- Reading a claim that is not there must be `false`, never an error. This is the same
-- lesson as `token.get('x', default)` in the Firestore rules, where a bare `token.admin`
-- threw on every customer's token and failed the branch it sat in for a reason that had
-- nothing to do with access.
create or replace function public.claim(name text)
returns text
language sql
stable
as $$
  select nullif(auth.jwt() -> 'app_metadata' ->> name, '');
$$;

create or replace function public.is_admin() returns boolean
language sql stable as $$
  select coalesce(public.claim('admin')::boolean, false);
$$;

create or replace function public.staff_role() returns text
language sql stable as $$
  select coalesce(public.claim('role'), '');
$$;

create or replace function public.staff_scope() returns text
language sql stable as $$
  select coalesce(public.claim('scope'), '');
$$;

-- "Belongs to" is not "runs". An owner and their courier carry the SAME merchant, so
-- this alone cannot tell them apart — and every rule written on it alone would let a
-- courier accept orders, rewrite the menu and close the shop.
create or replace function public.belongs_to_merchant(m uuid) returns boolean
language sql stable as $$
  select m is not null and public.claim('merchant_id')::uuid = m;
$$;

create or replace function public.is_merchant_owner(m uuid) returns boolean
language sql stable as $$
  select public.belongs_to_merchant(m) and public.staff_role() = 'owner';
$$;

create or replace function public.is_courier_for(m uuid) returns boolean
language sql stable as $$
  select public.belongs_to_merchant(m) and public.staff_role() = 'courier';
$$;

-- Luqma's own courier: home kitchens, and merchants that do not deliver. Belongs to no
-- merchant, so it is scope rather than merchant that identifies them.
create or replace function public.is_platform_courier() returns boolean
language sql stable as $$
  select public.staff_role() = 'courier' and public.staff_scope() = 'platform';
$$;

-- ---------------------------------------------------------------- the order state machine

-- Mirrored from `OrderTransitions` in luqma_core, and from the rules the audit added.
-- `delivered` is the transition `on_order_delivered` will fire on, and that spends a
-- prepaid wallet or accrues a commission — so whoever can write the word can move money.
create or replace function public.enforce_order_transition()
returns trigger
language plpgsql
as $$
declare
  actor text;
begin
  if new.status = old.status then
    return new;
  end if;

  -- A trusted server function declares itself, exactly as the column guards do: the
  -- deadline escalator moves orders nobody is holding a token for, and no HTTP client
  -- can set the flag it reads.
  if coalesce(current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  if public.is_admin() then
    return new;
  end if;

  -- Delivered and cancelled are final for everyone else. An order that can be reopened
  -- is an order whose cash total can change after the money was handed over.
  if old.status in ('delivered', 'cancelled') then
    raise exception 'order % is finished (%), and cannot be moved', old.id, old.status
      using errcode = 'check_violation';
  end if;

  actor := case
    when auth.uid() = old.customer_uid then 'customer'
    when public.is_merchant_owner(old.merchant_id) then 'merchant'
    when auth.uid() = old.courier_uid
      or public.is_courier_for(old.merchant_id)
      or (public.is_platform_courier() and old.delivery_by = 'platform') then 'courier'
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
$$;

create trigger orders_enforce_transition
  before update of status on orders
  for each row execute function public.enforce_order_transition();

-- A courier may only ever write their own name, and only onto an order nobody else is
-- already carrying — otherwise one could hand another's phone a delivery, or take an
-- order off somebody halfway to the door.
create or replace function public.enforce_courier_claim()
returns trigger
language plpgsql
as $$
begin
  if new.courier_uid is distinct from old.courier_uid and not public.is_admin() then
    if new.courier_uid is distinct from auth.uid() then
      raise exception 'a courier may only put their own name on an order'
        using errcode = 'check_violation';
    end if;
    if old.courier_uid is not null and old.courier_uid <> auth.uid() then
      raise exception 'that order is already being carried by somebody else'
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

create trigger orders_enforce_courier_claim
  before update of courier_uid on orders
  for each row execute function public.enforce_courier_claim();

-- ---------------------------------------------------------------- which columns

-- The port of `onlyChanges([...])`.
--
-- Column privileges were the obvious tool and are the wrong one: `authenticated` is a
-- single Postgres role for every signed-in person, so a grant wide enough for an admin is
-- wide enough for a merchant. What tells them apart is the token, and only a trigger can
-- read the token *and* see which columns actually moved.
create or replace function public.guard_columns()
returns trigger
language plpgsql
as $$
declare
  allowed text[] := tg_argv[0]::text[] || array['updated_at'];
  touched text[];
begin
  if public.is_admin() then
    return new;
  end if;

  select coalesce(array_agg(k), '{}')
    into touched
    from jsonb_each(to_jsonb(new)) as changes(k, v)
   where v is distinct from (to_jsonb(old) -> changes.k);

  if not (touched <@ allowed) then
    raise exception 'column not yours to change on %: %',
      tg_table_name, array_to_string(array(select unnest(touched) except select unnest(allowed)), ', ')
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

-- A customer owns their name, phone and addresses. They do not own the columns that
-- describe how the platform sees them: unblocking yourself or resetting your own refusal
-- count would make the whole abuse defence decorative.
create trigger users_guard_columns before update on users for each row
  execute function public.guard_columns('{name,phone,fcm_tokens,default_address_id}');

-- Absent deliberately: status, plan_id, revenue_model, revenue_value, wallet_balance,
-- commission_owed, owner_uid, rating_avg. A merchant that can set its own revenue model
-- sets its own price.
create trigger merchants_guard_columns before update on merchants for each row
  execute function public.guard_columns(
    '{name,phone,logo_media_id,cover_media_id,opening_hours,paused_until,min_order,delivery_fee_override}');

-- Neither quantity moves from a client: `remaining_qty` belongs to the order function and
-- is decremented in the same transaction as the order, and letting a kitchen raise
-- `total_qty` alone would only skew the meter, since they cannot raise what is left.
create trigger daily_meals_guard_columns before update on daily_meals for each row
  execute function public.guard_columns(
    '{name,description,media_id,price,date,pickup_window_start,pickup_window_end,delivery_option,status}');

-- An order is money. Which columns may move depends on who is moving them, so this one
-- knows about the parties rather than taking a single list.
create or replace function public.guard_order_columns()
returns trigger
language plpgsql
as $$
declare
  allowed text[];
  touched text[];
begin
  -- Same declaration the other guards honour: the deadline escalator writes status and
  -- status_history on orders nobody holds a token for.
  if coalesce(current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  if public.is_admin() then
    return new;
  end if;

  allowed := case
    when auth.uid() = old.customer_uid
      then array['status', 'status_history', 'cancel_reason', 'cancelled_by']
    when public.is_merchant_owner(old.merchant_id)
      -- `courier_uid` is absent: only a courier writes it, and only their own name. A
      -- merchant able to write it could hand any account read and write over an order,
      -- and the cash on it.
      then array['status', 'status_history', 'prep_minutes', 'cancel_reason', 'cancelled_by']
    when auth.uid() = old.courier_uid
      or public.is_courier_for(old.merchant_id)
      or (public.is_platform_courier() and old.delivery_by = 'platform')
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
$$;

create trigger orders_guard_columns before update on orders for each row
  execute function public.guard_order_columns();

-- ---------------------------------------------------------------- lock it all down

-- Nothing is readable or writable until a policy below says so. New tables start denied
-- and are opened deliberately, rather than shipping open because nobody remembered them.
do $$
declare t text;
begin
  foreach t in array array[
    'cities', 'zones', 'landmarks', 'users', 'addresses', 'merchants', 'menu_categories',
    'merchant_served_zones', 'menu_items', 'daily_meals', 'media', 'orders',
    'order_issues', 'ratings', 'plans', 'subscriptions', 'promotions', 'coupons',
    'coupon_redemptions', 'staff', 'config', 'home_sections', 'audit_log'
  ]
  loop
    execute format('alter table %I enable row level security', t);
    execute format('alter table %I force row level security', t);
    execute format('revoke all on %I from anon, authenticated', t);

    -- The server, explicitly. `service_role` already bypasses RLS, but bypassing a
    -- policy is not the same as holding a privilege: without this it is refused at the
    -- grant, and the order function, the nightly pass and every Edge Function with it.
    -- Granted here rather than left to default privileges, which are a setting somewhere
    -- else that this file cannot see.
    execute format('grant all on %I to service_role', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------- geography

-- The addressing primitives. Public because a customer picks a zone before they have an
-- account, and there is nothing in them worth hiding.
grant select on cities, zones, landmarks to anon, authenticated;
create policy read_cities on cities for select to anon, authenticated using (true);
create policy read_zones on zones for select to anon, authenticated using (true);
create policy read_landmarks on landmarks for select to anon, authenticated using (true);

grant insert, update, delete on cities, zones, landmarks to authenticated;
create policy admin_cities on cities for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_zones on zones for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_landmarks on landmarks for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- users

-- Which columns a customer may move is `users_guard_columns` above; these grants decide
-- only which *statements* they may run.
grant select, insert, update on users to authenticated;

create policy read_own_user on users for select to authenticated
  using (id = auth.uid() or public.is_admin());
create policy create_own_user on users for insert to authenticated
  with check (id = auth.uid());
create policy update_own_user on users for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy admin_users on users for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

grant select, insert, update, delete on addresses to authenticated;
create policy own_addresses on addresses for all to authenticated
  using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());

-- ---------------------------------------------------------------- merchants

grant select on merchants to anon, authenticated;
create policy read_approved_merchants on merchants for select to anon, authenticated
  using (status = 'approved'
         or public.belongs_to_merchant(id)
         or public.is_admin());

-- Which columns a merchant may move is `merchants_guard_columns` above.
grant insert, update, delete on merchants to authenticated;
create policy merchant_edits_own on merchants for update to authenticated
  using (public.is_merchant_owner(id))
  with check (public.is_merchant_owner(id));

create policy admin_merchants on merchants for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

grant select on menu_categories, merchant_served_zones to anon, authenticated;
create policy read_menu_categories on menu_categories for select to anon, authenticated
  using (true);
create policy read_served_zones on merchant_served_zones for select to anon, authenticated
  using (true);

grant insert, update, delete on menu_categories to authenticated;
create policy merchant_menu_categories on menu_categories for all to authenticated
  using (public.is_merchant_owner(merchant_id))
  with check (public.is_merchant_owner(merchant_id));
create policy admin_menu_categories on menu_categories for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

grant insert, update, delete on merchant_served_zones to authenticated;
create policy admin_served_zones on merchant_served_zones for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- menu

grant select on menu_items to anon, authenticated;
create policy read_menu_items on menu_items for select to anon, authenticated using (true);

grant insert, update, delete on menu_items to authenticated;

-- `using` decides which rows you may touch and `with check` decides what they may become.
-- Together they say: only your own items, and they have to stay yours. The Firestore rule
-- read only the *incoming* merchant, so rewriting it to your own moved another shop's
-- dish into your menu.
create policy merchant_menu_items on menu_items for all to authenticated
  using (public.is_merchant_owner(merchant_id))
  with check (public.is_merchant_owner(merchant_id));
create policy admin_menu_items on menu_items for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- daily meals

grant select on daily_meals to anon, authenticated;
-- Drafts and not-yet-published days are kitchen secrets until they go live: a customer
-- seeing tomorrow's menu early is a leak, not a convenience. The kitchen and the admin
-- see their own rows regardless of state.
create policy read_daily_meals on daily_meals for select to anon, authenticated
  using (status = 'published'
         or public.is_merchant_owner(merchant_id)
         or public.is_admin());

grant insert, update, delete on daily_meals to authenticated;

create policy kitchen_daily_meals on daily_meals for all to authenticated
  using (public.is_merchant_owner(merchant_id))
  with check (public.is_merchant_owner(merchant_id));

create policy admin_daily_meals on daily_meals for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- media

grant select, insert on media to authenticated;
create policy read_media on media for select to anon, authenticated
  using (status = 'approved' or uploaded_by = auth.uid() or public.is_admin());
grant select on media to anon;

-- `uploaded_by` is checked, not trusted: it is what the read policy above lets somebody
-- see, so filing an upload under another name hands it to that person. And only an admin
-- moves an image out of pending — an uploader approving their own upload is the gate with
-- a hole in it.
create policy upload_media on media for insert to authenticated
  with check (uploaded_by = auth.uid() and status = 'pending');

grant update, delete on media to authenticated;
create policy admin_media on media for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- orders

grant select on orders to authenticated;
create policy read_orders on orders for select to authenticated
  using (public.is_admin()
         or customer_uid = auth.uid()
         or public.belongs_to_merchant(merchant_id)
         or courier_uid = auth.uid()
         -- Without this the platform courier cannot find the work at all: they are not
         -- named on an order until they take it, and they cannot take what they cannot see.
         or (public.is_platform_courier() and delivery_by = 'platform'));

-- No client insert, ever. Orders are created by a database function that recomputes the
-- total and the coupon; a client-written order is a client-chosen price. And no delete:
-- an order is the record of money that changed hands.
create policy admin_orders on orders for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
grant insert, update, delete on orders to authenticated;

-- Two triggers do the work here: `orders_enforce_transition` decides which *move* each
-- party may make, and `orders_guard_columns` decides which *columns* they may touch. The
-- policies below decide only which rows are theirs at all.
create policy customer_cancels on orders for update to authenticated
  using (customer_uid = auth.uid()) with check (customer_uid = auth.uid());

create policy merchant_moves_orders on orders for update to authenticated
  using (public.is_merchant_owner(merchant_id))
  with check (public.is_merchant_owner(merchant_id));

create policy courier_moves_orders on orders for update to authenticated
  using (courier_uid = auth.uid()
         or (courier_uid is null and (public.is_courier_for(merchant_id)
             or (public.is_platform_courier() and delivery_by = 'platform'))))
  with check (courier_uid = auth.uid()
              or public.is_courier_for(merchant_id)
              or (public.is_platform_courier() and delivery_by = 'platform'));

-- ---------------------------------------------------------------- issues and ratings

grant select, insert on order_issues to authenticated;
create policy read_order_issues on order_issues for select to authenticated
  using (public.is_admin()
         or customer_uid = auth.uid()
         or public.belongs_to_merchant(merchant_id));

-- About an order they actually had, from the merchant they are naming. A ticket against
-- a stranger's dinner is a complaint the merchant has no way to answer.
create policy raise_own_issue on order_issues for insert to authenticated
  with check (customer_uid = auth.uid()
              and exists (select 1 from orders o
                           where o.id = order_id
                             and o.customer_uid = auth.uid()
                             and o.merchant_id = order_issues.merchant_id));

grant update, delete on order_issues to authenticated;
create policy admin_order_issues on order_issues for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

grant select, insert, update on ratings to authenticated;
-- Stars aggregate onto the merchant; the words stay between the customer, the merchant
-- and the admin until the public-comments flag is turned on.
create policy read_ratings on ratings for select to authenticated
  using (public.is_admin()
         or customer_uid = auth.uid()
         or public.belongs_to_merchant(merchant_id));

-- An order they actually received, from that merchant. Without it a merchant's average
-- is anybody's to move, from anywhere, for nothing. The primary key does the rest: one
-- rating per order, so rating again corrects the first instead of voting twice.
create policy rate_own_delivered_order on ratings for insert to authenticated
  with check (customer_uid = auth.uid()
              and exists (select 1 from orders o
                           where o.id = order_id
                             and o.customer_uid = auth.uid()
                             and o.merchant_id = ratings.merchant_id
                             and o.status = 'delivered'));
create policy correct_own_rating on ratings for update to authenticated
  using (customer_uid = auth.uid()) with check (customer_uid = auth.uid());

grant delete on ratings to authenticated;
create policy admin_ratings on ratings for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- money

grant select on plans to anon, authenticated;
create policy read_plans on plans for select to anon, authenticated using (true);
grant insert, update, delete on plans to authenticated;
create policy admin_plans on plans for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

grant select on subscriptions to authenticated;
create policy read_own_subscription on subscriptions for select to authenticated
  using (public.is_admin() or public.belongs_to_merchant(merchant_id));
grant insert, update, delete on subscriptions to authenticated;
create policy admin_subscriptions on subscriptions for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

grant select, insert on promotions to authenticated;
grant select on promotions to anon;
-- Both live states, because that is what the app queries for. A policy that allows less
-- than the query asks for returns nothing rather than returning less — which is how the
-- entire promotions feature shipped invisible to every customer in the city.
create policy read_live_promotions on promotions for select to anon, authenticated
  using (status in ('approved', 'active')
         or public.is_admin()
         or public.belongs_to_merchant(merchant_id));

-- A merchant may ask; only an admin may approve. That single asymmetry is what keeps
-- unmoderated push off every customer's phone.
create policy merchant_requests_promotion on promotions for insert to authenticated
  with check (public.is_merchant_owner(merchant_id) and status = 'requested');

grant update, delete on promotions to authenticated;
create policy admin_promotions on promotions for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Deliberately unreadable by any client. A readable coupons table is one anybody can
-- enumerate — every merchant-specific code and every campaign that has not launched yet.
-- The app calls a function that returns the discount for one basket and nothing else.
grant select, insert, update, delete on coupons to authenticated;
create policy admin_coupons on coupons for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Written by the order function, so a per-user limit cannot be sidestepped by simply not
-- recording the use.
grant select on coupon_redemptions to authenticated;
create policy admin_coupon_redemptions on coupon_redemptions for select to authenticated
  using (public.is_admin());

-- ---------------------------------------------------------------- staff

grant select on staff to authenticated;
create policy read_staff on staff for select to authenticated
  using (public.is_admin()
         or uid = auth.uid()
         or public.belongs_to_merchant(merchant_id));
grant insert, update, delete on staff to authenticated;
create policy admin_staff on staff for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- control plane

grant select on config, home_sections to anon, authenticated;
create policy read_config on config for select to anon, authenticated using (true);
create policy read_home_sections on home_sections for select to anon, authenticated
  using (true);

grant insert, update, delete on config, home_sections to authenticated;
create policy admin_config on config for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy admin_home_sections on home_sections for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------- audit

-- Append-only, including for an admin. A log its own subject can edit proves nothing.
grant select, insert on audit_log to authenticated;
create policy read_audit_log on audit_log for select to authenticated
  using (public.is_admin());
create policy append_audit_log on audit_log for insert to authenticated
  with check (public.is_admin());
