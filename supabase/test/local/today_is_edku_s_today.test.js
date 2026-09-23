import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * E7. «اليوم» on the owner's screen is Edku's today, not Greenwich's.
 *
 * `admin_today` counted from `date_trunc('day', now())` — midnight UTC on hosted Postgres,
 * which is two or three in the morning in Edku. So everything between Edku's midnight and
 * that hour — Ramadan's suhoor orders, the late-night rush — was counted in the previous
 * day's figures, and the owner's «اليوم» at 1am showed yesterday. The statistics' weeks and
 * months had the same edge.
 *
 * D6. The unanswered-order sheet offered «كلّم المحل» only when a separate read of the
 * shop happened to have finished, which on the sheet it never had. The queue carries the
 * shop's phone itself now.
 */
describe("today is Edku's today", () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';
  let db, zoneId, shopId;

  const cairoMidnight = async () => (await db.query(
    `select (date_trunc('day', now() at time zone 'Africa/Cairo')
              at time zone 'Africa/Cairo') as t`)).rows[0].t;

  const orderAt = async (createdAt, status = 'placed') => (await db.query(`
    insert into orders (city_id, customer_uid, customer_name, customer_phone, merchant_id,
      merchant_name, zone_id, address, delivery_by, type, items, pricing, revenue, status,
      created_at)
    values ('e7', $1, 'عميل', '0100', $2, 'مطعم', $3, '{}'::jsonb, 'merchant', 'instant',
      '[]'::jsonb, '{"total":1000}'::jsonb, '{"value":0}'::jsonb, $4, $5)
    returning id`, [CUSTOMER, shopId, zoneId, status, createdAt])).rows[0].id;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${CUSTOMER}');
      insert into cities (id, name) values ('e7', 'إدكو');`);
    zoneId = (await db.query(`insert into zones (city_id, name, default_delivery_fee)
      values ('e7', 'منطقة', 1000) returning id`)).rows[0].id;
    shopId = (await db.query(`insert into merchants (city_id, type, name, zone_id, phone, status)
      values ('e7', 'restaurant', 'مطعم', $1, '01033334444', 'approved') returning id`,
      [zoneId])).rows[0].id;
  });

  after(async () => { await db?.close(); });

  it('an order placed just after midnight in Edku is today', async () => {
    const midnight = await cairoMidnight();
    const before = Number((await db.query('select admin_today() t')).rows[0].t.ordersToday);

    await orderAt(new Date(midnight.getTime() + 30 * 60 * 1000));
    await orderAt(new Date(midnight.getTime() - 30 * 60 * 1000));

    const after = Number((await db.query('select admin_today() t')).rows[0].t.ordersToday);
    assert.equal(after - before, 1, 'the one after midnight, and only that one');
  });

  it('an unanswered order carries the phone of the shop that did not answer', async () => {
    await orderAt(new Date(), 'needsAttention');

    const queue = (await db.query('select admin_today() t')).rows[0].t.needsAttention;
    assert.equal(queue[0].merchantPhone, '01033334444');
  });
});
