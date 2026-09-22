import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * The merchants list asks once instead of once per shop.
 *
 * Each card watched an exact `count` against `orders` filtered to its own merchant, so
 * opening AdminApp's merchants screen cost one HTTPS round trip per shop. Invisible with
 * two, and it is the screen the owner lives on during the launch.
 */
describe('the list asks once', () => {
  const ADMIN = '00000000-0000-0000-0000-00000000c001';
  const MOD = '00000000-0000-0000-0000-00000000c002';
  const NOBODY = '00000000-0000-0000-0000-00000000c003';

  let db, busy, quiet;

  const as = (uid, claims) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const admin = () => as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
  const rows = async (sql, params) => (await db.query(sql, params)).rows;

  const counts = async (city = 'edku') => Object.fromEntries(
    (await rows('select * from admin_merchant_order_counts($1)', [city]))
      .map((r) => [r.merchant_id, r.orders]));

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${ADMIN}'), ('${MOD}'), ('${NOBODY}');
      insert into staff (uid, scope, role, is_active) values
        ('${ADMIN}', 'platform', 'admin', true),
        ('${MOD}', 'platform', 'moderator', true);
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;
      insert into cities (id, name) values ('other', 'مدينة تانية') on conflict (id) do nothing;`);

    const zone = (await rows(
      `insert into zones (city_id, name, default_delivery_fee)
       values ('edku', 'الزغبي', 2000) returning id`))[0].id;
    const shop = async (city, name) => (await rows(
      `insert into merchants (city_id, type, name, zone_id, phone, status)
       values ($1, 'restaurant', $2, $3, '0100', 'approved') returning id`,
      [city, name, zone]))[0].id;

    busy = await shop('edku', 'مطعم الشاطئ');
    quiet = await shop('edku', 'كشري المحطة');
    const elsewhere = await shop('other', 'مطعم بعيد');

    // `place_order` is a different question; these rows exist only to be counted.
    await db.exec(`do $$ begin perform set_config('app.server_mode','on',true); end $$;`);
    for (const [id, n] of [[busy, 3], [elsewhere, 5]]) {
      for (let i = 0; i < n; i++) {
        await db.query(
          `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                               merchant_id, merchant_name, zone_id, type, items, pricing,
                               status)
           values ((select city_id from merchants where id = $1), null, 'عميل',
                   '01000000000', $1, (select name from merchants where id = $1), $2,
                   'instant', '[]'::jsonb,
                   jsonb_build_object('subtotal', 1000, 'total', 2000), 'delivered')`,
          [id, zone]);
      }
    }
  });

  after(async () => { await db?.close(); });

  it('answers for every shop in the city in one statement', async () => {
    await admin();

    const all = await counts();

    assert.equal(Object.keys(all).length, 2, 'both Edku shops, and only Edku');
    assert.equal(all[busy], 3);
  });

  it('gives a shop with no orders a zero rather than leaving it out', async () => {
    // A screen that reads an absence as "not in this answer" draws nothing; one that
    // reads it as zero draws the truth. The server says zero so no caller has to guess.
    await admin();

    assert.equal((await counts())[quiet], 0);
  });

  it('does not count another city\'s orders', async () => {
    await admin();

    const all = await counts('other');
    assert.equal(Object.values(all).reduce((a, b) => a + b, 0), 5);
  });

  it('lets a moderator read it, because a count is a label', async () => {
    await as(MOD, { admin: true, role: 'moderator', scope: 'platform' });

    assert.equal((await counts())[busy], 3);
  });

  it('refuses anybody else, rather than answering with nothing', async () => {
    // The rule this repository keeps relearning: a query that comes back empty reads as
    // «there are no shops», which is a sentence the product says for real. Putting
    // `is_admin()` in the WHERE of a definer function would have done exactly that.
    await as(NOBODY, {});

    await assert.rejects(
      () => db.query('select * from admin_merchant_order_counts($1)', ['edku']),
      (error) => {
        assert.equal(error.code, '42501');
        assert.match(error.message, /only an admin/);
        return true;
      });
  });
});
