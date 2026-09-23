import { describe, it } from 'node:test';
import { strictEqual } from 'node:assert';
import { freshDatabase } from './harness.mjs';

/**
 * Two customer notifications that were not news.
 *
 * `queue_order_status_push` told a customer «الأوردر اتلغى» for an order they had just
 * cancelled themselves, with the phone still in their hand. And a status push that
 * failed kept being retried on the spacing that exists so an application reaches an
 * admin who installs the app that evening — so «اتقبل طلبك» could arrive seven hours
 * after the food had. An order's news is only news for half an hour.
 */
describe('a customer is told only what is news', () => {
  const OWNER = '00000000-0000-0000-0000-0000000000a1';
  const COURIER = '00000000-0000-0000-0000-0000000000a2';
  const CUSTOMER = '00000000-0000-0000-0000-0000000000a3';
  const MERCHANT = '00000000-0000-0000-0000-0000000000b1';
  const ZONE = '00000000-0000-0000-0000-000000000001';

  const db = async () => {
    const d = await freshDatabase();

    for (const uid of [OWNER, COURIER, CUSTOMER]) {
      await d.query(`insert into auth.users (id) values ($1)`, [uid]);
    }
    // ensure_user_profile already made the users rows; this only adds the tokens a
    // phone would have registered.
    await d.query(
      `update users set fcm_tokens = array['tok-owner-1','tok-owner-2'] where id = $1`,
      [OWNER],
    );

    await d.query(`insert into cities (id, name) values ('edku', 'إدكو')`);
    await d.query(
      `insert into zones (id, city_id, name, default_delivery_fee)
       values ($1, 'edku', 'وسط', 1000)`,
      [ZONE],
    );
    await d.query(
      `insert into merchants (id, city_id, type, name, zone_id, phone, status)
       values ($1, 'edku', 'restaurant', 'مطعم البحر', $2, '0100', 'approved')`,
      [MERCHANT, ZONE],
    );
    await d.query(
      `insert into staff (uid, scope, role, merchant_id)
       values ($1, 'merchant', 'owner', $2), ($3, 'merchant', 'courier', $2)`,
      [OWNER, MERCHANT, COURIER],
    );
    return d;
  };

  /** Places an order the way place_order would, minus the pricing. */
  const placeOrder = (d, { type = 'instant' } = {}) =>
    d.query(
      `insert into orders (city_id, merchant_id, customer_uid, type, status,
                           zone_id, address, items, pricing,
                           customer_phone, customer_name, merchant_name)
       values ('edku', $1, $2, $3, 'placed', $4, '{}'::jsonb, '[]'::jsonb,
               '{}'::jsonb, '0100', 'العميل', 'مطعم البحر')
       returning id`,
      [MERCHANT, CUSTOMER, type, ZONE],
    );

  const cancel = (d, id, by) => d.query(
    `do $$ begin
       perform set_config('app.server_mode', 'on', true);
       update public.orders set status = 'cancelled', cancelled_by = '${by}',
              cancel_reason = 'x' where id = '${id}';
     end $$;`);

  const customerPushes = async (d) => (await d.query(
    `select count(*)::int n from push_outbox where uid = $1`, [CUSTOMER])).rows[0].n;

  it('a customer who cancelled is not told that it was cancelled', async () => {
    const d = await db();
    const id = (await placeOrder(d)).rows[0].id;
    await cancel(d, id, 'customer');
    strictEqual(await customerPushes(d), 0);
  });

  it('a shop that cancelled still tells them', async () => {
    const d = await db();
    const id = (await placeOrder(d)).rows[0].id;
    await cancel(d, id, 'merchant');
    strictEqual(await customerPushes(d), 1);
  });

  it('an order status older than half an hour is not sent, and not kept', async () => {
    const d = await db();
    await d.query(
      `insert into push_outbox (uid, title, body, data, channel, created_at)
       values ($1, 'اتقبل طلبك', 'x', '{"kind":"orderStatus","orderId":"o"}', 'orders',
               now() - interval '31 minutes'),
              ($1, 'اتقبل طلبك', 'y', '{"kind":"orderStatus","orderId":"p"}', 'orders',
               now() - interval '5 minutes')`, [CUSTOMER]);
    await d.query('delete from push_outbox where uid <> $1', [CUSTOMER]);

    const { rows } = await d.query('select * from claim_push_batch(10)');
    strictEqual(rows.length, 1, 'only the recent one is claimed');
    strictEqual(rows[0].body, 'y');

    const stale = (await d.query(
      `select attempts, last_error from push_outbox where body = 'x'`)).rows[0];
    strictEqual(stale.attempts, 5, 'retired, so it leaves the queue index');
    strictEqual(stale.last_error, 'too late to be news');
  });

  it('an alarm for the kitchen is not retired by age', async () => {
    const d = await db();
    await d.query('delete from push_outbox');
    await d.query(
      `insert into push_outbox (uid, title, body, data, channel, created_at)
       values ($1, 'أوردر جديد', 'z', '{"kind":"newOrder"}', 'orders_critical',
               now() - interval '2 hours')`, [OWNER]);
    const { rows } = await d.query('select * from claim_push_batch(10)');
    strictEqual(rows.length, 1);
  });
});
