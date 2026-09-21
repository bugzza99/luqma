import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

describe('review safety fixes', () => {
  let db;

  before(async () => { db = await freshDatabase(); });
  after(async () => { await db?.close(); });

  it('keeps rating refresh implementation functions private', async () => {
    const privileges = (await db.query(`select
      has_function_privilege('anon',
        'public.refresh_merchant_rating(uuid)', 'execute') as merchant_anon,
      has_function_privilege('authenticated',
        'public.refresh_merchant_rating(uuid)', 'execute') as merchant_authenticated,
      has_function_privilege('anon',
        'public.refresh_item_rating(uuid)', 'execute') as item_anon,
      has_function_privilege('authenticated',
        'public.refresh_item_rating(uuid)', 'execute') as item_authenticated`)).rows[0];

    assert.deepEqual(privileges, {
      merchant_anon: false,
      merchant_authenticated: false,
      item_anon: false,
      item_authenticated: false,
    });
  });

  it('caps the popular shelf even when the caller asks for an extreme limit', async () => {
    await db.exec(`
      insert into cities (id, name) values ('review-limit', 'مدينة الاختبار');
      with zone as (
        insert into zones (city_id, name, default_delivery_fee)
        values ('review-limit', 'منطقة الاختبار', 1000)
        returning id
      )
      insert into merchants (city_id, type, name, zone_id, phone, status)
      select 'review-limit', 'restaurant', 'مطعم الاختبار', id, '01000000000', 'approved'
      from zone;

      insert into menu_items (merchant_id, category_id, name, price)
      select m.id, c.id, 'طبق ' || n, 1000
      from merchants m
      join lateral (
        select id from menu_categories where merchant_id = m.id order by sort_order limit 1
      ) c on true
      cross join generate_series(1, 51) n
      where m.city_id = 'review-limit';
    `);

    const count = async (call) => Number((await db.query(
      `select count(*) as n from ${call}`)).rows[0].n);

    assert.equal(await count("public.popular_items('review-limit', 999)"), 50);
    assert.equal(await count("public.popular_items('review-limit', null)"), 12);
    assert.equal(await count("public.popular_items('review-limit')"), 12);
  });
});
