import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * L3. A delivery is dated when it happened, and never outside what the server can vouch
 * for.
 *
 * `markDelivered` stamped `delivered_at` from the phone at the moment the request was
 * sent — so a tap queued offline at 23:50 and sent at 01:10 landed on the next day's
 * statement, and a phone whose clock was wrong wrote any date at all. The phone now sends
 * the moment of the tap, and the server keeps it only between the moment the order went
 * out for delivery and now; outside that it takes the nearer edge, and with nothing sent
 * it takes now.
 */
describe('a delivery is dated when it happened', () => {
  let db, zoneId, merchantId;

  /** An order that went out for delivery [minutesAgo] minutes ago. */
  const outFor = async (minutesAgo) => (await db.query(`
    insert into orders (
      city_id, customer_name, customer_phone, merchant_id, merchant_name, zone_id,
      address, delivery_by, type, items, pricing, revenue, status, status_history
    ) values ('dd', 'عميل', '0100', $1, 'مطعم', $2, '{}'::jsonb, 'merchant', 'instant',
      '[]'::jsonb, '{"total":1000}'::jsonb, '{}'::jsonb, 'outForDelivery',
      jsonb_build_array(jsonb_build_object('from', 'preparing', 'to', 'outForDelivery',
        'by', 'courier', 'at', now() - make_interval(mins => $3))))
    returning id`, [merchantId, zoneId, minutesAgo])).rows[0].id;

  const deliver = (id, at) => db.query(`do $$ begin
      perform set_config('app.server_mode', 'on', true);
      update public.orders set status = 'delivered',
             delivered_at = ${at === null ? 'null' : `'${at}'::timestamptz`}
       where id = '${id}';
    end $$;`);

  /** Minutes between delivered_at and now, rounded. */
  const minutesAgo = async (id) => Math.round((await db.query(
    `select extract(epoch from now() - delivered_at) / 60 as m from orders where id = $1`,
    [id])).rows[0].m);

  before(async () => {
    db = await freshDatabase();
    await db.exec(`insert into cities (id, name) values ('dd', 'إدكو');`);
    zoneId = (await db.query(`insert into zones (city_id, name) values ('dd', 'منطقة')
      returning id`)).rows[0].id;
    merchantId = (await db.query(`insert into merchants
      (city_id, type, name, zone_id, phone, status)
      values ('dd', 'restaurant', 'مطعم', $1, '0100', 'approved') returning id`,
      [zoneId])).rows[0].id;
  });
  after(async () => { await db?.close(); });

  const ago = async (minutes) => (await db.query(
    `select (now() - make_interval(mins => $1))::text as t`, [minutes])).rows[0].t;

  it('the moment of the tap is kept when it is plausible', async () => {
    const id = await outFor(80);
    await deliver(id, await ago(60));
    assert.equal(await minutesAgo(id), 60);
  });

  it('a date in the future is today', async () => {
    const id = await outFor(30);
    await deliver(id, '2099-01-01T00:00:00Z');
    assert.equal(await minutesAgo(id), 0);
  });

  it('a date before it went out is when it went out', async () => {
    const id = await outFor(30);
    await deliver(id, '2001-01-01T00:00:00Z');
    assert.equal(await minutesAgo(id), 30);
  });

  it('nothing sent is now', async () => {
    const id = await outFor(30);
    await deliver(id, null);
    const row = (await db.query('select delivered_at from orders where id = $1', [id])).rows[0];
    assert.notEqual(row.delivered_at, null, 'a delivery always has a date');
    assert.equal(await minutesAgo(id), 0);
  });
});
