import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A11. A platform courier reads the platform orders they could still carry, not every
 * one the city ever placed.
 *
 * `read_orders` lets a courier read any order `is_courier_for_order` says is theirs, and
 * for a platform courier that included every platform order with nobody's name on it —
 * with no limit on status or age. So a rider could list months of cancelled and
 * escalated orders, each with a customer's name, phone, street and notes. The pool a
 * rider picks from is the live one; once an order is finished without them, it is none of
 * theirs. Their own orders stay readable forever — the statement is built from them.
 */
describe('a courier reads what they can carry', () => {
  const RIDER = '00000000-0000-0000-0000-0000000000d1';
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';
  let db, zoneId, shopId;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const asRider = async (fn) => {
    await as(RIDER, { role: 'courier', scope: 'platform' });
    await db.exec('set role authenticated');
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  const order = async (status, { courier = null, deliveryBy = 'platform' } = {}) =>
    (await db.query(`insert into orders (
        city_id, customer_uid, customer_name, customer_phone, merchant_id, merchant_name,
        zone_id, address, delivery_by, type, items, pricing, revenue, status, courier_uid)
      values ('a11', $1, 'عميل', '01012345678', $2, 'مطعم', $3,
        '{"street":"شارع الجلاء"}'::jsonb, $4, 'instant', '[]'::jsonb,
        '{"total":0}'::jsonb, '{"value":0}'::jsonb, $5, $6)
      returning id`, [CUSTOMER, shopId, zoneId, deliveryBy, status, courier])).rows[0].id;

  const canRead = (id) => asRider(async () =>
    (await db.query('select id from orders where id = $1', [id])).rows.length === 1);

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${RIDER}'), ('${CUSTOMER}');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('a11', 'إدكو');
      insert into staff (uid, scope, role, is_active)
        values ('${RIDER}', 'platform', 'courier', true);`);
    zoneId = (await db.query(`insert into zones (city_id, name, default_delivery_fee)
      values ('a11', 'المعدية', 1000) returning id`)).rows[0].id;
    shopId = (await db.query(`insert into merchants (city_id, type, name, zone_id, phone, status)
      values ('a11', 'restaurant', 'مطعم', $1, '0100', 'approved') returning id`,
      [zoneId])).rows[0].id;
  });

  after(async () => { await db?.close(); });

  for (const status of ['placed', 'accepted', 'preparing']) {
    it(`an unclaimed platform order that is ${status} is in the pool`, async () => {
      assert.equal(await canRead(await order(status)), true);
    });
  }

  for (const status of ['cancelled', 'delivered', 'needsAttention']) {
    it(`an unclaimed platform order that is ${status} is nobody's to read`, async () => {
      assert.equal(await canRead(await order(status)), false);
    });
  }

  it('their own orders stay readable, finished or not', async () => {
    assert.equal(await canRead(await order('delivered', { courier: RIDER })), true);
    assert.equal(await canRead(await order('cancelled', { courier: RIDER })), true);
  });
});
