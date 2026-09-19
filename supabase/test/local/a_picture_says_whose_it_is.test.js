import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * The moderation queue names whose each picture is: the shop, the dish, who uploaded it.
 * It printed a raw uploader id before (QA review 2026-09-19).
 */
describe('a picture says whose it is', () => {
  const OWNER = '00000000-0000-0000-0000-0000000000e7';
  let db, shopId, itemId;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;
      insert into auth.users (id) values ('${OWNER}');`);
    await db.query(`update users set name = 'أبو حاتم' where id = $1`, [OWNER]);
    const zoneId = (await db.query(
      `insert into zones (city_id, name, default_delivery_fee)
       values ('edku', 'الزغبي', 1000) returning id`)).rows[0].id;
    shopId = (await db.query(
      `insert into merchants (city_id, type, name, zone_id, phone, status)
       values ('edku', 'restaurant', 'مطعم أبو حاتم', $1, '0100', 'approved') returning id`,
      [zoneId])).rows[0].id;
    await db.query(
      `insert into staff (uid, scope, role, merchant_id) values ($1, 'merchant', 'owner', $2)`,
      [OWNER, shopId]);
    const categoryId = (await db.query(
      'select id from menu_categories where merchant_id = $1 order by sort_order limit 1',
      [shopId])).rows[0].id;
    itemId = (await db.query(
      `insert into menu_items (merchant_id, category_id, name, price)
       values ($1, $2, 'فراخ مشوية', 12000) returning id`, [shopId, categoryId])).rows[0].id;
  });

  after(async () => { await db?.close(); });

  const media = async (kind, ownerId) => (await db.query(
    `insert into media (kind, url, owner_id, uploaded_by)
     values ($1, 'https://x/y.jpg', $2, $3) returning id`, [kind, ownerId, OWNER])).rows[0].id;

  it('a dish photo names the dish, its shop and the person who uploaded it', async () => {
    const id = await media('menuItem', itemId);
    const row = (await db.query('select * from admin_media_context($1)', [[id]])).rows[0];
    assert.equal(row.shop, 'مطعم أبو حاتم');
    assert.equal(row.item, 'فراخ مشوية');
    assert.equal(row.uploader, 'أبو حاتم');
  });

  it('a logo names its shop', async () => {
    const id = await media('merchantLogo', shopId);
    const row = (await db.query('select * from admin_media_context($1)', [[id]])).rows[0];
    assert.equal(row.shop, 'مطعم أبو حاتم');
    assert.equal(row.item, null);
  });
});
