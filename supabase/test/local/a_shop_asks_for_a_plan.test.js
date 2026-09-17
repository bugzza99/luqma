import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

describe('a shop asks for a plan', () => {
  const ADMIN_1 = '00000000-0000-0000-0000-0000000000a1';
  const ADMIN_2 = '00000000-0000-0000-0000-0000000000a2';
  const OWNER_A = '00000000-0000-0000-0000-0000000000b1';
  const OWNER_B = '00000000-0000-0000-0000-0000000000b2';
  const COURIER_A = '00000000-0000-0000-0000-0000000000d1';
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';

  let db;
  let shopA;
  let shopB;
  let shopPrepaid;
  let zoneA;
  let itemA;
  let itemPrepaid;
  let addressCustomer;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select ${uid ? `'${uid}'::uuid` : 'null::uuid'} $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;
  `);

  const role = async (r, fn) => {
    await db.exec(`set role ${r}`);
    try {
      return await fn();
    } finally {
      await db.exec('reset role');
    }
  };

  const setMerchantPlan = async (merchantId, planId, expiresAt) => {
    await db.query("select set_config('app.server_mode', 'on', false)");
    await db.query('update merchants set plan_id = $1, plan_expires_at = $2 where id = $3', [planId, expiresAt, merchantId]);
    await db.query("select set_config('app.server_mode', 'off', false)");
  };

  before(async () => {
    db = await freshDatabase();

    await db.exec(`
      insert into auth.users (id) values
        ('${ADMIN_1}'), ('${ADMIN_2}'), ('${OWNER_A}'), ('${OWNER_B}'), ('${COURIER_A}'), ('${CUSTOMER}');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('edku', 'إدكو')
        on conflict (id) do nothing;
      update users set name = 'عميل تجربة', phone = '01000000001' where id = '${CUSTOMER}';
    `);

    zoneA = (await db.query(`
      insert into zones (city_id, name, default_delivery_fee)
      values ('edku', 'المنطقة المركزية', 1000) returning id;
    `)).rows[0].id;

    // Plans
    await db.exec(`
      insert into plans (id, name, price_monthly, features, sort_order, is_active) values
        ('basic', 'باقة المبتدئ', 30000, '{}'::jsonb, 1, true),
        ('pro', 'باقة المحترفين', 60000, '{}'::jsonb, 2, true),
        ('inactive_plan', 'باقة متوقفة', 20000, '{}'::jsonb, 3, false);
    `);

    const createShop = async (name, ownerUid, model = 'commission', value = 1000, balance = 0) => (await db.query(`
      insert into merchants (
        city_id, type, name, zone_id, phone, status, owner_uid,
        delivers_self, min_order, revenue_model, revenue_value, wallet_balance, opening_hours
      ) values (
        'edku', 'restaurant', $1, $2, '01011111111', 'approved', $3,
        true, 0, $4, $5, $6,
        (select jsonb_agg(jsonb_build_object('weekday', d, 'openMinute', 0, 'closeMinute', 1439))
           from generate_series(1, 7) d)
      ) returning id;
    `, [name, zoneA, ownerUid, model, value, balance])).rows[0].id;

    shopA = await createShop('مطعم البركة', OWNER_A, 'commission', 1000); // 10% commission
    shopB = await createShop('مطعم الأصيل', OWNER_B, 'commission', 1500);
    shopPrepaid = await createShop('كشك السعادة', OWNER_A, 'prepaid', 500, 0); // 5 EGP per order, 0 balance

    await db.query(`
      insert into merchant_served_zones (merchant_id, zone_id) values ($1, $3), ($2, $3);
    `, [shopA, shopPrepaid, zoneA]);

    await db.exec(`
      insert into staff (uid, scope, role, is_active) values
        ('${ADMIN_1}', 'platform', 'admin', true),
        ('${ADMIN_2}', 'platform', 'admin', true);
      insert into staff (uid, scope, role, merchant_id, is_active) values
        ('${OWNER_A}', 'merchant', 'owner', '${shopA}', true),
        ('${OWNER_B}', 'merchant', 'owner', '${shopB}', true),
        ('${COURIER_A}', 'merchant', 'courier', '${shopA}', true);
    `);

    // Menu items
    const catA = (await db.query(`
      insert into menu_categories (merchant_id, name) values ($1, 'سندوتشات') returning id;
    `, [shopA])).rows[0].id;

    itemA = (await db.query(`
      insert into menu_items (merchant_id, category_id, name, price, options)
      values ($1, $2, 'شاورما لحم', 10000, '[]'::jsonb) returning id;
    `, [shopA, catA])).rows[0].id;

    const catPrepaid = (await db.query(`
      insert into menu_categories (merchant_id, name) values ($1, 'مشروبات') returning id;
    `, [shopPrepaid])).rows[0].id;

    itemPrepaid = (await db.query(`
      insert into menu_items (merchant_id, category_id, name, price, options)
      values ($1, $2, 'عصير مانجو', 3000, '[]'::jsonb) returning id;
    `, [shopPrepaid, catPrepaid])).rows[0].id;

    addressCustomer = (await db.query(`
      insert into addresses (user_id, zone_id, label)
      values ('${CUSTOMER}', $1, 'المنزل') returning id;
    `, [zoneA])).rows[0].id;
  });

  after(async () => {
    await db?.close();
  });

  describe('A. Requests', () => {
    it('owner requests a plan -> row pending with server-computed quoted_amount and admin push queued', async () => {
      await as(OWNER_A, { merchant_id: shopA, role: 'owner' });

      // Clean out outbox before request
      await db.exec('delete from push_outbox');

      const res = await role('authenticated', () => db.query(`
        select * from public.request_subscription('pro', 3, 'transfer', '  TRF-998811  ')
      `));

      const req = res.rows[0];
      assert.ok(req.id);
      assert.equal(req.merchant_id, shopA);
      assert.equal(req.plan_id, 'pro');
      assert.equal(req.months, 3);
      assert.equal(req.quoted_amount, 180000); // 60000 * 3
      assert.equal(req.payment_method, 'transfer');
      assert.equal(req.transfer_reference, 'TRF-998811');
      assert.equal(req.status, 'pending');
      assert.equal(req.requested_by, OWNER_A);

      // Pushes queued to active platform admins
      const pushes = (await db.query('select * from push_outbox order by created_at')).rows;
      assert.ok(pushes.length >= 2);
      const pushUids = pushes.map((p) => p.uid);
      assert.ok(pushUids.includes(ADMIN_1));
      assert.ok(pushUids.includes(ADMIN_2));

      for (const p of pushes) {
        assert.equal(p.title, 'طلب اشتراك جديد');
        assert.equal(p.body, 'مطعم البركة طلب باقة باقة المحترفين لمدة 3 شهر');
        assert.equal(p.channel, 'orders_critical');
      }
    });

    it('reference is trimmed and null when empty', async () => {
      // Cancel previous request first so shopA can make another request
      await as(OWNER_A, { merchant_id: shopA, role: 'owner' });
      const pendingReq = (await db.query("select id from subscription_requests where merchant_id = $1 and status = 'pending'", [shopA])).rows[0];
      await role('authenticated', () => db.query('select public.cancel_subscription_request($1)', [pendingReq.id]));

      const res = await role('authenticated', () => db.query(`
        select * from public.request_subscription('basic', 1, 'cash', '   ')
      `));
      assert.equal(res.rows[0].transfer_reference, null);
      assert.equal(res.rows[0].quoted_amount, 30000);
    });

    it('a second pending request is refused (unique violation)', async () => {
      await as(OWNER_A, { merchant_id: shopA, role: 'owner' });
      await assert.rejects(
        () => role('authenticated', () => db.query(`
          select * from public.request_subscription('basic', 1, 'cash')
        `)),
        /unique_violation|duplicate key|subscription_requests/
      );
    });

    it('non-owner / courier is refused', async () => {
      // Customer
      await as(CUSTOMER);
      await assert.rejects(
        () => role('authenticated', () => db.query(`
          select * from public.request_subscription('basic', 1, 'cash')
        `)),
        /42501|only an active merchant owner/
      );

      // Courier
      await as(COURIER_A, { merchant_id: shopA, role: 'courier' });
      await assert.rejects(
        () => role('authenticated', () => db.query(`
          select * from public.request_subscription('basic', 1, 'cash')
        `)),
        /42501|only an active merchant owner/
      );
    });

    it('inactive plan is refused', async () => {
      await as(OWNER_B, { merchant_id: shopB, role: 'owner' });
      await assert.rejects(
        () => role('authenticated', () => db.query(`
          select * from public.request_subscription('inactive_plan', 1, 'cash')
        `)),
        /plan not found or inactive/
      );
    });

    it('bad months is refused', async () => {
      await as(OWNER_B, { merchant_id: shopB, role: 'owner' });
      await assert.rejects(
        () => role('authenticated', () => db.query(`
          select * from public.request_subscription('basic', 5, 'cash')
        `)),
        /check_violation|months/
      );
    });

    it('client cannot insert, update, or delete the table directly', async () => {
      await as(OWNER_B, { merchant_id: shopB, role: 'owner' });

      // Direct insert
      await assert.rejects(
        () => role('authenticated', () => db.query(`
          insert into subscription_requests (merchant_id, plan_id, months, quoted_amount, payment_method)
          values ('${shopB}', 'basic', 1, 30000, 'cash')
        `)),
        /violates row-level security|denied/
      );

      // Direct update
      const reqId = (await db.query("select id from subscription_requests where merchant_id = $1 and status = 'pending'", [shopA])).rows[0].id;
      await assert.rejects(
        () => role('authenticated', () => db.query(`
          update subscription_requests set status = 'activated' where id = '${reqId}'
        `)),
        /violates row-level security|denied/
      );

      // Direct delete
      await assert.rejects(
        () => role('authenticated', () => db.query(`
          delete from subscription_requests where id = '${reqId}'
        `)),
        /violates row-level security|denied/
      );
    });

    it('owner can select own shop requests, but cannot see other shops', async () => {
      await as(OWNER_A, { merchant_id: shopA, role: 'owner' });
      const rowsA = (await role('authenticated', () => db.query('select * from subscription_requests'))).rows;
      assert.ok(rowsA.length > 0);
      assert.ok(rowsA.every((r) => r.merchant_id === shopA));

      await as(OWNER_B, { merchant_id: shopB, role: 'owner' });
      const rowsB = (await role('authenticated', () => db.query('select * from subscription_requests'))).rows;
      assert.equal(rowsB.length, 0); // Shop B has no requests yet
    });

    it('owner cancels pending request -> status cancelled', async () => {
      await as(OWNER_A, { merchant_id: shopA, role: 'owner' });
      const reqId = (await db.query("select id from subscription_requests where merchant_id = $1 and status = 'pending'", [shopA])).rows[0].id;

      await role('authenticated', () => db.query('select public.cancel_subscription_request($1)', [reqId]));

      const req = (await db.query('select * from subscription_requests where id = $1', [reqId])).rows[0];
      assert.equal(req.status, 'cancelled');

      // Cancelling again fails
      await assert.rejects(
        () => role('authenticated', () => db.query('select public.cancel_subscription_request($1)', [reqId])),
        /only pending requests can be cancelled/
      );
    });

    it('admin activates with a discount -> subscription created, merchant plan set, request activated, owner push queued', async () => {
      // Owner A creates new request for 6 months pro (quoted: 360000)
      await as(OWNER_A, { merchant_id: shopA, role: 'owner' });
      const req = (await role('authenticated', () => db.query(`
        select * from public.request_subscription('pro', 6, 'transfer', 'TRF-DISCOUNT')
      `))).rows[0];

      // Admin activates with discount: 300000 instead of 360000
      await as(ADMIN_1, { admin: true });
      await db.exec('delete from push_outbox');

      await role('authenticated', () => db.query(`
        select public.activate_subscription_request($1, 300000)
      `, [req.id]));

      // Verify request state
      const updatedReq = (await db.query('select * from subscription_requests where id = $1', [req.id])).rows[0];
      assert.equal(updatedReq.status, 'activated');
      assert.ok(updatedReq.subscription_id);
      assert.equal(updatedReq.reviewed_by, ADMIN_1);
      assert.ok(updatedReq.reviewed_at);

      // Verify subscription row
      const sub = (await db.query('select * from subscriptions where id = $1', [updatedReq.subscription_id])).rows[0];
      assert.equal(sub.merchant_id, shopA);
      assert.equal(sub.plan_id, 'pro');
      assert.equal(sub.amount, 300000);
      assert.ok(sub.expires_at > sub.started_at);

      // Verify merchant
      const m = (await db.query('select plan_id, plan_expires_at from merchants where id = $1', [shopA])).rows[0];
      assert.equal(m.plan_id, 'pro');
      assert.deepEqual(m.plan_expires_at, sub.expires_at);

      // Verify owner push
      const pushes = (await db.query('select * from push_outbox where uid = $1', [OWNER_A])).rows;
      assert.equal(pushes.length, 1);
      assert.equal(pushes[0].title, 'اشتراكك اتفعّل');
      assert.match(pushes[0].body, /باقة باقة المحترفين شغالة لحد \d\d\/\d\d\/\d\d\d\d/);
      assert.equal(pushes[0].channel, 'orders_critical');

      // Activating twice is refused
      await assert.rejects(
        () => role('authenticated', () => db.query('select public.activate_subscription_request($1)', [req.id])),
        /only pending requests can be activated/
      );
    });

    it('reject needs a reason and queues a push', async () => {
      // Owner B requests
      await as(OWNER_B, { merchant_id: shopB, role: 'owner' });
      const req = (await role('authenticated', () => db.query(`
        select * from public.request_subscription('basic', 1, 'cash')
      `))).rows[0];

      await as(ADMIN_1, { admin: true });

      // Reject without reason fails
      await assert.rejects(
        () => role('authenticated', () => db.query('select public.reject_subscription_request($1, $2)', [req.id, '   '])),
        /rejection reason is required/
      );

      // Reject with reason
      await db.exec('delete from push_outbox');
      await role('authenticated', () => db.query('select public.reject_subscription_request($1, $2)', [req.id, 'لم يتم استلام المبلغ']));

      const updatedReq = (await db.query('select * from subscription_requests where id = $1', [req.id])).rows[0];
      assert.equal(updatedReq.status, 'rejected');
      assert.equal(updatedReq.reject_reason, 'لم يتم استلام المبلغ');
      assert.equal(updatedReq.reviewed_by, ADMIN_1);

      // Owner B received push
      const pushes = (await db.query('select * from push_outbox where uid = $1', [OWNER_B])).rows;
      assert.equal(pushes.length, 1);
      assert.equal(pushes[0].title, 'طلب الاشتراك اترفض');
      assert.equal(pushes[0].body, 'لم يتم استلام المبلغ');
      assert.equal(pushes[0].channel, 'orders_critical');
    });
  });

  describe('B. No commission while a plan is active', () => {
    it('order placed while plan is active has revenue model subscription and value 0', async () => {
      // shopA currently has active pro plan (plan_expires_at in future, revenue_model is commission)
      await as(CUSTOMER);

      const res = await db.query('select place_order($1::jsonb) as o', [JSON.stringify({
        merchantId: shopA,
        addressId: addressCustomer,
        type: 'instant',
        items: [{ itemId: itemA, name: 'شاورما لحم', unitPrice: 10000, quantity: 1, optionIds: [] }],
      })]);

      const order = res.rows[0].o;
      assert.equal(order.revenue.model, 'subscription');
      assert.equal(order.revenue.value, 0);
      assert.equal(order.revenue.amount, 0);
    });

    it('after plan_expires_at passes, the next order carries the merchant commission', async () => {
      // Expire shopA's plan
      const past = new Date(Date.now() - 60000);
      await setMerchantPlan(shopA, 'pro', past);

      await as(CUSTOMER);
      const res = await db.query('select place_order($1::jsonb) as o', [JSON.stringify({
        merchantId: shopA,
        addressId: addressCustomer,
        type: 'instant',
        items: [{ itemId: itemA, name: 'شاورما لحم', unitPrice: 10000, quantity: 1, optionIds: [] }],
      })]);

      const order = res.rows[0].o;
      assert.equal(order.revenue.model, 'commission');
      assert.equal(order.revenue.value, 1000); // shopA's original commission
    });

    it('a prepaid shop with no credit can take orders while subscribed', async () => {
      // shopPrepaid has wallet_balance = 0 and revenue_model = 'prepaid' (value = 500)
      // Without active plan, order is refused
      await as(CUSTOMER);
      await assert.rejects(
        () => db.query('select place_order($1::jsonb) as o', [JSON.stringify({
          merchantId: shopPrepaid,
          addressId: addressCustomer,
          type: 'instant',
          items: [{ itemId: itemPrepaid, name: 'عصير مانجو', unitPrice: 3000, quantity: 1, optionIds: [] }],
        })]),
        /merchant not accepting orders/
      );

      // Now subscribe shopPrepaid
      const future = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
      await setMerchantPlan(shopPrepaid, 'basic', future);

      // Now order succeeds with revenue model subscription!
      const res = await db.query('select place_order($1::jsonb) as o', [JSON.stringify({
        merchantId: shopPrepaid,
        addressId: addressCustomer,
        type: 'instant',
        items: [{ itemId: itemPrepaid, name: 'عصير مانجو', unitPrice: 3000, quantity: 1, optionIds: [] }],
      })]);

      const order = res.rows[0].o;
      assert.equal(order.revenue.model, 'subscription');
      assert.equal(order.revenue.value, 0);
    });

    it('catalog verification for place_order_priced', async () => {
      const { rows } = await db.query(`
        select p.prosecdef, p.proconfig, l.lanname,
               has_function_privilege('anon', p.oid, 'execute') as anon_exec,
               has_function_privilege('authenticated', p.oid, 'execute') as auth_exec
          from pg_proc p
          join pg_language l on l.oid = p.prolang
         where p.oid = 'public.place_order_priced(jsonb)'::regprocedure;
      `);

      assert.equal(rows.length, 1);
      const fn = rows[0];
      assert.equal(fn.prosecdef, true, 'security definer');
      assert.equal(fn.lanname, 'plpgsql', 'language plpgsql');
      assert.ok(fn.proconfig && fn.proconfig.some((c) => c === 'search_path=' || c.startsWith('search_path=')), 'search_path empty');
      assert.equal(fn.anon_exec, false, 'revoked from anon');
      assert.equal(fn.auth_exec, false, 'revoked from authenticated');
    });
  });

  describe('C. Expiry reminders', () => {
    it('remind_expiring_subscriptions queues pushes once and not twice', async () => {
      // Set up a merchant expiring in 2 days with a subscription
      const expMerchant = shopB;
      const startsAt = new Date();
      const expiresAt = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000); // 2 days from now

      const subId = (await db.query(`
        insert into subscriptions (merchant_id, plan_id, amount, started_at, expires_at, reminded_at)
        values ($1, 'basic', 30000, $2, $3, null) returning id
      `, [expMerchant, startsAt, expiresAt])).rows[0].id;

      await setMerchantPlan(expMerchant, 'basic', expiresAt);

      await db.exec('delete from push_outbox');

      // Call reminder
      const count1 = (await db.query('select public.remind_expiring_subscriptions() as c')).rows[0].c;
      assert.ok(count1 >= 1);

      // Verify pushes: owner got reminder, admins got reminder
      const ownerPushes = (await db.query('select * from push_outbox where uid = $1', [OWNER_B])).rows;
      assert.equal(ownerPushes.length, 1);
      assert.equal(ownerPushes[0].title, 'اشتراكك هيخلص قريب');
      assert.match(ownerPushes[0].body, /باقة باقة المبتدئ بتخلص يوم \d\d\/\d\d\/\d\d\d\d\. جدّد عشان متدفعش عمولة\./);
      assert.equal(ownerPushes[0].channel, 'orders_critical');

      const adminPushes = (await db.query('select * from push_outbox where uid in ($1, $2)', [ADMIN_1, ADMIN_2])).rows;
      assert.equal(adminPushes.length, 2);
      for (const ap of adminPushes) {
        assert.equal(ap.title, 'اشتراك هيخلص قريب');
        assert.match(ap.body, /مطعم الأصيل — \d\d\/\d\d\/\d\d\d\d/);
        assert.equal(ap.channel, 'orders_critical');
      }

      // Verify reminded_at is stamped
      const sub = (await db.query('select reminded_at from subscriptions where id = $1', [subId])).rows[0];
      assert.ok(sub.reminded_at);

      // Call a second time -> 0 reminded, no new pushes
      await db.exec('delete from push_outbox');
      const count2 = (await db.query('select public.remind_expiring_subscriptions() as c')).rows[0].c;
      assert.equal(count2, 0);
      const pushesAfter = (await db.query('select * from push_outbox')).rows;
      assert.equal(pushesAfter.length, 0);
    });
  });

  describe('D. Admin overview', () => {
    it('admin_subscriptions() refuses non-admin', async () => {
      await as(OWNER_A, { merchant_id: shopA, role: 'owner' });
      await assert.rejects(
        () => role('authenticated', () => db.query('select * from public.admin_subscriptions()')),
        /42501|only an admin/
      );

      await as(CUSTOMER);
      await assert.rejects(
        () => role('authenticated', () => db.query('select * from public.admin_subscriptions()')),
        /42501|only an admin/
      );
    });

    it('admin_subscriptions() returns every merchant ordered by newest expiry first then name', async () => {
      // Ensure one shop has pending request
      await as(OWNER_A, { merchant_id: shopA, role: 'owner' });
      await db.exec(`delete from subscription_requests where merchant_id = '${shopA}' and status = 'pending'`);
      const pendingReq = (await role('authenticated', () => db.query(`
        select * from public.request_subscription('basic', 1, 'cash')
      `))).rows[0];

      await as(ADMIN_1, { admin: true });
      const rows = (await role('authenticated', () => db.query('select * from public.admin_subscriptions()'))).rows;

      assert.ok(rows.length >= 3);

      // Check pending_request_id
      const shopARow = rows.find((r) => r.merchant_id === shopA);
      assert.ok(shopARow);
      assert.equal(shopARow.pending_request_id, pendingReq.id);

      const shopBRow = rows.find((r) => r.merchant_id === shopB);
      assert.ok(shopBRow);
      assert.equal(shopBRow.pending_request_id, null);

      // Check sorting: newest expiry first, nulls last, then name asc
      for (let i = 0; i < rows.length - 1; i++) {
        const a = rows[i];
        const b = rows[i + 1];
        if (a.plan_expires_at && b.plan_expires_at) {
          assert.ok(
            new Date(a.plan_expires_at) >= new Date(b.plan_expires_at),
            'expiry sorted newest first'
          );
        } else if (!a.plan_expires_at && b.plan_expires_at) {
          assert.fail('null expiry should be after non-null');
        }
      }
    });
  });

  describe('E. app.server_mode preservation', () => {
    it('app.server_mode is back to its prior value after each function', async () => {
      await as(ADMIN_1, { admin: true });

      const checkPreserved = async (sql, params = [], asServiceRole = false) => {
        await db.exec('begin');
        try {
          await db.query("select set_config('app.server_mode', 'custom_test_mode', true)");
          if (asServiceRole) {
            await db.query(sql, params);
          } else {
            await role('authenticated', () => db.query(sql, params));
          }
          const mode = (await db.query("select current_setting('app.server_mode', true) as m")).rows[0].m;
          assert.equal(mode, 'custom_test_mode');
        } finally {
          await db.exec('rollback');
        }
      };

      // 1. admin_subscriptions
      await checkPreserved('select * from public.admin_subscriptions()');

      // 2. remind_expiring_subscriptions
      await checkPreserved('select public.remind_expiring_subscriptions()', [], true);

      // 3. request_subscription (as owner)
      await as(OWNER_B, { merchant_id: shopB, role: 'owner' });
      await db.exec(`delete from subscription_requests where merchant_id = '${shopB}'`);

      await db.exec('begin');
      try {
        await db.query("select set_config('app.server_mode', 'custom_owner_mode', true)");
        await role('authenticated', () => db.query("select * from public.request_subscription('basic', 1, 'cash')"));
        const mode = (await db.query("select current_setting('app.server_mode', true) as m")).rows[0].m;
        assert.equal(mode, 'custom_owner_mode');
      } finally {
        await db.exec('rollback');
      }

      // 4. cancel_subscription_request
      await as(OWNER_B, { merchant_id: shopB, role: 'owner' });
      await db.exec(`delete from subscription_requests where merchant_id = '${shopB}'`);
      const reqForCancel = (await role('authenticated', () => db.query(`
        select * from public.request_subscription('basic', 1, 'cash')
      `))).rows[0];

      await db.exec('begin');
      try {
        await db.query("select set_config('app.server_mode', 'custom_cancel_mode', true)");
        await role('authenticated', () => db.query('select public.cancel_subscription_request($1)', [reqForCancel.id]));
        const mode = (await db.query("select current_setting('app.server_mode', true) as m")).rows[0].m;
        assert.equal(mode, 'custom_cancel_mode');
      } finally {
        await db.exec('rollback');
      }

      // 5. activate_subscription_request (as admin)
      await as(OWNER_B, { merchant_id: shopB, role: 'owner' });
      await db.exec(`delete from subscription_requests where merchant_id = '${shopB}'`);
      const reqForActivate = (await role('authenticated', () => db.query(`
        select * from public.request_subscription('basic', 1, 'cash')
      `))).rows[0];

      await as(ADMIN_1, { admin: true });
      await checkPreserved('select public.activate_subscription_request($1)', [reqForActivate.id]);

      // 6. reject_subscription_request (as admin on another request)
      await as(OWNER_B, { merchant_id: shopB, role: 'owner' });
      await db.exec(`delete from subscription_requests where merchant_id = '${shopB}'`);
      const reqForReject = (await role('authenticated', () => db.query(`
        select * from public.request_subscription('basic', 1, 'cash')
      `))).rows[0];

      await as(ADMIN_1, { admin: true });
      await checkPreserved('select public.reject_subscription_request($1, $2)', [reqForReject.id, 'سبب الرفض']);
    });
  });
  // PGlite has one connection, so the race itself cannot be staged here. What can be pinned
  // is that every function answering a request takes the row lock before reading its status.
  it('every function that answers a request locks it first', async () => {
    for (const fn of ['cancel_subscription_request', 'activate_subscription_request', 'reject_subscription_request']) {
      const src = (await db.query(`select prosrc from pg_proc where proname = $1`, [fn])).rows[0].prosrc;
      assert.match(src, /from public\.subscription_requests\s+where id = p_id\s+for update/i, fn);
    }
  });
});
