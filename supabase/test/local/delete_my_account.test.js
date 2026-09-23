import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

describe('delete_my_account address scrub', () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000b1';
  const OWNER = '00000000-0000-0000-0000-0000000000b2';

  let db, zoneId, merchantId;

  const as = (uid) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '{"app_metadata":{}}'::jsonb $fn$;`);

  const role = async (name, fn) => {
    await db.exec(`set role ${name}`);
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${CUSTOMER}'), ('${OWNER}');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('h02-edku', 'إدكو');
    `);

    zoneId = (await db.query(`
      insert into zones (city_id, name, default_delivery_fee)
      values ('h02-edku', 'المعدية', 1000) returning id;
    `)).rows[0].id;

    merchantId = (await db.query(`
      insert into merchants (city_id, type, name, zone_id, phone, status, owner_uid)
      values ('h02-edku', 'restaurant', 'مطعم الاختبار', $1,
              '01000000000', 'approved', $2)
      returning id;
    `, [zoneId, OWNER])).rows[0].id;
  });

  after(async () => {
    await db?.close();
  });

  it('keeps only the zone in the address while retaining the financial snapshot', async () => {
    const addressBefore = {
      zoneId,
      landmarkId: '00000000-0000-0000-0000-0000000000d2',
      landmarkName: 'مدرسة إدكو',
      landmarkNote: 'الباب الخلفي',
      street: 'شارع الجلاء',
      building: '٨',
      floor: '٢',
      apartment: '٥',
      label: 'المنزل',
      lat: 31.3072,
      lng: 30.2988,
    };
    const itemsBefore = [
      { itemId: 'dish-2', name: 'حواوشي', unitPrice: 9000, quantity: 3 },
    ];
    const pricingBefore = {
      subtotal: 27000,
      deliveryFee: 1000,
      discount: 0,
      total: 28000,
    };
    const revenueBefore = {
      model: 'commission',
      value: 500,
      basis: 27000,
      amount: 1350,
    };

    const orderId = (await db.query(`
      insert into orders (
        city_id, customer_uid, customer_name, customer_phone,
        merchant_id, merchant_name, zone_id, address, delivery_by,
        type, items, pricing, revenue, status
      ) values (
        'h02-edku', $1, 'محمد العميل', '01012345678',
        $2, 'مطعم الاختبار', $3, $4::jsonb, 'merchant',
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

    await as(CUSTOMER);
    await role('authenticated', () => db.query('select public.delete_my_account()'));

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
  });
});
