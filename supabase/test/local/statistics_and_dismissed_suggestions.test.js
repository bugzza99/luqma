import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * Two fixes from the admin QA review of 2026-09-19 that live in the database.
 *
 *   * «المقترحة»: a landmark suggestion the owner turns down stays turned down, and only an
 *     admin can turn one down.
 *   * «الإحصائيات»: the customers figure counts customers, and every order figure counts
 *     the same orders — none of them the cancelled ones.
 */
describe('statistics count what they say', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000ad';
  const COURIER = '00000000-0000-0000-0000-0000000000c1';
  const CUSTOMER_A = '00000000-0000-0000-0000-0000000000a1';
  const CUSTOMER_B = '00000000-0000-0000-0000-0000000000a2';
  let db, zoneId, shopId;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select ${uid ? `'${uid}'::uuid` : 'null::uuid'} $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const role = async (r, fn) => {
    await db.exec(`set role ${r}`);
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  const order = (status, total) => db.query(
    `insert into orders (
       city_id, customer_uid, customer_name, customer_phone,
       merchant_id, merchant_name, zone_id, address, delivery_by,
       type, items, pricing, revenue, status
     ) values (
       'edku', $1, 'عميل', '01012345678',
       $2, 'مطعم', $3, '{"street":"شارع"}'::jsonb, 'platform',
       'instant', '[]'::jsonb, $4::jsonb, '{"platformShare":0}'::jsonb, $5
     )`,
    [CUSTOMER_A, shopId, zoneId, JSON.stringify({ total }), status]);

  const stats = async () => (await db.query('select admin_statistics() as s')).rows[0].s;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;
      insert into auth.users (id) values ('${COURIER}'), ('${CUSTOMER_A}'), ('${CUSTOMER_B}');
      insert into staff (uid, scope, role) values ('${COURIER}', 'platform', 'courier');
      grant usage on schema auth to anon, authenticated;`);
    zoneId = (await db.query(
      `insert into zones (city_id, name, default_delivery_fee)
       values ('edku', 'الزغبي', 1000) returning id`)).rows[0].id;
    shopId = (await db.query(
      `insert into merchants (city_id, type, name, zone_id, phone, status)
       values ('edku', 'restaurant', 'مطعم', $1, '0100', 'approved') returning id`,
      [zoneId])).rows[0].id;
  });

  after(async () => { await db?.close(); });

  it('customers are the accounts with no staff row — the admin and the courier are not',
    async () => {
      // Four accounts exist: the harness admin, the courier and two customers.
      assert.equal(Number((await stats()).customers), 2);
    });

  it('a cancelled order is in none of the order figures', async () => {
    await order('delivered', 10000);
    await order('delivered', 20000);
    await order('cancelled', 90000);
    const s = await stats();
    assert.equal(Number(s.ordersTotal), 2);
    assert.equal(Number(s.avgOrderValue), 15000);
    const weekly = s.byWeek.reduce((sum, w) => sum + Number(w.count), 0);
    assert.equal(weekly, 2);
  });

  it('«اليوم» carries what the platform itself took, apart from the value of the orders', async () => {
    const today = (await db.query('select admin_today() as t')).rows[0].t;
    assert.ok('platformToday' in today);
    assert.equal(Number(today.platformToday), 0);
  });

  it('a turned-down suggestion is remembered by zone and folded name', async () => {
    await db.query(
      `insert into dismissed_landmark_suggestions (zone_id, folded_name, dismissed_by)
       values ($1, 'صيدليه النور', $2)`, [zoneId, ADMIN]);
    await assert.rejects(
      db.query(
        `insert into dismissed_landmark_suggestions (zone_id, folded_name, dismissed_by)
         values ($1, 'صيدليه النور', $2)`, [zoneId, ADMIN]),
      /duplicate key/);
  });

  it('a customer can neither read nor write the refusals', async () => {
    await as(CUSTOMER_B, {});
    try {
      const read = await role('authenticated', () =>
        db.query('select * from dismissed_landmark_suggestions'));
      assert.equal(read.rows.length, 0);
      await assert.rejects(
        role('authenticated', () => db.query(
          `insert into dismissed_landmark_suggestions (zone_id, folded_name, dismissed_by)
           values ($1, 'بيتي', $2)`, [zoneId, CUSTOMER_B])),
        /row-level security/);
    } finally {
      await as(ADMIN, { admin: true });
    }
  });

  it('an admin cannot sign a refusal in somebody else’s name', async () => {
    await as(ADMIN, { admin: true });
    await assert.rejects(
      role('authenticated', () => db.query(
        `insert into dismissed_landmark_suggestions (zone_id, folded_name, dismissed_by)
         values ($1, 'كافيه الركن', $2)`, [zoneId, COURIER])),
      /row-level security/);
  });
});
