import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * A6. A shop's money is read by the shop and the platform, not by whoever holds the app.
 *
 * `merchants` was granted whole to `anon` and `authenticated` with a row policy alone, so
 * the key inside every APK read every shop's wallet, debt, hold and negotiated rate. The
 * columns a customer's screen draws stay readable; the money is answered by
 * `merchant_money` to the owner and to staff, and one generated boolean tells a customer
 * whether a prepaid shop can take one more order.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

const uid = async () => (await q(
  "insert into auth.users (id, instance_id, aud, role) values (gen_random_uuid(), " +
  "'00000000-0000-0000-0000-000000000000','authenticated','authenticated') returning id",
)).rows[0].id;

/** Runs `fn` as one identity, in a transaction that is always rolled back. */
async function as(identity, fn) {
  await q('begin');
  try {
    if (identity === 'anon') {
      await q("select set_config('role','anon',true)");
      await q("select set_config('request.jwt.claims','{\"role\":\"anon\"}',true)");
    } else {
      await q("select set_config('role','authenticated',true)");
      await q("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
        sub: identity.uid, role: 'authenticated', app_metadata: identity.claims ?? {},
      })]);
    }
    return await fn();
  } finally {
    await q('rollback');
  }
}

const denied = (error) => {
  assert.equal(error.code, '42501', `expected 42501, got ${error.code}: ${error.message}`);
  return true;
};

describe("a shop's money is its own", () => {
  let city, zone, shop, broke, admin, owner, customer;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = 'money-' + Date.now();
    await q('insert into cities (id,name) values ($1,$2)', [city, 'مدينة']);
    zone = (await q('insert into zones (city_id,name) values ($1,$2) returning id',
                    [city, 'منطقة'])).rows[0].id;
    await q("select set_config('app.server_mode','on',false)");
    shop = (await q(
      `insert into merchants (city_id,type,name,zone_id,phone,status,revenue_model,
                              revenue_value,commission_owed)
       values ($1,'restaurant','مطعم',$2,'0100','approved','commission',1000,47500)
       returning id`, [city, zone])).rows[0].id;
    broke = (await q(
      `insert into merchants (city_id,type,name,zone_id,phone,status,revenue_model,
                              revenue_value,wallet_balance)
       values ($1,'restaurant','مطعم مفلس',$2,'0101','approved','prepaid',500,300)
       returning id`, [city, zone])).rows[0].id;
    await q("select set_config('app.server_mode','',false)");

    admin = await uid();
    await q("insert into staff (uid,scope,role) values ($1,'platform','admin')", [admin]);
    owner = await uid();
    await q("insert into staff (uid,scope,role,merchant_id) values ($1,'merchant','owner',$2)",
            [owner, shop]);
    customer = await uid();
  });

  after(async () => {
    await q('delete from staff where uid = any($1)', [[admin, owner]]).catch(() => {});
    for (const sql of [
      'delete from merchants where city_id = $1',
      'delete from zones where city_id = $1',
      'delete from cities where id = $1',
    ]) await q(sql, [city]).catch((e) => console.error('teardown:', e.message));
    await q('delete from auth.users where id = any($1)', [[admin, owner, customer]])
      .catch(() => {});
    await db.end();
  });

  const ADMIN = () => ({ uid: admin, claims: { admin: true, role: 'admin', scope: 'platform' } });
  const OWNER = () => ({ uid: owner,
                         claims: { role: 'owner', scope: 'merchant', merchant_id: shop } });
  const money = (ids) => q('select * from merchant_money($1::uuid[])', [ids]);

  it('the key inside the app cannot read what a shop owes', () => assert.rejects(
    as('anon', () => q('select commission_owed from merchants where id = $1', [shop])),
    denied));

  it('nor can a signed-in customer read a wallet', () => assert.rejects(
    as({ uid: customer }, () => q('select wallet_balance from merchants where id = $1', [shop])),
    denied));

  it('nor the rate a shop agreed', () => assert.rejects(
    as({ uid: customer }, () => q('select revenue_value from merchants where id = $1', [shop])),
    denied));

  it('what a customer screen draws is still there', async () => {
    const row = await as({ uid: customer }, async () => (await q(
      `select name, opening_hours, rating_avg, takes_prepaid_orders
         from merchants where id = $1`, [shop])).rows[0]);
    assert.equal(row.name, 'مطعم');
    assert.equal(row.takes_prepaid_orders, true);
  });

  it('a prepaid shop out of credit says so, and only that', async () => {
    const row = await as('anon', async () => (await q(
      'select takes_prepaid_orders from merchants where id = $1', [broke])).rows[0]);
    assert.equal(row.takes_prepaid_orders, false);
  });

  it('the owner reads their own figures', async () => {
    const rows = await as(OWNER(), async () => (await money([shop, broke])).rows);
    assert.equal(rows.length, 1, 'their own shop and nobody else\'s');
    assert.equal(rows[0].id, shop);
    assert.equal(rows[0].commission_owed, 47500);
    assert.equal(rows[0].revenue_value, 1000);
  });

  it('a customer is answered with nothing', async () => {
    const rows = await as({ uid: customer }, async () => (await money([shop, broke])).rows);
    assert.equal(rows.length, 0);
  });

  it('staff who run shops read every one', async () => {
    const rows = await as(ADMIN(), async () => (await money([shop, broke])).rows);
    assert.equal(rows.length, 2);
  });

  it('the key inside the app cannot even ask', () => assert.rejects(
    as('anon', () => money([shop])), denied));
});
