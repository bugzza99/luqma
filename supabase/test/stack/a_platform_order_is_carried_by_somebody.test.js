import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * A platform order is never delivered without a courier on it.
 *
 * MerchantApp's live board offered the owner «خرج للتوصيل» from `preparing` on every
 * order, and the transitions allowed it. On a platform order that wrote the status alone,
 * and `markOnTheWay` — the one path that puts a rider's name on an order — starts from
 * `preparing`, so no rider could take it afterwards. Any platform courier could still
 * deliver an order with nobody on it, and the settlement read the null courier as "the
 * shop delivered": a zero row, nothing on any rider's statement, and no record of who held
 * the customer's cash.
 *
 * Every move here goes through a real token and a real `staff` row. A test that moved the
 * order with `app.server_mode` on would stand down the very trigger under test.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

/** Runs `fn` as the given identity, in a transaction that is always rolled back. */
async function as(identity, fn) {
  await q('begin');
  try {
    await q("select set_config('role', 'authenticated', true)");
    await q("select set_config('request.jwt.claims', $1, true)", [JSON.stringify({
      sub: identity.uid, role: 'authenticated', app_metadata: identity.claims,
    })]);
    return await fn();
  } finally {
    await q('rollback');
  }
}

/** The error `fn` raised as `identity`, or null when it was allowed. */
const refused = (identity, fn) => as(identity, async () => {
  try {
    await fn();
    return null;
  } catch (error) {
    return error;
  }
});

const uid = async () => (await q(
  "insert into auth.users (id, instance_id, aud, role) values (gen_random_uuid(), " +
  "'00000000-0000-0000-0000-000000000000','authenticated','authenticated') returning id",
)).rows[0].id;

describe('a platform order is carried by somebody', () => {
  let city, zone, shop, customer, owner, rider, admin;

  /** An order at `status`, inserted the way `place_order` inserts one: as the server. */
  const makeOrder = async ({ status = 'preparing', deliveryBy = 'platform',
                             courierUid = null } = {}) => {
    await q('begin');
    try {
      await q("select set_config('app.server_mode','on',true)");
      const id = (await q(
        `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                             merchant_id, merchant_name, zone_id, type, items, pricing,
                             status, courier_uid, delivery_by)
         values ($1, $2, 'عميل', '01000000000', $3, 'مطعم', $4, 'instant', '[]'::jsonb,
                 '{"subtotal":20000,"deliveryFee":2000,"total":22000}'::jsonb,
                 $5, $6, $7) returning id`,
        [city, customer, shop, zone, status, courierUid, deliveryBy])).rows[0].id;
      await q('commit');
      return id;
    } catch (e) { await q('rollback'); throw e; }
  };

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = 'carried-' + Date.now();
    await q('insert into cities (id, name) values ($1, $2)', [city, 'مدينة المندوب']);
    zone = (await q('insert into zones (city_id, name) values ($1, $2) returning id',
                    [city, 'منطقة'])).rows[0].id;
    shop = (await q(
      `insert into merchants (city_id, type, name, zone_id, phone, status)
       values ($1, 'restaurant', 'مطعم', $2, '0100', 'approved') returning id`,
      [city, zone])).rows[0].id;

    customer = await uid();
    await q('insert into users (id) values ($1) on conflict (id) do nothing', [customer]);

    owner = { uid: await uid(),
              claims: { role: 'owner', scope: 'merchant', merchant_id: shop } };
    rider = { uid: await uid(), claims: { role: 'courier', scope: 'platform' } };
    admin = { uid: await uid(), claims: { admin: true, role: 'admin', scope: 'platform' } };

    // `staff_attach_initial_courier` gives the platform rider the platform row.
    for (const [person, scope, role, m] of [
      [owner, 'merchant', 'owner', shop],
      [rider, 'platform', 'courier', null],
      [admin, 'platform', 'admin', null],
    ]) {
      await q('insert into staff (uid, scope, role, merchant_id) values ($1, $2, $3, $4)',
              [person.uid, scope, role, m]);
    }
  });

  after(async () => {
    const people = [owner?.uid, rider?.uid, admin?.uid].filter(Boolean);
    for (const [sql, params] of [
      // Settlements first: both are `on delete restrict` on the order. Nothing below
      // commits one, but a failure half-way through a future edit could.
      ['delete from courier_settlements where order_id in (select id from orders where city_id = $1)', [city]],
      ['delete from order_settlements where order_id in (select id from orders where city_id = $1)', [city]],
      ['delete from orders where city_id = $1', [city]],
      ['delete from staff where uid = any($1)', [people]],
      ['delete from merchants where city_id = $1', [city]],
      ['delete from zones where city_id = $1', [city]],
      ['delete from cities where id = $1', [city]],
      ['delete from auth.users where id = any($1)', [[...people, customer]]],
    ]) await q(sql, params).catch((e) => console.error('teardown:', sql, e.message));
    await db?.end();
  });

  describe('the shop', () => {
    it('may not send a platform order out', async () => {
      const id = await makeOrder();

      const error = await refused(owner, () => q(
        "update orders set status = 'outForDelivery' where id = $1", [id]));

      assert.ok(error, 'the shop sent out an order no rider was on');
      assert.equal(error.code, '23514', error.message);
      assert.match(error.message, /courier/);
    });

    // The shop's own rider flow is unchanged: the owner still sends out what they carry.
    it('still sends out an order its own rider carries', async () => {
      const id = await makeOrder({ deliveryBy: 'merchant' });

      const status = await as(owner, async () => (await q(
        "update orders set status = 'outForDelivery' where id = $1 returning status",
        [id])).rows[0]?.status);

      assert.equal(status, 'outForDelivery');
    });
  });

  describe('delivering it', () => {
    it('refuses a courier delivering a platform order nobody took', async () => {
      // Out with nobody on it: where the shop's tap used to leave an order, and where any
      // platform rider could then deliver it anonymously.
      const id = await makeOrder({ status: 'outForDelivery' });

      const error = await refused(rider, () => q(
        "update orders set status = 'delivered', delivered_at = now() where id = $1", [id]));

      assert.ok(error, 'delivered with no courier on the order');
      assert.equal(error.code, '23514', error.message);
      assert.match(error.message, /courier/);
    });

    // Not excepted: nothing in AdminApp moves an order to `delivered`, and an admin who
    // did would be settling a delivery nobody is on record as having made.
    it('refuses a platform admin delivering one nobody took', async () => {
      const id = await makeOrder({ status: 'outForDelivery' });

      const error = await refused(admin, () => q(
        "update orders set status = 'delivered', delivered_at = now() where id = $1", [id]));

      assert.ok(error, 'an admin delivered an order with no courier on it');
      assert.equal(error.code, '23514', error.message);
    });

    // The rule is about the row as it will be. Judged on the row as it was, an admin could
    // turn a shop's order into a platform one and deliver it in one statement: the check
    // saw a merchant order, the admin's exit let it through, and the settlement recorded
    // `merchantDelivery` at zero on a platform order nobody carried.
    it('refuses an admin making it a platform order and delivering it at once', async () => {
      const id = await makeOrder({ status: 'outForDelivery', deliveryBy: 'merchant' });

      const error = await refused(admin, () => q(
        `update orders set delivery_by = 'platform', status = 'delivered',
                           delivered_at = now()
          where id = $1`, [id]));

      assert.ok(error, 'an admin made it a platform order and delivered it with nobody on it');
      assert.equal(error.code, '23514', error.message);
      assert.match(error.message, /courier/);
    });

    it('carries the normal path through, and charges the rider who carried it', async () => {
      const id = await makeOrder();

      // Read inside the same `as()`: it rolls back, and a read after it sees nothing.
      const settled = await as(rider, async () => {
        // A known rate, so the amount below is a figure rather than "something". Set as the
        // owner inside this transaction and handed back to the rider's role before either
        // update: the rollback takes it with everything else, so the shared test project's
        // config is never changed, and neither courier update runs in server mode.
        await q('set local role postgres');
        await q(`insert into config (key, value) values ('courier_commission_percent', '10'::jsonb)
                 on conflict (key) do update set value = excluded.value`);
        await q('set local role authenticated');

        // `markOnTheWay`: the status and the name in one update.
        await q("update orders set status = 'outForDelivery', courier_uid = $2 where id = $1",
                [id, rider.uid]);
        // `markDelivered`: the status alone, the name already on the row.
        await q("update orders set status = 'delivered', delivered_at = now() where id = $1",
                [id]);
        return (await q(
          'select courier_uid, ground, amount from courier_settlements where order_id = $1',
          [id])).rows[0];
      });

      assert.ok(settled, 'a delivered order leaves a courier row');
      assert.equal(settled.courier_uid, rider.uid);
      assert.equal(settled.ground, 'platform');
      // 10% of a 2000-piastre fee with no discount: 2000 × 1000 bps ÷ 10000 = 200.
      assert.equal(settled.amount, 200);
    });
  });
});
