import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * An order nobody answered can be let go by the person waiting for it.
 *
 * An order moves to `needsAttention` when the shop lets its accept deadline pass, and only
 * an admin could move it from there. At night nobody does: the customer sat in front of
 * «بيحتاج مراجعة» with no button, and a prepaid shop's hold stayed held. The owner decided
 * (2026-09-23): after fifteen minutes in that state the customer may cancel it themselves.
 * Fifteen minutes is the admin's chance to rescue the order by telephoning the shop.
 */
describe('an order nobody answered can be let go', () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';
  const OTHER = '00000000-0000-0000-0000-0000000000c2';
  let db, zoneId, merchantId;

  const as = (uid) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '{"app_metadata":{}}'::jsonb $fn$;`);

  const asRole = async (fn) => {
    await db.exec('set role authenticated');
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  /** An order that entered needsAttention [minutes] ago, the way the escalation writes it. */
  const escalated = async (minutes) => (await db.query(`
    insert into orders (
      city_id, customer_uid, customer_name, customer_phone, merchant_id, merchant_name,
      zone_id, address, delivery_by, type, items, pricing, revenue, status,
      accept_deadline_at, status_history
    ) values (
      'na', $1, 'عميل', '01012345678', $2, 'مطعم', $3, '{}'::jsonb, 'merchant',
      'instant', '[]'::jsonb, '{"subtotal":9000,"total":10000}'::jsonb,
      '{"model":"commission","value":0}'::jsonb, 'needsAttention',
      now() - make_interval(mins => $4 + 1),
      jsonb_build_array(jsonb_build_object('from', 'placed', 'to', 'needsAttention',
        'by', 'system', 'at', now() - make_interval(mins => $4)))
    ) returning id`, [CUSTOMER, merchantId, zoneId, minutes])).rows[0].id;

  const cancel = (id) => asRole(() => db.query(
    `update orders set status = 'cancelled', cancelled_by = 'customer',
            cancel_reason = 'محدش ردّ' where id = $1`, [id]));
  const status = async (id) => (await db.query(
    'select status from orders where id = $1', [id])).rows[0].status;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${CUSTOMER}'), ('${OTHER}');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('na', 'إدكو');`);
    zoneId = (await db.query(`insert into zones (city_id, name) values ('na', 'منطقة')
      returning id`)).rows[0].id;
    merchantId = (await db.query(`insert into merchants
      (city_id, type, name, zone_id, phone, status)
      values ('na', 'restaurant', 'مطعم', $1, '0100', 'approved') returning id`,
      [zoneId])).rows[0].id;
  });
  after(async () => { await db?.close(); });

  it('after fifteen minutes the customer may cancel it', async () => {
    const id = await escalated(16);
    await as(CUSTOMER);
    await cancel(id);
    assert.equal(await status(id), 'cancelled');
  });

  it("before then it is still the admin's to rescue", async () => {
    const id = await escalated(5);
    await as(CUSTOMER);
    await assert.rejects(cancel(id), /may not move an order/);
    assert.equal(await status(id), 'needsAttention');
  });

  it("and it is only ever the customer's own order", async () => {
    const id = await escalated(30);
    await as(OTHER);
    await cancel(id);
    assert.equal(await status(id), 'needsAttention',
      "somebody else's order is not theirs to see, let alone cancel");
  });
});
