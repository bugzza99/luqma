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

  // ---------------------------------------------------------------- writing a coupon
  //
  // Coupons are money, so since 20261020000000 every write goes through an audited
  // function and `insert, update, delete` were taken from `authenticated` on the table
  // itself. Leaving the table writable would have meant an admin could move a discount
  // without leaving evidence, which is the whole point of that migration.
  //
  // The rules these tests are about did not change — they moved out of `with check` and
  // into the function, which re-states every one of them. So the assertions below are the
  // same assertions, asked at the boundary that now answers them.
  const createCoupon = ({
    code, cityId = 'edku', type = 'percentage', value = 1000, maxDiscount = 3000,
    minOrder = 0, merchantId, firstOrderOnly = false, perUserLimit = 0,
    totalLimit = 0, isActive = true, fundedBy = 'merchant',
  }) => role('authenticated', () => db.query(
    'select * from create_coupon($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,null,null)',
    [code, cityId, type, value, maxDiscount, minOrder, merchantId,
      firstOrderOnly, perUserLimit, totalLimit, isActive, fundedBy]));

  const updateCoupon = (id, {
    code = 'SHOP10', type = 'percentage', value = 1000, maxDiscount = 3000,
    minOrder = 0, firstOrderOnly = false, perUserLimit = 0, totalLimit = 0,
    isActive = true, fundedBy = 'merchant',
  }) => role('authenticated', () => db.query(
    'select update_coupon($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,null,null)',
    [id, code, type, value, maxDiscount, minOrder, firstOrderOnly,
      perUserLimit, totalLimit, isActive, fundedBy]));

  const read = (id, columns = '*') => db.query(
    `select ${columns} from coupons where id = $1`, [id]);

  it('an owner creates, lists, pauses and edits a coupon for their shop', async () => {
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });

    const inserted = (await createCoupon({ code: 'SHOP10', merchantId: shopA })).rows[0];

    assert.equal(inserted.code, 'SHOP10');
    assert.equal(inserted.merchant_id, shopA);
    assert.equal(inserted.used_count, 0);
    // `auth.uid()` is still the caller's inside a definer function — it runs as another
    // *role*, not as another person — so the trigger stamps the owner exactly as before.
    assert.equal(inserted.created_by, OWNER_A);
    assert.equal(inserted.is_active, true);

    const list = (await role('authenticated', () => db.query(
      'select * from coupons where merchant_id = $1', [shopA]
    ))).rows;
    assert.ok(list.some((c) => c.code === 'SHOP10'));

    await role('authenticated', () => db.query(
      'select set_coupon_active($1, false)', [inserted.id]));
    assert.equal((await read(inserted.id, 'is_active')).rows[0].is_active, false);

    await updateCoupon(inserted.id, { value: 1500, isActive: true });
    const edited = (await read(inserted.id, 'is_active, value')).rows[0];
    assert.equal(edited.is_active, true);
    assert.equal(edited.value, 1500);
  });

  it('owner cannot create coupon for another shop', async () => {
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });

    await assert.rejects(
      () => createCoupon({ code: 'OTHER10', merchantId: shopB }),
      /not allowed to create this coupon/i
    );
  });

  // Found in review: the funding restriction lived only in `with check`, which does not
  // guard a read or a delete. A coupon the platform pays for, placed on this shop by an
  // admin, is not the shop's to see or change.
  it('owner cannot read or change a platform-funded coupon on their own shop', async () => {
    const id = (await db.query(`
      insert into coupons (code, city_id, type, value, max_discount, merchant_id, funded_by)
      values ('PLATONA', 'edku', 'percentage', 1000, 3000, $1, 'platform') returning id;
    `, [shopA])).rows[0].id;
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });

    // Reading is still RLS's answer, and it is still nothing.
    const seen = await role('authenticated', () =>
      db.query('select id from coupons where id = $1', [id]));
    assert.equal(seen.rows.length, 0);

    await assert.rejects(
      () => updateCoupon(id, { code: 'PLATONA', fundedBy: 'platform' }),
      /not allowed to update this coupon/i
    );
    await assert.rejects(
      () => role('authenticated', () => db.query(
        'select set_coupon_active($1, false)', [id])),
      /not allowed/i
    );

    assert.equal((await read(id, 'is_active')).rows[0].is_active, true);
  });

  it('owner cannot create coupon with funded_by = platform', async () => {
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });

    await assert.rejects(
      () => createCoupon({ code: 'PLAT10', merchantId: shopA, fundedBy: 'platform' }),
      /not allowed to create this coupon/i
    );
  });

  it('nobody writes the table directly any more, not even an admin', async () => {
    // The reason every test above had to move. A write that skips the function skips the
    // audit row with it, so the grant is gone rather than merely discouraged.
    for (const uid of [OWNER_A, ADMIN]) {
      await as(uid, uid === ADMIN
        ? { admin: true, role: 'admin', scope: 'platform' }
        : { role: 'owner', scope: 'merchant', merchant_id: shopA });
      await assert.rejects(
        () => role('authenticated', () => db.query(`
          insert into coupons (code, city_id, type, value, max_discount, merchant_id, funded_by)
          values ('DIRECT', 'edku', 'percentage', 1000, 3000, $1, 'merchant')
        `, [shopA])),
        /permission denied/i,
        `${uid} should not be able to insert directly`);
    }
  });

  it('cannot set used_count or fake created_by', async () => {
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });

    // Neither is a parameter of the function, which is the strongest form of "you may not
    // set this": there is nowhere to put it.
    const c = (await createCoupon({ code: 'GUARD10', merchantId: shopA })).rows[0];
    assert.equal(c.used_count, 0);
    assert.equal(c.created_by, OWNER_A);

    await updateCoupon(c.id, { code: 'GUARD10', value: 1200 });
    const afterUpdate = (await read(c.id, 'used_count, created_by')).rows[0];
    assert.equal(afterUpdate.used_count, 0);
    assert.equal(afterUpdate.created_by, OWNER_A);
  });

  it('refuses a coupon whose city is not the shop own city', async () => {
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });

    await assert.rejects(
      () => createCoupon({ code: 'WRONGCITY', cityId: 'alex', merchantId: shopA }),
      /coupon city must match merchant city/i
    );

    // The shop and the city of an existing coupon are not parameters of `update_coupon`
    // at all, so there is no call that moves a coupon to another shop or another city.
    const id = (await createCoupon({ code: 'UPDATEGUARD', merchantId: shopA })).rows[0].id;
    await updateCoupon(id, { code: 'UPDATEGUARD', value: 1100 });
    const after = (await read(id, 'merchant_id, city_id')).rows[0];
    assert.equal(after.merchant_id, shopA);
    assert.equal(after.city_id, 'edku');
  });

  it('courier of that shop cannot read or write coupons', async () => {
    // The courier's real claim carries the shop, so the refusal has to come from the role
    // check rather than from a missing merchant id.
    await as(COURIER_A, { role: 'courier', scope: 'merchant', merchant_id: shopA });

    const list = (await role('authenticated', () => db.query('select * from coupons'))).rows;
    assert.equal(list.length, 0);

    await assert.rejects(
      () => createCoupon({ code: 'COUR10', merchantId: shopA }),
      /not allowed to create this coupon/i
    );
  });

  it('customer cannot select any coupon directly', async () => {
    await as(CUSTOMER, {});
    const res = await role('authenticated', () => db.query('select * from coupons'));
    assert.equal(res.rowCount, 0);
  });

  it('admin still does everything (including platform funded and all shops)', async () => {
    await as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });

    const adminCoupon = (await createCoupon({
      code: 'ADMINPLAT', value: 2000, maxDiscount: 5000,
      merchantId: null, fundedBy: 'platform',
    })).rows[0];

    assert.equal(adminCoupon.code, 'ADMINPLAT');
    assert.equal(adminCoupon.funded_by, 'platform');
    // Not 10, which the old test seeded directly: a redemption count is the server's to
    // keep, and the function gives nobody anywhere to put one.
    assert.equal(adminCoupon.used_count, 0);

    const all = (await role('authenticated', () => db.query('select * from coupons'))).rows;
    assert.ok(all.length >= 2);
  });

  it('every write leaves an audit row naming who made it', async () => {
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });
    const before = (await db.query(
      "select count(*)::int n from audit_log where action like 'coupon.%'")).rows[0].n;

    const id = (await createCoupon({ code: 'AUDITED', merchantId: shopA })).rows[0].id;
    await updateCoupon(id, { code: 'AUDITED', value: 1400 });
    await role('authenticated', () => db.query('select set_coupon_active($1, false)', [id]));

    const rows = (await db.query(
      "select action, actor from audit_log where action like 'coupon.%' order by at")).rows;
    assert.equal(rows.length - before, 3);
    for (const row of rows.slice(before)) {
      assert.equal(row.actor, OWNER_A, 'the actor is auth.uid(), never a parameter');
    }
  });

  it('placing an order with a merchant-created coupon applies discount and increments used_count', async () => {
    await as(OWNER_A, { role: 'owner', scope: 'merchant', merchant_id: shopA });
    const coupon = (await createCoupon({
      code: 'SAVE20', value: 2000, maxDiscount: 5000, merchantId: shopA,
    })).rows[0];
    assert.equal(coupon.used_count, 0);

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
    assert.equal(orderRes.pricing.subtotalDiscount, 2000);
    assert.equal(orderRes.pricing.total, 9000);

    assert.equal((await read(coupon.id, 'used_count')).rows[0].used_count, 1);
  });
});
