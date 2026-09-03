import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * A response that disappears after commit must not turn one dinner into two.
 *
 * These calls use an authenticated role and the public wrapper, not the priced function
 * behind it. That is the route a phone takes, including the default argument an old APK
 * still relies on.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

const uid = async () => (await q(
  "insert into auth.users (id, instance_id, aud, role) values (gen_random_uuid(), "
  + "'00000000-0000-0000-0000-000000000000','authenticated','authenticated') returning id",
)).rows[0].id;

/** Runs `fn` as one customer, in a transaction that is always rolled back. */
async function asCustomer(customerUid, fn) {
  await q('begin');
  try {
    await q("select set_config('role','authenticated',true)");
    await q("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
      sub: customerUid, role: 'authenticated', app_metadata: {},
    })]);
    return await fn();
  } finally {
    await q('rollback');
  }
}

describe('order placement idempotency', () => {
  let city, zone, merchant, item, customer;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = 'idempotency-' + Date.now();
    await q('insert into cities (id,name) values ($1,$2)', [city, 'مدينة']);
    zone = (await q(
      'insert into zones (city_id,name) values ($1,$2) returning id',
      [city, 'منطقة'],
    )).rows[0].id;

    // Every weekday, all day. A fixture about retries must not close because the suite
    // happened to cross midnight or run on Sunday.
    const openingHours = Array.from({ length: 7 }, (_, index) => ({
      weekday: index + 1, openMinute: 0, closeMinute: 1440,
    }));
    merchant = (await q(
      `insert into merchants (city_id,type,name,zone_id,phone,status,opening_hours)
       values ($1,'restaurant','مطعم',$2,'0100','approved',$3) returning id`,
      [city, zone, JSON.stringify(openingHours)],
    )).rows[0].id;
    item = (await q(
      `insert into menu_items (merchant_id,name,price)
       values ($1,'سمك',10000) returning id`,
      [merchant],
    )).rows[0].id;
    customer = await uid();
  });

  after(async () => {
    await q('delete from order_settlements where order_id in '
      + '(select id from orders where city_id = $1)', [city]).catch(() => {});
    await q('delete from orders where city_id = $1', [city]).catch(() => {});
    await q('delete from menu_items where merchant_id = $1', [merchant]).catch(() => {});
    await q('delete from merchants where city_id = $1', [city]).catch(() => {});
    await q('delete from zones where city_id = $1', [city]).catch(() => {});
    await q('delete from cities where id = $1', [city]).catch(() => {});
    await q('delete from auth.users where id = $1', [customer]).catch(() => {});
    await db.end();
  });

  const draft = () => JSON.stringify({
    merchantId: merchant,
    type: 'instant',
    items: [{ itemId: item, name: 'لا يصدق', unitPrice: 1, quantity: 1 }],
  });

  const place = async (clientOrderId) => {
    const result = clientOrderId === undefined
      ? await q('select place_order($1::jsonb) as placed', [draft()])
      : await q('select place_order($1::jsonb,$2::uuid) as placed',
                [draft(), clientOrderId]);
    return result.rows[0].placed;
  };

  it('returns the first order when the same client id is sent twice', async () => {
    await asCustomer(customer, async () => {
      const clientOrderId = '11111111-1111-4111-8111-111111111111';
      const first = await place(clientOrderId);
      const retry = await place(clientOrderId);

      assert.deepEqual(retry, first, 'the retry returns the committed order');
      const rows = await q(
        'select id from orders where customer_uid = $1 and client_order_id = $2',
        [customer, clientOrderId],
      );
      assert.equal(rows.rowCount, 1, 'one checkout has one order');
    });
  });

  it('places two orders for two different client ids', async () => {
    await asCustomer(customer, async () => {
      const first = await place('11111111-1111-4111-8111-111111111111');
      const second = await place('22222222-2222-4222-8222-222222222222');

      assert.notEqual(second.id, first.id);
      assert.equal((await q(
        'select 1 from orders where customer_uid = $1 and client_order_id is not null',
        [customer],
      )).rowCount, 2);
    });
  });

  it('still places an order when the optional id is omitted', async () => {
    await asCustomer(customer, async () => {
      const placed = await place();

      assert.ok(placed.id);
      assert.equal((await q(
        'select client_order_id from orders where id = $1', [placed.id],
      )).rows[0].client_order_id, null);
    });
  });

  it('does not let the customer rewrite the id after placement', async () => {
    await asCustomer(customer, async () => {
      const placed = await place('11111111-1111-4111-8111-111111111111');

      await assert.rejects(
        q('update orders set client_order_id = $2 where id = $1', [
          placed.id, '22222222-2222-4222-8222-222222222222',
        ]),
        (error) => error.code === '42501',
      );
    });
  });

  it('lets the unique index settle two requests that arrive together', async () => {
    const clientOrderId = '33333333-3333-4333-8333-333333333333';
    const connections = [
      new Client({ connectionString: DB }),
      new Client({ connectionString: DB }),
    ];
    await Promise.all(connections.map((connection) => connection.connect()));

    const concurrentPlace = async (connection) => {
      await connection.query('begin');
      try {
        await connection.query("select set_config('role','authenticated',true)");
        await connection.query("select set_config('request.jwt.claims',$1,true)", [
          JSON.stringify({ sub: customer, role: 'authenticated', app_metadata: {} }),
        ]);
        const result = await connection.query(
          'select place_order($1::jsonb,$2::uuid) as placed',
          [draft(), clientOrderId],
        );
        await connection.query('commit');
        return result.rows[0].placed;
      } catch (error) {
        await connection.query('rollback');
        throw error;
      }
    };

    try {
      const [first, second] = await Promise.all(
        connections.map((connection) => concurrentPlace(connection)),
      );
      assert.deepEqual(second, first, 'both callers receive the one winning row');
      assert.equal((await q(
        'select 1 from orders where customer_uid = $1 and client_order_id = $2',
        [customer, clientOrderId],
      )).rowCount, 1);
    } finally {
      await Promise.all(connections.map((connection) => connection.end()));
      await q('delete from orders where customer_uid = $1 and client_order_id = $2',
              [customer, clientOrderId]);
    }
  });
});
