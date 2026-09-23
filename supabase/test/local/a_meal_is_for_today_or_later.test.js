import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * C5, on the server. A kitchen publishes a meal for today or a day to come, never for one
 * already over.
 *
 * A phone left open past midnight published its morning meal dated the day before, and
 * nothing refused it: the kitchen's write policy and the column guard do not look at the
 * date. The meal existed, the cook saw it, and no customer's today-only query ever found
 * it. The app now dates the meal when it is published; this is the same rule where a
 * stale or hand-written request cannot talk its way past it.
 */
describe('a meal is for today or later', () => {
  const COOK = '00000000-0000-0000-0000-0000000000e1';
  let db, kitchen;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  before(async () => {
    db = await freshDatabase();
    await db.exec(`insert into auth.users (id) values ('${COOK}');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('mt', 'إدكو');`);
    const zone = (await db.query(`insert into zones (city_id, name) values ('mt', 'منطقة')
      returning id`)).rows[0].id;
    kitchen = (await db.query(`insert into merchants (city_id, type, name, zone_id, phone, status)
      values ('mt', 'homeKitchen', 'مطبخ', $1, '0100', 'approved') returning id`,
    [zone])).rows[0].id;
    await db.query(`insert into staff (uid, scope, role, merchant_id, is_active)
      values ($1, 'merchant', 'owner', $2, true)`, [COOK, kitchen]);
  });
  after(async () => { await db?.close(); });

  const publish = (dayOffset) => db.query(`insert into daily_meals
      (merchant_id, city_id, name, price, date, total_qty, remaining_qty,
       pickup_window_start, pickup_window_end, status)
    values ($1, 'mt', 'محشي', 9000,
            (now() at time zone 'Africa/Cairo')::date + $2::int,
            10, 10, 0, 1440, 'published')`, [kitchen, dayOffset]);

  const asCook = async (fn) => {
    await as(COOK, { role: 'owner', scope: 'merchant', merchant_id: kitchen });
    await db.exec('set role authenticated');
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  it('a meal for today is published', async () => {
    await asCook(() => publish(0));
  });

  it('and one for tomorrow', async () => {
    await asCook(() => publish(1));
  });

  it('but not one for a day already over', async () => {
    await assert.rejects(asCook(() => publish(-1)), /today or later/);
  });
});
