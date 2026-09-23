import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * An admin can delete anybody (except platform staff).
 *
 * Covers:
 * - Customer with orders
 * - Courier with attachment and delivered orders
 * - Merchant owner
 * - User with requested promotion
 * - Rejection of self-deletion, platform staff deletion, and non-admin callers
 * - Restoration of app.server_mode
 */
describe('an admin can delete anybody', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000a1';
  const OTHER_ADMIN = '00000000-0000-0000-0000-0000000000a2';
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';
  const OWNER = '00000000-0000-0000-0000-0000000000c2';
  const COURIER = '00000000-0000-0000-0000-0000000000c3';
  const PROMO_USER = '00000000-0000-0000-0000-0000000000c4';

  let db, zoneId, merchantId;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select ${uid ? `'${uid}'::uuid` : 'null::uuid'} $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const role = async (r, fn) => {
    await db.exec(`set role ${r}`);
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values
        ('${ADMIN}'), ('${OTHER_ADMIN}'), ('${CUSTOMER}'),
        ('${OWNER}'), ('${COURIER}'), ('${PROMO_USER}');
      insert into staff (uid, scope, role, is_active) values
        ('${ADMIN}', 'platform', 'admin', true),
        ('${OTHER_ADMIN}', 'platform', 'admin', true);
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;
    `);

    zoneId = (await db.query(`
      insert into zones (city_id, name, default_delivery_fee)
      values ('edku', 'المنطقة', 1000) returning id;
    `)).rows[0].id;

    merchantId = (await db.query(`
      insert into merchants (city_id, type, name, zone_id, phone, status, owner_uid)
      values ('edku', 'restaurant', 'مطعم الاختبار', $1, '01000000000', 'approved', $2)
      returning id;
    `, [zoneId, OWNER])).rows[0].id;

    await db.query(`
      insert into staff (uid, scope, role, merchant_id, is_active)
      values ($1, 'merchant', 'owner', $2, true);
    `, [OWNER, merchantId]);

    await db.query(`
      insert into staff (uid, scope, role, merchant_id, is_active)
      values ($1, 'merchant', 'courier', $2, true);
    `, [COURIER, merchantId]);
  });

  after(async () => {
    await db?.close();
  });

  it('admin deletes a customer with an order: order survives, customer fields scrubbed', async () => {
    const addressBefore = {
      zoneId,
      landmarkId: '00000000-0000-0000-0000-0000000000d1',
      landmarkName: 'المسجد الكبير',
      landmarkNote: 'بجوار الصيدلية',
      street: 'شارع البحر',
      building: '١٢',
      floor: '٣',
      apartment: '٧',
      label: 'البيت',
      lat: 31.3065,
      lng: 30.2994,
    };
    const itemsBefore = [
      { itemId: 'dish-1', name: 'كشري', unitPrice: 15000, quantity: 2 },
    ];
    const pricingBefore = {
      subtotal: 30000,
      deliveryFee: 1000,
      discount: 500,
      total: 30500,
    };
    const revenueBefore = {
      model: 'commission',
      value: 500,
      basis: 30000,
      amount: 1500,
    };
    const orderId = (await db.query(`
      insert into orders (
        city_id, customer_uid, customer_name, customer_phone,
        merchant_id, merchant_name, zone_id, address, delivery_by,
        type, items, pricing, revenue, status
      ) values (
        'edku', $1, 'أحمد العميل', '01012345678',
        $2, 'مطعم الاختبار', $3, $4::jsonb, 'platform',
        'instant', $5::jsonb, $6::jsonb, $7::jsonb, 'delivered'
      ) returning id;
    `, [
      CUSTOMER,
      merchantId,
      zoneId,
      JSON.stringify(addressBefore),
      JSON.stringify(itemsBefore),
      JSON.stringify(pricingBefore),
      JSON.stringify(revenueBefore),
    ])).rows[0].id;

    await as(ADMIN, { admin: true });
    await role('authenticated', () => db.query('select public.admin_delete_account($1)', [CUSTOMER]));

    // Customer auth user is gone
    const authUser = await db.query('select * from auth.users where id = $1', [CUSTOMER]);
    assert.equal(authUser.rowCount, 0);

    // Order survives with scrubbed details
    const order = (await db.query('select * from orders where id = $1', [orderId])).rows[0];
    assert.equal(order.customer_uid, null);
    assert.equal(order.customer_name, 'حساب محذوف');
    assert.equal(order.customer_phone, 'حساب محذوف');
    // An empty id beside the zone: nothing personal, and a shape every installed app can
    // read — a copy it cannot parse took the whole order list down (20261101310000).
    assert.deepEqual(order.address, { id: '', zoneId });
    assert.equal(order.zone_id, zoneId);
    assert.deepEqual(order.items, itemsBefore);
    assert.deepEqual(order.pricing, pricingBefore);
    assert.deepEqual(order.revenue, revenueBefore);

    // Audit log records deletion without personal details
    const audit = (await db.query(`
      select * from audit_log
       where action = 'account.deleted_by_admin'
       order by at desc limit 1
    `)).rows[0];
    assert.equal(audit.actor, ADMIN);
    assert.equal(audit.detail.kind, 'customer');
    assert.equal(audit.detail.ordersScrubbed, 1);
  });

  it('admin deletes a courier with an attachment and a delivered order', async () => {
    // Courier attachment was already created by staff trigger
    const attachId = (await db.query(`
      select id from courier_merchants where courier_uid = $1 and merchant_id = $2
    `, [COURIER, merchantId])).rows[0].id;

    // Create delivered order for courier
    const orderId = (await db.query(`
      insert into orders (
        city_id, customer_name, customer_phone, courier_uid,
        merchant_id, merchant_name, zone_id, address, delivery_by,
        type, items, pricing, revenue, status
      ) values (
        'edku', 'عميل آخر', '01011112222', $1,
        $2, 'مطعم الاختبار', $3, '{"street":"شارع"}'::jsonb, 'platform',
        'instant', '[]'::jsonb, '{"total":2000}'::jsonb, '{"platformShare":200}'::jsonb, 'delivered'
      ) returning id;
    `, [COURIER, merchantId, zoneId])).rows[0].id;

    await as(ADMIN, { admin: true });
    await role('authenticated', () => db.query('select public.admin_delete_account($1)', [COURIER]));

    // Courier auth user is gone
    const authUser = await db.query('select * from auth.users where id = $1', [COURIER]);
    assert.equal(authUser.rowCount, 0);

    // Delivered order survives and courier_uid is null
    const order = (await db.query('select * from orders where id = $1', [orderId])).rows[0];
    assert.equal(order.courier_uid, null);

    // Attachment in courier_merchants is inactive (either updated to is_active=false or removed with staff cascade)
    const att = await db.query('select * from courier_merchants where id = $1', [attachId]);
    assert.ok(att.rows.length === 0 || att.rows[0].is_active === false);
  });

  it('admin deletes an owner: merchant survives with owner_uid null', async () => {
    await as(ADMIN, { admin: true });
    await role('authenticated', () => db.query('select public.admin_delete_account($1)', [OWNER]));

    const authUser = await db.query('select * from auth.users where id = $1', [OWNER]);
    assert.equal(authUser.rowCount, 0);

    const merchant = (await db.query('select * from merchants where id = $1', [merchantId])).rows[0];
    assert.equal(merchant.owner_uid, null);
  });

  it('refuses non-admin caller', async () => {
    const randomUser = '00000000-0000-0000-0000-000000000099';
    await db.query('insert into auth.users (id) values ($1)', [randomUser]);

    await as(randomUser, {});
    await assert.rejects(
      () => role('authenticated', () => db.query('select public.admin_delete_account($1)', [randomUser])),
      /insufficient_privilege|authentication required/i
    );
  });

  it('refuses deleting a platform admin', async () => {
    await as(ADMIN, { admin: true });
    await assert.rejects(
      () => role('authenticated', () => db.query('select public.admin_delete_account($1)', [OTHER_ADMIN])),
      /cannot delete platform staff/i
    );
  });

  it('refuses deleting yourself', async () => {
    await as(ADMIN, { admin: true });
    await assert.rejects(
      () => role('authenticated', () => db.query('select public.admin_delete_account($1)', [ADMIN])),
      /cannot delete yourself/i
    );
  });

  it('a user who requested a promotion can be deleted (FK on delete set null)', async () => {
    const promoId = (await db.query(`
      insert into promotions (
        city_id, channel, merchant_id, requested_by, status,
        start_at, end_at, title
      ) values (
        'edku', 'homeBanner', $1, $2, 'requested',
        now(), now() + interval '7 days', 'عرض تجريبي'
      ) returning id;
    `, [merchantId, PROMO_USER])).rows[0].id;

    await as(ADMIN, { admin: true });
    await role('authenticated', () => db.query('select public.admin_delete_account($1)', [PROMO_USER]));

    const promo = (await db.query('select * from promotions where id = $1', [promoId])).rows[0];
    assert.equal(promo.requested_by, null, 'requested_by was set to null on user deletion');
  });

  it('app.server_mode is restored to its prior value afterwards', async () => {
    const tempUser = '00000000-0000-0000-0000-000000000088';
    await db.query('insert into auth.users (id) values ($1)', [tempUser]);

    await as(ADMIN, { admin: true });

    // One explicit transaction: the setting is transaction-local, so outside one autocommit
    // would put it back by itself and the assertion would pass whatever the function did.
    await db.exec('begin');
    try {
      await db.query("select set_config('app.server_mode', 'custom_mode', true)");
      await db.exec('set local role authenticated');
      await db.query('select public.admin_delete_account($1)', [tempUser]);
      const mode = (await db.query("select current_setting('app.server_mode', true) as m")).rows[0].m;
      assert.equal(mode, 'custom_mode');
    } finally {
      await db.exec('rollback');
    }
  });
});
