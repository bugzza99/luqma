import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * The shops' offers, on the customer's home.
 *
 * What a restaurant puts on its «العروض» shelf reaches the second section of every
 * customer's home. The shelf is known by a flag, so a rename does not take it off the home.
 */
describe('offers on the home', () => {
  let db, zoneId;

  // Signed out for real: the harness's own auth stubs answer as an admin, so `set role anon`
  // alone would let a policy that accidentally needs an admin pass as public.
  const signedOut = () => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select null::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '{}'::jsonb $fn$;`);

  // And back to the harness's own admin afterwards, which the fixtures below write as.
  const asHarnessAdmin = () => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '00000000-0000-0000-0000-0000000000ad'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '{"app_metadata":{"admin":true}}'::jsonb $fn$;`);

  const role = async (r, fn) => {
    if (r === 'anon') await signedOut();
    await db.exec(`set role ${r}`);
    try {
      return await fn();
    } finally {
      await db.exec('reset role');
      if (r === 'anon') await asHarnessAdmin();
    }
  };

  const shop = async (name, status = 'approved') => (await db.query(
    `insert into merchants (city_id, type, name, zone_id, phone, status)
     values ('edku', 'restaurant', $1, $2, '01000000000', $3) returning id`,
    [name, zoneId, status])).rows[0].id;

  const shelf = async (merchantId, name) => (await db.query(
    'select id from menu_categories where merchant_id = $1 and name = $2',
    [merchantId, name])).rows[0].id;

  const dish = async (merchantId, categoryId, name, available = true) => db.query(
    `insert into menu_items (merchant_id, category_id, name, price, is_available)
     values ($1, $2, $3, 5000, $4)`, [merchantId, categoryId, name, available]);

  const offers = async () => (await role('anon', () => db.query(
    `select name, merchant_name from public.offer_items('edku')`))).rows;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;`);
    zoneId = (await db.query(
      `insert into zones (city_id, name, default_delivery_fee)
       values ('edku', 'الزغبي', 1000) returning id`)).rows[0].id;
  });

  after(async () => { await db?.close(); });

  it('a new restaurant’s second shelf is its offers shelf', async () => {
    const id = await shop('ابو حاتم');
    const flagged = (await db.query(
      'select name from menu_categories where merchant_id = $1 and is_offers', [id])).rows;
    assert.deepEqual(flagged.map((r) => r.name), ['العروض']);
  });

  it('what is on it reaches the home, and nothing else on the menu does', async () => {
    const id = await shop('شاورما الريس');
    await dish(id, await shelf(id, 'العروض'), 'وجبة توفير');
    await dish(id, await shelf(id, 'الوجبات الأساسية'), 'شاورما فراخ');

    const names = (await offers()).map((r) => r.name);
    assert.ok(names.includes('وجبة توفير'));
    assert.ok(!names.includes('شاورما فراخ'));
  });

  it('a renamed offers shelf stays on the home', async () => {
    const id = await shop('كبدة');
    const offersShelf = await shelf(id, 'العروض');
    await db.query(`update menu_categories set name = 'عروض الأسبوع' where id = $1`, [offersShelf]);
    await dish(id, offersShelf, 'كبدة وسجق');

    assert.ok((await offers()).some((r) => r.name === 'كبدة وسجق'));
  });

  it('a shop that is not approved, or a dish that is off, is not offered', async () => {
    const pending = await shop('تحت المراجعة', 'pending');
    await dish(pending, await shelf(pending, 'العروض'), 'عرض مخفي');
    const live = await shop('فول وطعمية');
    await dish(live, await shelf(live, 'العروض'), 'خلصان', false);

    const names = (await offers()).map((r) => r.name);
    assert.ok(!names.includes('عرض مخفي'));
    assert.ok(!names.includes('خلصان'));
  });

  it('the home has the section second, under the category chips', async () => {
    // The migration adds it to every city that exists when it runs; a fresh database has
    // none then, so this asks the file both seeds read, which a new city is built from.
    const { readFileSync } = await import('node:fs');
    const edku = JSON.parse(readFileSync(new URL('../../../data/edku.json', import.meta.url)));
    const ordered = [...edku.homeSections].sort((a, b) => a.sortOrder - b.sortOrder);
    assert.equal(ordered[0].type, 'categoryChips');
    assert.equal(ordered[1].type, 'offers');
  });

  // Live in production until this migration: every signed-out read of merchants failed on
  // "permission denied for function courier_carries".
  it('somebody who has not signed in can read the shops and the shelves', async () => {
    await shop('للزوار');
    for (const q of [
      'select count(*) from public.merchants',
      `select count(*) from public.popular_items('edku')`,
      `select count(*) from public.offer_items('edku')`,
      'select count(*) from public.menu_items',
      'select count(*) from public.home_sections',
    ]) {
      await role('anon', () => db.query(q));
    }
    const seen = (await role('anon', () => db.query(
      `select name from public.merchants where name = 'للزوار'`))).rows;
    assert.equal(seen.length, 1);

    // And what is not public stays hidden from them.
    await shop('لسه بيتراجع', 'pending');
    const hidden = (await role('anon', () => db.query(
      `select name from public.merchants where name = 'لسه بيتراجع'`))).rows;
    assert.equal(hidden.length, 0);
  });

  it('one busy shop cannot push every other shop off the shelf', async () => {
    const busy = await shop('مطعم كتير العروض');
    const busyShelf = await shelf(busy, 'العروض');
    for (let i = 0; i < 25; i++) await dish(busy, busyShelf, `عرض ${i}`);
    const quiet = await shop('مطعم عرض واحد');
    await dish(quiet, await shelf(quiet, 'العروض'), 'العرض الوحيد');
    // Written first, so the busy shop's twenty-five are all newer.
    await db.query(
      `update menu_items set created_at = now() - interval '1 day' where name = 'العرض الوحيد'`);

    const first = (await role('anon', () => db.query(
      `select name from public.offer_items('edku', 20)`))).rows.map((r) => r.name);
    assert.ok(first.includes('العرض الوحيد'), 'every shop gets its newest offer in first');
  });

  describe('chips change in one step', () => {
    it('an admin replaces the set', async () => {
      const id = await shop('صيدلية الشفاء');
      const [a1, b1] = (await db.query(
        `insert into cuisines (city_id, name) values ('edku', 'صيدليات'), ('edku', 'سوبرماركت')
         returning id`)).rows.map((r) => r.id);
      await db.query('select public.set_merchant_cuisines($1, $2)', [id, [a1, b1]]);
      await db.query('select public.set_merchant_cuisines($1, $2)', [id, [a1]]);
      const now = (await db.query(
        'select cuisine_id from merchant_cuisines where merchant_id = $1', [id])).rows;
      assert.deepEqual(now.map((r) => r.cuisine_id), [a1]);
    });

    it('a set that cannot be written leaves the old one standing', async () => {
      const id = await shop('سوبرماركت الأمانة');
      const kept = (await db.query(
        `insert into cuisines (city_id, name) values ('edku', 'بقالة') returning id`)).rows[0].id;
      await db.query('select public.set_merchant_cuisines($1, $2)', [id, [kept]]);

      await assert.rejects(() => db.query('select public.set_merchant_cuisines($1, $2)',
        [id, [kept, '00000000-0000-0000-0000-00000000dead']]));

      const now = (await db.query(
        'select cuisine_id from merchant_cuisines where merchant_id = $1', [id])).rows;
      assert.deepEqual(now.map((r) => r.cuisine_id), [kept]);
    });

    it('nobody but an admin may call it', async () => {
      const id = await shop('محل');
      await assert.rejects(
        () => role('anon', () => db.query('select public.set_merchant_cuisines($1, $2)', [id, []]))
        , /permission denied|only an admin/i);
    });
  });
});
