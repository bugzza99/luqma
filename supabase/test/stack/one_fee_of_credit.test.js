import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * A7. One order's worth of prepaid credit funds one order — even when two customers
 * press «اطلب» in the same instant.
 *
 * Placement reads the merchant row without a lock, so two placements could both see the
 * same free credit and both be held against it. Sequential tests cannot show that; this
 * file opens two real sessions, starts both placements, and lets them race. The fix is a
 * conditional hold under the row lock, so exactly one of them commits.
 *
 * Unlike the rest of the stack suite these transactions commit — a rollback cannot show
 * what the second session sees after the first has finished — so the fixture is its own
 * city and is removed in `after`.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

const FEE = 500;
let db, first, second;
let city, zone, merchant, item, customerA, customerB;
const addressOf = {};

const newUser = async () => (await db.query(
  "insert into auth.users (id, instance_id, aud, role) values (gen_random_uuid(), "
  + "'00000000-0000-0000-0000-000000000000','authenticated','authenticated') returning id",
)).rows[0].id;

const place = async (client, customer) => {
  await client.query('begin');
  await client.query("select set_config('role','authenticated',true)");
  await client.query("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
    sub: customer, role: 'authenticated', app_metadata: {},
  })]);
  await client.query('select place_order($1::jsonb)', [JSON.stringify({
    merchantId: merchant, type: 'instant', addressId: addressOf[customer],
    items: [{ itemId: item, name: 'سمك', unitPrice: 10000, quantity: 1 }],
  })]);
};

describe('one fee of prepaid credit is one order', () => {
  before(async () => {
    db = new Client({ connectionString: DB });
    first = new Client({ connectionString: DB });
    second = new Client({ connectionString: DB });
    await Promise.all([db.connect(), first.connect(), second.connect()]);

    city = 'one-fee-' + Date.now();
    await db.query('insert into cities (id,name) values ($1,$2)', [city, 'مدينة']);
    zone = (await db.query(
      'insert into zones (city_id,name,default_delivery_fee) values ($1,$2,0) returning id',
      [city, 'منطقة'])).rows[0].id;
    const openingHours = Array.from({ length: 7 }, (_, index) => ({
      weekday: index + 1, openMinute: 0, closeMinute: 1440,
    }));
    merchant = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status,opening_hours,
                              delivers_self,revenue_model,revenue_value,wallet_balance)
       values ($1,'restaurant','مطعم',$2,'0100','approved',$3,true,'prepaid',$4,$4)
       returning id`,
      [city, zone, JSON.stringify(openingHours), FEE])).rows[0].id;
    item = (await db.query(
      `insert into menu_items (merchant_id,name,price) values ($1,'سمك',10000) returning id`,
      [merchant])).rows[0].id;
    customerA = await newUser();
    customerB = await newUser();
    for (const c of [customerA, customerB]) {
      await db.query(`update users set name='عميل', phone='01000000000' where id=$1`, [c]);
      // Food to be delivered names where it goes (20261101190000).
      addressOf[c] = (await db.query(
        `insert into addresses (user_id,zone_id,label) values ($1,$2,'البيت') returning id`,
        [c, zone])).rows[0].id;
    }
  });

  after(async () => {
    for (const c of [first, second]) await c.query('rollback').catch(() => {});
    await db.query('delete from orders where city_id = $1', [city]).catch(() => {});
    await db.query('delete from menu_items where merchant_id = $1', [merchant]).catch(() => {});
    await db.query('delete from menu_categories where merchant_id = $1', [merchant]).catch(() => {});
    await db.query('delete from merchants where city_id = $1', [city]).catch(() => {});
    await db.query('delete from addresses where zone_id = $1', [zone]).catch(() => {});
    await db.query('delete from zones where city_id = $1', [city]).catch(() => {});
    await db.query('delete from cities where id = $1', [city]).catch(() => {});
    await db.query('delete from auth.users where id = any($1)', [[customerA, customerB]])
      .catch(() => {});
    await Promise.all([db.end(), first.end(), second.end()]);
  });

  it('two placements racing for one fee of credit: exactly one commits', async () => {
    // The first holds the merchant row until it commits; the second's hold waits on that
    // lock, re-reads the row, and must be refused rather than held a second time.
    await place(first, customerA);
    const racing = place(second, customerB).then(
      () => second.query('commit').then(() => 'committed'),
      async (error) => { await second.query('rollback'); return error.message; },
    );
    // Give the second session time to reach the lock before the first lets go.
    await new Promise((resolve) => setTimeout(resolve, 500));
    await first.query('commit');

    const outcome = await racing;
    assert.match(String(outcome), /not accepting orders/);

    const orders = (await db.query(
      'select count(*)::int n from orders where merchant_id = $1', [merchant])).rows[0].n;
    assert.equal(orders, 1);
    const wallet = (await db.query(
      'select wallet_balance, wallet_held from merchants where id = $1', [merchant])).rows[0];
    assert.equal(wallet.wallet_held, FEE, 'held once');
    assert.equal(wallet.wallet_balance, FEE);
  });
});
