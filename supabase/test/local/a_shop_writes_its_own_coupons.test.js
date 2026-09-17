import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A shop writes its own coupons.
 *
 * Covers:
 * - Owner creates, lists, pauses and edits coupons for their shop
 * - Cannot create for another shop
 * - Cannot create funded_by='platform'
 * - Cannot set used_count (forced to 0 on insert, kept on update)
 * - created_by is forced to auth.uid() on insert and kept on update
 * - city_id on insert must match merchant's city_id
 * - cannot change merchant_id or city_id on update
 * - Courier of that shop cannot read or write coupons
 * - Customer cannot select any coupon
 * - Admin still does everything
 * - Placing an order with merchant-created coupon applies discount and increments used_count
 */
describe('a shop writes its own coupons', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000a1';
  const OWNER_A = '00000000-0000-0000-0000-0000000000b1';
  const OWNER_B = '00000000-0000-0000-0000-0000000000b2';
  const COURIER_A = '00000000-0000-0000-0000-0000000000d1';
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';

  let db, shopA, shopB, zoneA, itemId, addressId;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select ${uid ? `'${uid}'::uuid` : 'null::uuid'} $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const role = async (r, fn) => {
    await db.exec(`set role ${r}`);
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values
        ('${ADMIN}'), ('${OWNER_A}'), ('${OWNER_B}'), ('${COURIER_A}'), ('${CUSTOMER}');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('edku', 'إدكو'), ('alex', 'الإسكندرية')
        on conflict (id) do nothing;
      update users set name = 'عميل', phone = '01000000000' where id = '${CUSTOMER}';
    `);

    zoneA = (await db.query(`
      insert into zones (city_id, name, default_delivery_fee)
      values ('edku', 'منطقة أ', 1000) returning id;
    `)).rows[0].id;

    const createShop = async (name, ownerUid) => (await db.query(`
      insert into merchants (
        city_id, type, name, zone_id, phone, status, owner_uid,
        delivers_self, min_order, opening_hours
      ) values (
        'edku', 'restaurant', $1, $2, '01000000000', 'approved', $3,
        true, 0,
        (select jsonb_agg(jsonb_build_object('weekday', d, 'openMinute', 0, 'closeMinute', 1439))
           from generate_series(1, 7) d)
      ) returning id;
    `, [name, zoneA, ownerUid])).rows[0].id;

    shopA = await createShop('مطعم أ', OWNER_A);
    shopB = await createShop('مطعم ب', OWNER_B);

    await db.query(`
      insert into merchant_served_zones (merchant_id, zone_id) values ($1, $2), ($3, $2);
    `, [shopA, zoneA, shopB]);

    await db.exec(`
      insert into staff (uid, scope, role, is_active) values ('${ADMIN}', 'platform', 'admin', true);
      insert into staff (uid, scope, role, merchant_id, is_active) values
        ('${OWNER_A}', 'merchant', 'owner', '${shopA}', true),
        ('${OWNER_B}', 'merchant', 'owner', '${shopB}', true),
        ('${COURIER_A}', 'merchant', 'courier', '${shopA}', true);
    `);

    const catId = (await db.query(`
      insert into menu_categories (merchant_id, name) values ($1, 'وجبات') returning id;
    `, [shopA])).rows[0].id;

    itemId = (await db.query(`
      insert into menu_items (merchant_id, category_id, name, price, options)
      values ($1, $2, 'شاورما', 10000, '[]'::jsonb) returning id;
    `, [shopA, catId])).rows[0].id;

    addressId = (await db.query(`
      insert into addresses (user_id, zone_id, label)
      values ('${CUSTOMER}', $1, 'المنزل') returning id;
    `, [zoneA])).rows[0].id;
  });

  after(async () => {
    await db?.close();
  });

  it('an owner creates, lists, pauses and edits a coupon for their shop', async () => {
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });

    // Create coupon
    const inserted = (await role('authenticated', () => db.query(`
      insert into coupons (
        code, city_id, type, value, max_discount, merchant_id, funded_by
      ) values (
        'SHOP10', 'edku', 'percentage', 1000, 3000, $1, 'merchant'
      ) returning *;
    `, [shopA]))).rows[0];

    assert.equal(inserted.code, 'SHOP10');
    assert.equal(inserted.merchant_id, shopA);
    assert.equal(inserted.used_count, 0);
    assert.equal(inserted.created_by, OWNER_A);
    assert.equal(inserted.is_active, true);

    // List coupons
    const list = (await role('authenticated', () => db.query(
      'select * from coupons where merchant_id = $1', [shopA]
    ))).rows;
    assert.ok(list.some((c) => c.code === 'SHOP10'));

    // Pause coupon (is_active = false)
    await role('authenticated', () => db.query(
      'update coupons set is_active = false where id = $1', [inserted.id]
    ));
    const paused = (await role('authenticated', () => db.query(
      'select is_active from coupons where id = $1', [inserted.id]
    ))).rows[0];
    assert.equal(paused.is_active, false);

    // Edit coupon (e.g. value and reactivate)
    await role('authenticated', () => db.query(
      'update coupons set is_active = true, value = 1500 where id = $1', [inserted.id]
    ));
    const edited = (await role('authenticated', () => db.query(
      'select is_active, value from coupons where id = $1', [inserted.id]
    ))).rows[0];
    assert.equal(edited.is_active, true);
    assert.equal(edited.value, 1500);
  });

  it('owner cannot create coupon for another shop', async () => {
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });

    await assert.rejects(
      () => role('authenticated', () => db.query(`
        insert into coupons (
          code, city_id, type, value, max_discount, merchant_id, funded_by
        ) values (
          'OTHER10', 'edku', 'percentage', 1000, 3000, $1, 'merchant'
        );
      `, [shopB])),
      /row-level security/i
    );
  });

  // Found in review: the funding restriction lived only in `with check`, which does not
  // guard a read or a delete. A coupon the platform pays for, placed on this shop by an
  // admin, is not the shop's to see, change or remove.
  it('owner cannot read, update or delete a platform-funded coupon on their own shop', async () => {
    const id = (await db.query(`
      insert into coupons (code, city_id, type, value, max_discount, merchant_id, funded_by)
      values ('PLATONA', 'edku', 'percentage', 1000, 3000, $1, 'platform') returning id;
    `, [shopA])).rows[0].id;
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });

    const seen = await role('authenticated', () =>
      db.query(`select id from coupons where id = $1`, [id]));
    assert.equal(seen.rows.length, 0);
    const updated = await role('authenticated', () =>
      db.query(`update coupons set is_active = false where id = $1 returning id`, [id]));
    assert.equal(updated.rows.length, 0);
    const deleted = await role('authenticated', () =>
      db.query(`delete from coupons where id = $1 returning id`, [id]));
    assert.equal(deleted.rows.length, 0);

    const still = await db.query(`select is_active from coupons where id = $1`, [id]);
    assert.equal(still.rows.length, 1);
    assert.equal(still.rows[0].is_active, true);
  });

  it('owner cannot create coupon with funded_by = platform', async () => {
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });

    await assert.rejects(
      () => role('authenticated', () => db.query(`
        insert into coupons (
          code, city_id, type, value, max_discount, merchant_id, funded_by
        ) values (
          'PLAT10', 'edku', 'percentage', 1000, 3000, $1, 'platform'
        );
      `, [shopA])),
      /row-level security/i
    );
  });

  it('cannot set used_count or fake created_by on insert or update', async () => {
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });

    // Try setting used_count = 99 and created_by = ADMIN on insert
    const c = (await role('authenticated', () => db.query(`
      insert into coupons (
        code, city_id, type, value, max_discount, merchant_id, funded_by,
        used_count, created_by
      ) values (
        'GUARD10', 'edku', 'percentage', 1000, 3000, $1, 'merchant',
        99, '${ADMIN}'
      ) returning used_count, created_by, id;
    `, [shopA]))).rows[0];

    // Trigger forces used_count = 0 and created_by = auth.uid()
    assert.equal(c.used_count, 0);
    assert.equal(c.created_by, OWNER_A);

    // Try altering used_count and created_by on update
    await role('authenticated', () => db.query(`
      update coupons set used_count = 50, created_by = '${ADMIN}' where id = $1
    `, [c.id]));

    const afterUpdate = (await role('authenticated', () => db.query(
      'select used_count, created_by from coupons where id = $1', [c.id]
    ))).rows[0];
    assert.equal(afterUpdate.used_count, 0);
    assert.equal(afterUpdate.created_by, OWNER_A);
  });

  it('refuses mismatching city_id on insert and changing merchant_id or city_id on update', async () => {
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });

    // Insert with wrong city_id ('alex' instead of shop's 'edku')
    await assert.rejects(
      () => role('authenticated', () => db.query(`
        insert into coupons (
          code, city_id, type, value, max_discount, merchant_id, funded_by
        ) values (
          'WRONGCITY', 'alex', 'percentage', 1000, 3000, $1, 'merchant'
        );
      `, [shopA])),
      /coupon city must match merchant city/i
    );

    // Create valid coupon first
    const couponId = (await role('authenticated', () => db.query(`
      insert into coupons (
        code, city_id, type, value, max_discount, merchant_id, funded_by
      ) values (
        'UPDATEGUARD', 'edku', 'percentage', 1000, 3000, $1, 'merchant'
      ) returning id;
    `, [shopA]))).rows[0].id;

    // Refuse changing merchant_id
    await assert.rejects(
      () => role('authenticated', () => db.query(
        'update coupons set merchant_id = $1 where id = $2', [shopB, couponId]
      )),
      /cannot change merchant on a coupon/i
    );

    // Refuse changing city_id
    await assert.rejects(
      () => role('authenticated', () => db.query(
        "update coupons set city_id = 'alex' where id = $1", [couponId]
      )),
      /cannot change city on a coupon/i
    );
  });

  it('courier of that shop cannot read or write coupons', async () => {
    // The courier's real claim carries the shop, so the refusal has to come from the role
    // check rather than from a missing merchant id.
    await as(COURIER_A, { role: 'courier', scope: 'merchant', merchant_id: shopA });

    const list = (await role('authenticated', () => db.query('select * from coupons'))).rows;
    assert.equal(list.length, 0);

    await assert.rejects(
      () => role('authenticated', () => db.query(`
        insert into coupons (
          code, city_id, type, value, max_discount, merchant_id, funded_by
        ) values (
          'COUR10', 'edku', 'percentage', 1000, 3000, $1, 'merchant'
        );
      `, [shopA])),
      /row-level security/i
    );
  });

  it('customer cannot select any coupon directly', async () => {
    await as(CUSTOMER, {});
    const res = await role('authenticated', () => db.query('select * from coupons'));
    assert.equal(res.rowCount, 0);
  });

  it('admin still does everything (including platform funded and all shops)', async () => {
    await as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });

    // Admin can create platform-funded coupon
    const adminCoupon = (await role('authenticated', () => db.query(`
      insert into coupons (
        code, city_id, type, value, max_discount, merchant_id, funded_by, used_count
      ) values (
        'ADMINPLAT', 'edku', 'percentage', 2000, 5000, null, 'platform', 10
      ) returning *;
    `))).rows[0];

    assert.equal(adminCoupon.code, 'ADMINPLAT');
    assert.equal(adminCoupon.funded_by, 'platform');
    assert.equal(adminCoupon.used_count, 10);

    // Admin can see all coupons
    const all = (await role('authenticated', () => db.query('select * from coupons'))).rows;
    assert.ok(all.length >= 2);
  });

  it('placing an order with a merchant-created coupon applies discount and increments used_count', async () => {
    // Owner creates coupon 'SAVE20'
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });
    const coupon = (await role('authenticated', () => db.query(`
      insert into coupons (
        code, city_id, type, value, max_discount, merchant_id, funded_by
      ) values (
        'SAVE20', 'edku', 'percentage', 2000, 5000, $1, 'merchant'
      ) returning *;
    `, [shopA]))).rows[0];
    assert.equal(coupon.used_count, 0);

    // Customer places an order using SAVE20
    await as(CUSTOMER, {});
    const orderRes = (await role('authenticated', () => db.query(`
      select place_order($1::jsonb) as o
    `, [JSON.stringify({
      merchantId: shopA,
      addressId,
      type: 'instant',
      couponCode: 'SAVE20',
      items: [{ itemId, name: 'شاورما', unitPrice: 10000, quantity: 1 }],
    })]))).rows[0].o;

    assert.equal(orderRes.pricing.subtotal, 10000);
    // 20% of 10000 is 2000 discount
    assert.equal(orderRes.pricing.subtotalDiscount, 2000);
    assert.equal(orderRes.pricing.total, 9000); // 10000 - 2000 + 1000 delivery

    // Verify used_count incremented in coupons table
    const afterOrder = (await db.query(
      'select used_count from coupons where id = $1', [coupon.id]
    )).rows[0];
    assert.equal(afterOrder.used_count, 1);
  });
});
