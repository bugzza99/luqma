import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A complaint has an upper bound, as every other free text a customer writes now does.
 *
 * `order_issues.reason` took any length. The app caps what it sends, but the table is
 * written through PostgREST by a customer token, and a client that ignores the app's cap
 * can store a megabyte per complaint in the admin's queue — the same cheap way to fill a
 * free-tier database the name bound (A5) and the order note bound already close. The
 * topic line the assistant puts first plus the 500 the field takes fit well inside it.
 */
describe('a complaint is bounded', () => {
  let db, orderId, merchantId;
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';

  before(async () => {
    db = await freshDatabase();
    await db.exec(`insert into auth.users (id) values ('${CUSTOMER}');
      insert into cities (id, name) values ('cb', 'إدكو');`);
    const zone = (await db.query(`insert into zones (city_id, name) values ('cb', 'منطقة')
      returning id`)).rows[0].id;
    merchantId = (await db.query(`insert into merchants (city_id, type, name, zone_id, phone, status)
      values ('cb', 'restaurant', 'مطعم', $1, '0100', 'approved') returning id`, [zone])).rows[0].id;
    orderId = (await db.query(`insert into orders (city_id, customer_uid, customer_name,
        customer_phone, merchant_id, merchant_name, zone_id, type, items, pricing, status)
      values ('cb', $1, 'عميل', '0100', $2, 'مطعم', $3, 'instant', '[]', '{}', 'delivered')
      returning id`, [CUSTOMER, merchantId, zone])).rows[0].id;
  });
  after(async () => { await db?.close(); });

  const complain = (reason) => db.query(`insert into order_issues
      (order_id, customer_uid, merchant_id, reason) values ($1, $2, $3, $4)`,
    [orderId, CUSTOMER, merchantId, reason]);

  it('a real complaint, topic line and all, is taken', async () => {
    await complain('الأكل وصل بارد — ' + 'ا'.repeat(500));
  });

  it('a megabyte is not a complaint', async () => {
    await assert.rejects(complain('ا'.repeat(1001)), /check constraint/);
  });

  it('nor is nothing', async () => {
    await assert.rejects(complain('   '), /check constraint/);
  });
});
