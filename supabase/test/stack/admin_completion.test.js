import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * The admin screens' server half, against the real local stack.
 *
 * Three functions move or reveal what no ordinary customer may. The boundary here is
 * the same one production uses — an authenticated token whose claims name an admin —
 * so each test proves both directions: what an admin can do, and that everyone else
 * gets the classified 42501 rather than a shrug.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

async function as(identity, fn) {
  await q('begin');
  try {
    if (identity.anon) {
      await q("select set_config('role', 'anon', true)");
      await q(
        "select set_config('request.jwt.claims', '{\"role\":\"anon\"}', true)",
      );
      return await fn();
    }
    const claims = JSON.stringify({
      sub: identity.uid,
      role: 'authenticated',
      app_metadata: identity.claims ?? {},
    });
    await q("select set_config('role', 'authenticated', true)");
    await q("select set_config('request.jwt.claims', $1, true)", [claims]);
    return await fn();
  } finally {
    await q('rollback');
  }
}

const uid = async () => (await q(
  "insert into auth.users (id, instance_id, aud, role) " +
  "values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', " +
  "'authenticated') returning id",
)).rows[0].id;

const ADMIN_CLAIMS = { role: 'admin', scope: 'platform', admin: true };

/// `pg` carries the SQLSTATE on `error.code`, never in the message — so
/// `assert.rejects(..., /42501/)` matches the message and passes only by accident of
/// wording. This asks the field the database actually set.
const refusedAs = (code) => (error) => {
  assert.equal(error.code, code,
    `expected SQLSTATE ${code}, got ${error.code}: ${error.message}`);
  return true;
};

describe('admin completion functions', () => {
  let city, zone, merchant, customerUid, adminUid;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = 'admin-test-city';
    await q("insert into cities (id, name) values ($1, 'مدينة الأدمن') on conflict do nothing",
            [city]);
    zone = (await q(
      'insert into zones (city_id, name) values ($1, $2) returning id',
      [city, 'منطقة'],
    )).rows[0].id;
    merchant = (await q(
      `insert into merchants (city_id, type, name, zone_id, phone, status)
       values ($1, 'restaurant', 'مطعم الأدمن', $2, '0100', 'approved')
       returning id`,
      [city, zone],
    )).rows[0].id;

    customerUid = await uid();
    await q('insert into users (id, name, phone) values ($1, $2, $3) on conflict (id) do nothing',
            [customerUid, 'عميل', '01000000000']);
    adminUid = await uid();
    await q(
      `insert into staff (uid, scope, role) values ($1, 'platform', 'admin')`,
      [adminUid],
    );
  });

  after(async () => {
    // Leaf first, as everywhere: history cannot outlive its subject.
    await q('delete from order_settlements where order_id in (select id from orders where city_id = $1)', [city]);
    await q('delete from orders where city_id = $1', [city]);
    await q('delete from order_issues where merchant_id = $1', [merchant]);
    // `$1::uuid`, not a bare $1: jsonb_build_object takes "any", so Postgres cannot infer
    // the type and refuses to plan the statement at all. It sat before db.end(), so the
    // whole suite failed here and then hung with the client still open.
    await q("delete from audit_log where detail @> jsonb_build_object('uid', $1::uuid)",
            [customerUid]);
    await q('delete from staff where uid = $1', [adminUid]);
    await q('delete from users where id = $1', [customerUid]);
    await q('delete from merchants where city_id = $1', [city]);
    await q('delete from zones where city_id = $1', [city]);
    await q('delete from cities where id = $1', [city]);
    await db.end();
  });

  describe('admin_set_customer_blocked', () => {
    it('refuses anon outright', async () => {
      await assert.rejects(
        as({ anon: true }, () =>
          q('select public.admin_set_customer_blocked($1, true)', [customerUid])),
        refusedAs('42501'),
      );
    });

    it('refuses a signed-in customer who is not an admin', async () => {
      await assert.rejects(
        as({ uid: customerUid }, () =>
          q('select public.admin_set_customer_blocked($1, true)', [customerUid])),
        refusedAs('42501'),
      );
    });

    // Asserted inside the same `as` block, not after it: `as` always rolls back, so a
    // check that runs afterwards is looking at a database where the block never happened.
    // Staying inside the transaction is also what makes the undo below unnecessary.
    it('lets an admin block, and says so in the audit log', async () => {
      await as({ uid: adminUid, claims: ADMIN_CLAIMS }, async () => {
        await q('select public.admin_set_customer_blocked($1, true)', [customerUid]);

        const row = (await q(
          'select is_blocked from users where id = $1', [customerUid])).rows[0];
        assert.equal(row.is_blocked, true);

        const audit = (await q(
          `select action from audit_log
            where actor = $1 and detail ->> 'uid' = $2 and action = 'customer.blocked'`,
          [adminUid, customerUid])).rowCount;
        assert.equal(audit, 1, 'the block has to name who did it');
      });
    });

    // A uuid that was never an account, rather than a fresh auth user: since
    // `ensure_user_profile` fires on every insert into auth.users, a real account always
    // has a users row, and "no such customer" cannot be reached through one. What the
    // function still has to answer for is an id that belongs to nobody at all.
    it('names a customer who never existed as not-found', async () => {
      const nobody = '00000000-0000-0000-0000-0000000000ff';
      await assert.rejects(
        as({ uid: adminUid, claims: ADMIN_CLAIMS }, () =>
          q('select public.admin_set_customer_blocked($1, true)', [nobody])),
        refusedAs('P0002'),
      );
    });
  });

  describe('admin_today', () => {
    it('refuses a non-admin', async () => {
      await assert.rejects(
        as({ uid: customerUid }, () => q('select public.admin_today()')),
        refusedAs('42501'),
      );
    });

    it('answers an admin with all four numbers', async () => {
      const today = await as({ uid: adminUid, claims: ADMIN_CLAIMS }, async () =>
        (await q('select public.admin_today() as t')).rows[0].t);
      for (const key of ['ordersToday', 'moneyToday', 'needsAttention', 'openIssues']) {
        assert.ok(key in today, `missing ${key}`);
      }
    });
  });

  describe('admin_statistics', () => {
    it('refuses a non-admin', async () => {
      await assert.rejects(
        as({ uid: customerUid }, () => q('select public.admin_statistics()')),
        refusedAs('42501'),
      );
    });

    it('counts customers and orders by week and month', async () => {
      const stats = await as({ uid: adminUid, claims: ADMIN_CLAIMS }, async () =>
        (await q('select public.admin_statistics() as s')).rows[0].s);
      assert.ok(stats.customers >= 1);
      assert.equal(stats.byWeek.length, 8);
      assert.equal(stats.byMonth.length, 6);
    });
  });

});
