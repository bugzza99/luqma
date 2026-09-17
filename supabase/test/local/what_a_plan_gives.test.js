import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

describe('what a plan gives a shop', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000a1';
  const OWNER_PREMIUM = '00000000-0000-0000-0000-0000000000b1';
  const OWNER_BASIC = '00000000-0000-0000-0000-0000000000b2';
  const OWNER_NO_PLAN = '00000000-0000-0000-0000-0000000000b3';
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';

  let db;
  let shopPremium;
  let shopBasic;
  let shopExpired;
  let shopPending;
  let shopNoPlan;
  let zoneA;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select ${uid ? `'${uid}'::uuid` : 'null::uuid'} $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;
  `);

  const role = async (r, fn) => {
    await db.exec(`set role ${r}`);
    try {
      return await fn();
    } finally {
      await db.exec('reset role');
    }
  };

  const setMerchantPlan = async (merchantId, planId, expiresAt) => {
    await db.query("select set_config('app.server_mode', 'on', false)");
    await db.query(
      'update merchants set plan_id = $1, plan_expires_at = $2 where id = $3',
      [planId, expiresAt, merchantId],
    );
    await db.query("select set_config('app.server_mode', 'off', false)");
  };

  before(async () => {
    db = await freshDatabase();

    await db.exec(`
      insert into auth.users (id) values
        ('${ADMIN}'), ('${OWNER_PREMIUM}'), ('${OWNER_BASIC}'), ('${OWNER_NO_PLAN}'), ('${CUSTOMER}');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('edku', 'إدكو')
        on conflict (id) do nothing;
      update users set name = 'عميل تجربة', phone = '01000000001' where id = '${CUSTOMER}';
    `);

    zoneA = (await db.query(`
      insert into zones (city_id, name, default_delivery_fee)
      values ('edku', 'المنطقة المركزية', 1000) returning id;
    `)).rows[0].id;

    // Plans
    await db.exec(`
      insert into plans (id, name, price_monthly, features, sort_order, is_active) values
        ('basic', 'باقة أساسية', 25000, '{"maxItems": 100, "analytics": false}'::jsonb, 1, true),
        ('premium', 'باقة مميزة', 60000, '{"maxItems": 500, "analytics": true}'::jsonb, 2, true)
      on conflict (id) do update set features = excluded.features;
    `);

    // The migration's own section C, re-run against these rows: the plans did not exist
    // when the migration was applied, and a copy of its SQL here would pass even if the
    // migration stopped doing it (found in review).
    const migration = readFileSync(
      new URL('../../migrations/20261004000000_what_a_plan_gives.sql', import.meta.url),
      'utf8',
    );
    const startingValues = migration
      .slice(migration.indexOf('C. Starting values'))
      .replace(/^C\. Starting values/, '');
    assert.match(startingValues, /update public\.plans/i);
    await db.exec(startingValues);

    const createShop = async (name, ownerUid, status = 'approved') => (await db.query(`
      insert into merchants (
        city_id, type, name, zone_id, phone, status, owner_uid,
        delivers_self, min_order, revenue_model, revenue_value, wallet_balance, opening_hours
      ) values (
        'edku', 'restaurant', $1, $2, '01011111111', $3, $4,
        true, 0, 'commission', 1000, 0,
        (select jsonb_agg(jsonb_build_object('weekday', d, 'openMinute', 0, 'closeMinute', 1439))
           from generate_series(1, 7) d)
      ) returning id;
    `, [name, zoneA, status, ownerUid])).rows[0].id;

    shopPremium = await createShop('مطعم البركة المميز', OWNER_PREMIUM);
    shopBasic = await createShop('مطعم الأمل الأساسي', OWNER_BASIC);
    shopExpired = await createShop('مطعم منتهي الاشتراك', OWNER_PREMIUM);
    shopPending = await createShop('مطعم قيد المراجعة', OWNER_PREMIUM, 'pending');
    shopNoPlan = await createShop('مطعم بدون باقة', OWNER_NO_PLAN);

    const future = new Date(Date.now() + 30 * 86400000).toISOString();
    const past = new Date(Date.now() - 2 * 86400000).toISOString();

    await setMerchantPlan(shopPremium, 'premium', future);
    await setMerchantPlan(shopBasic, 'basic', future);
    await setMerchantPlan(shopExpired, 'premium', past);
    await setMerchantPlan(shopPending, 'premium', future);

    await db.exec(`
      insert into staff (uid, scope, role, is_active) values
        ('${ADMIN}', 'platform', 'admin', true);
      insert into staff (uid, scope, role, merchant_id, is_active) values
        ('${OWNER_PREMIUM}', 'merchant', 'owner', '${shopPremium}', true),
        ('${OWNER_BASIC}', 'merchant', 'owner', '${shopBasic}', true),
        ('${OWNER_NO_PLAN}', 'merchant', 'owner', '${shopNoPlan}', true);
    `);
  });

  after(async () => {
    await db?.close();
  });

  describe('Starting values (Decision 2 & Part C)', () => {
    it('sets starting values on basic and premium while keeping other features intact', async () => {
      const basicRow = (await db.query("select features from public.plans where id = 'basic'")).rows[0].features;
      assert.equal(basicRow.boostRank, false);
      assert.equal(basicRow.verifiedBadge, false);
      assert.equal(basicRow.homeBannerSlots, 0);
      assert.equal(basicRow.monthlyPromotionCount, 0);
      assert.equal(basicRow.maxItems, 100, 'pre-existing maxItems must survive');
      assert.equal(basicRow.analytics, false, 'pre-existing analytics must survive');

      const premiumRow = (await db.query("select features from public.plans where id = 'premium'")).rows[0].features;
      assert.equal(premiumRow.boostRank, true);
      assert.equal(premiumRow.verifiedBadge, true);
      assert.equal(premiumRow.homeBannerSlots, 1);
      assert.equal(premiumRow.monthlyPromotionCount, 1);
      assert.equal(premiumRow.maxItems, 500, 'pre-existing maxItems must survive');
      assert.equal(premiumRow.analytics, true, 'pre-existing analytics must survive');
    });
  });

  describe('A. merchant_perks()', () => {
    it('returns boosted and verified for an active premium shop, nothing for basic, expired, or pending', async () => {
      await as(null); // anon
      const res = await role('anon', () => db.query('select * from public.merchant_perks()'));

      const rows = res.rows;
      const premiumRow = rows.find((r) => r.merchant_id === shopPremium);
      assert.ok(premiumRow, 'premium shop must have a perks row');
      assert.equal(premiumRow.boost, true);
      assert.equal(premiumRow.verified, true);

      // Leaks check: no plan_id, price_monthly, plan_expires_at columns
      const keys = Object.keys(premiumRow);
      assert.deepEqual(keys.sort(), ['boost', 'merchant_id', 'verified']);

      // Nothing for basic (all off)
      assert.ok(!rows.some((r) => r.merchant_id === shopBasic), 'basic shop has no perks');

      // Nothing after expiry
      assert.ok(!rows.some((r) => r.merchant_id === shopExpired), 'expired shop has no perks');

      // Nothing for non-approved shop
      assert.ok(!rows.some((r) => r.merchant_id === shopPending), 'pending shop has no perks');

      // Nothing for shop with no plan
      assert.ok(!rows.some((r) => r.merchant_id === shopNoPlan), 'no-plan shop has no perks');
    });

    it('works identically for authenticated customer', async () => {
      await as(CUSTOMER);
      const res = await role('authenticated', () => db.query('select * from public.merchant_perks()'));
      const premiumRow = res.rows.find((r) => r.merchant_id === shopPremium);
      assert.ok(premiumRow);
      assert.equal(premiumRow.boost, true);
      assert.equal(premiumRow.verified, true);
    });
  });

  describe('B. Free banners and pushes counted from the plan', () => {
    it('first banner request of a premium shop is included_in_plan, second is not', async () => {
      await as(OWNER_PREMIUM, { merchant_id: shopPremium, role: 'owner' });

      // First banner request (homeBanner)
      const res1 = await role('authenticated', () => db.query(`
        insert into public.promotions (
          city_id, merchant_id, channel, start_at, end_at, requested_by, status, title
        ) values (
          'edku', '${shopPremium}', 'homeBanner', now() + interval '1 day', now() + interval '8 days',
          '${OWNER_PREMIUM}', 'requested', 'بانر ترحيبي 1'
        ) returning *;
      `));
      assert.equal(res1.rows[0].included_in_plan, true, 'first banner should be included_in_plan');

      // Second banner request (categoryBanner - counts together with homeBanner)
      const res2 = await role('authenticated', () => db.query(`
        insert into public.promotions (
          city_id, merchant_id, channel, start_at, end_at, requested_by, status, title
        ) values (
          'edku', '${shopPremium}', 'categoryBanner', now() + interval '1 day', now() + interval '8 days',
          '${OWNER_PREMIUM}', 'requested', 'بانر ترحيبي 2'
        ) returning *;
      `));
      assert.equal(res2.rows[0].included_in_plan, false, 'second banner must exceed quota and not be included');
    });

    it('a rejected included banner frees the slot', async () => {
      await as(ADMIN, { admin: true });

      // Admin rejects the first banner (which was included_in_plan = true)
      const banner1 = (await db.query(`
        select id from public.promotions
         where merchant_id = '${shopPremium}' and title = 'بانر ترحيبي 1'
      `)).rows[0];

      await role('authenticated', () => db.query(`
        update public.promotions
           set status = 'rejected', rejection_reason = 'صورة غير واضحة'
         where id = $1
      `, [banner1.id]));

      // Now owner requests a 3rd banner: should get included_in_plan = true since banner1 is rejected
      await as(OWNER_PREMIUM, { merchant_id: shopPremium, role: 'owner' });
      const res3 = await role('authenticated', () => db.query(`
        insert into public.promotions (
          city_id, merchant_id, channel, start_at, end_at, requested_by, status, title
        ) values (
          'edku', '${shopPremium}', 'homeBanner', now() + interval '1 day', now() + interval '8 days',
          '${OWNER_PREMIUM}', 'requested', 'بانر ترحيبي 3 بديل'
        ) returning *;
      `));
      assert.equal(res3.rows[0].included_in_plan, true, 'banner slot should be freed by rejection');
    });

    it('a push counts separately from banners', async () => {
      await as(OWNER_PREMIUM, { merchant_id: shopPremium, role: 'owner' });

      // Push request: should be included_in_plan = true because push quota is independent
      const resPush = await role('authenticated', () => db.query(`
        insert into public.promotions (
          city_id, merchant_id, channel, start_at, end_at, requested_by, status, title, body
        ) values (
          'edku', '${shopPremium}', 'push', now() + interval '1 day', now() + interval '8 days',
          '${OWNER_PREMIUM}', 'requested', 'إشعار مميز', 'خصم اليوم فقط'
        ) returning *;
      `));
      assert.equal(resPush.rows[0].included_in_plan, true, 'push should have its own separate quota');

      // Second push request: exceeds quota
      const resPush2 = await role('authenticated', () => db.query(`
        insert into public.promotions (
          city_id, merchant_id, channel, start_at, end_at, requested_by, status, title, body
        ) values (
          'edku', '${shopPremium}', 'push', now() + interval '1 day', now() + interval '8 days',
          '${OWNER_PREMIUM}', 'requested', 'إشعار ثاني', 'عرض جديد'
        ) returning *;
      `));
      assert.equal(resPush2.rows[0].included_in_plan, false, 'second push exceeds quota');
    });

    it('a shop with no plan is never included', async () => {
      await as(OWNER_NO_PLAN, { merchant_id: shopNoPlan, role: 'owner' });

      const res = await role('authenticated', () => db.query(`
        insert into public.promotions (
          city_id, merchant_id, channel, start_at, end_at, requested_by, status, title
        ) values (
          'edku', '${shopNoPlan}', 'homeBanner', now() + interval '1 day', now() + interval '8 days',
          '${OWNER_NO_PLAN}', 'requested', 'بانر بدون باقة'
        ) returning *;
      `));
      assert.equal(res.rows[0].included_in_plan, false);
    });

    it('channel boost is never included in plan for merchant insert', async () => {
      await as(OWNER_PREMIUM, { merchant_id: shopPremium, role: 'owner' });

      const res = await role('authenticated', () => db.query(`
        insert into public.promotions (
          city_id, merchant_id, channel, start_at, end_at, requested_by, status, title, included_in_plan
        ) values (
          'edku', '${shopPremium}', 'boost', now() + interval '1 day', now() + interval '8 days',
          '${OWNER_PREMIUM}', 'requested', 'ترقية إضافية', true
        ) returning *;
      `));
      assert.equal(res.rows[0].included_in_plan, false, 'boost channel must never be included_in_plan via request');
    });

    it('a client inserting included_in_plan = true gets false when not entitled', async () => {
      await as(OWNER_NO_PLAN, { merchant_id: shopNoPlan, role: 'owner' });

      const res = await role('authenticated', () => db.query(`
        insert into public.promotions (
          city_id, merchant_id, channel, start_at, end_at, requested_by, status, title, included_in_plan
        ) values (
          'edku', '${shopNoPlan}', 'homeBanner', now() + interval '1 day', now() + interval '8 days',
          '${OWNER_NO_PLAN}', 'requested', 'محاولة تزوير', true
        ) returning *;
      `));
      assert.equal(res.rows[0].included_in_plan, false, 'must force false when not entitled');
    });

    it('owner cannot flip included_in_plan on update, but admin can', async () => {
      // Get the unincluded banner from shopNoPlan
      const promo = (await db.query(`
        select id, included_in_plan from public.promotions
         where merchant_id = '${shopNoPlan}' and title = 'بانر بدون باقة'
      `)).rows[0];
      assert.equal(promo.included_in_plan, false);

      // Owner attempts to update included_in_plan to true
      await as(OWNER_NO_PLAN, { merchant_id: shopNoPlan, role: 'owner' });
      await role('authenticated', () => db.query(`
        update public.promotions
           set included_in_plan = true, status = 'requested'
         where id = $1
      `, [promo.id]));

      const check1 = (await db.query('select included_in_plan from public.promotions where id = $1', [promo.id])).rows[0];
      assert.equal(check1.included_in_plan, false, 'owner update must keep old value');

      // Admin flips it to true
      await as(ADMIN, { admin: true });
      await role('authenticated', () => db.query(`
        update public.promotions
           set included_in_plan = true
         where id = $1
      `, [promo.id]));

      const check2 = (await db.query('select included_in_plan from public.promotions where id = $1', [promo.id])).rows[0];
      assert.equal(check2.included_in_plan, true, 'admin should be able to update included_in_plan');
    });

    it('the owner edit of an unstarted request still works', async () => {
      await as(OWNER_PREMIUM, { merchant_id: shopPremium, role: 'owner' });

      // Get an unstarted promotion
      const promo = (await db.query(`
        select id from public.promotions
         where merchant_id = '${shopPremium}' and title = 'بانر ترحيبي 3 بديل'
      `)).rows[0];

      // Owner updates title
      await role('authenticated', () => db.query(`
        update public.promotions
           set title = 'بانر ترحيبي 3 بعد التعديل', status = 'requested'
         where id = $1
      `, [promo.id]));

      const updated = (await db.query('select title, included_in_plan from public.promotions where id = $1', [promo.id])).rows[0];
      assert.equal(updated.title, 'بانر ترحيبي 3 بعد التعديل');
      assert.equal(updated.included_in_plan, true, 'included_in_plan stays intact');
    });

    it('admin can insert promotion with included_in_plan directly', async () => {
      await as(ADMIN, { admin: true });

      const res = await role('authenticated', () => db.query(`
        insert into public.promotions (
          city_id, merchant_id, channel, start_at, end_at, requested_by, status, title, included_in_plan
        ) values (
          'edku', '${shopNoPlan}', 'homeBanner', now() + interval '1 day', now() + interval '8 days',
          '${ADMIN}', 'approved', 'منحة مجانية من الإدارة', true
        ) returning *;
      `));
      assert.equal(res.rows[0].included_in_plan, true, 'admin insert can set included_in_plan = true');
    });
  });

  describe('C. plan_allowance(merchant_id)', () => {
    it('returns correct numbers for the current Cairo month', async () => {
      await as(OWNER_PREMIUM, { merchant_id: shopPremium, role: 'owner' });

      const res = await role('authenticated', () => db.query(`
        select * from public.plan_allowance('${shopPremium}')
      `));
      const row = res.rows[0];
      assert.equal(row.banners_included, 1);
      // In previous tests: 1 banner rejected, 1 banner included ('بانر ترحيبي 3'), 1 banner not included
      // So used should be 1
      assert.equal(row.banners_used, 1);
      assert.equal(row.pushes_included, 1);
      // 1 push included, 1 push not included
      assert.equal(row.pushes_used, 1);
      assert.equal(row.boost, true);
      assert.equal(row.verified, true);
      assert.equal(row.plan_active, true);
    });

    it('non-owner is refused with 42501', async () => {
      await as(CUSTOMER);
      await assert.rejects(
        () => role('authenticated', () => db.query(`select * from public.plan_allowance('${shopPremium}')`)),
        (err) => err.code === '42501',
      );

      // Owner of another shop is also refused
      await as(OWNER_BASIC, { merchant_id: shopBasic, role: 'owner' });
      await assert.rejects(
        () => role('authenticated', () => db.query(`select * from public.plan_allowance('${shopPremium}')`)),
        (err) => err.code === '42501',
      );
    });

    it('admin is allowed to view plan_allowance for any merchant', async () => {
      await as(ADMIN, { admin: true });
      const res = await role('authenticated', () => db.query(`
        select * from public.plan_allowance('${shopPremium}')
      `));
      assert.equal(res.rows.length, 1);
      assert.equal(res.rows[0].plan_active, true);
    });

    it('month boundary: row created last month does not count against current month allowance or new requests', async () => {
      // Set config app.server_mode to insert a fixture row with past created_at for shopBasic
      await db.query("select set_config('app.server_mode', 'on', false)");
      const lastMonth = new Date(Date.now() - 35 * 86400000).toISOString();
      await db.query(`
        insert into public.promotions (
          city_id, merchant_id, channel, start_at, end_at, requested_by, status, title,
          included_in_plan, created_at
        ) values (
          'edku', '${shopBasic}', 'homeBanner', now() + interval '1 day', now() + interval '8 days',
          '${OWNER_BASIC}', 'approved', 'بانر الشهر الماضي', true, $1
        );
      `, [lastMonth]);
      await db.query("select set_config('app.server_mode', 'off', false)");

      // Basic plan gives 0 banners
      await as(OWNER_BASIC, { merchant_id: shopBasic, role: 'owner' });
      const res = await role('authenticated', () => db.query(`
        select * from public.plan_allowance('${shopBasic}')
      `));
      const row = res.rows[0];
      assert.equal(row.banners_included, 0);
      assert.equal(row.banners_used, 0, 'row created last month must not count toward current month used');
      assert.equal(row.pushes_included, 0);
      assert.equal(row.pushes_used, 0);
      assert.equal(row.boost, false);
      assert.equal(row.verified, false);
      assert.equal(row.plan_active, true);
    });
  });
  // Found in review: the quota was counted from the month in the row's own `created_at`, so a
  // request dated two months back always landed in an empty month — a free placement every time.
  it('a backdated request is stamped by the server and still counts against this month', async () => {
    await as(OWNER_PREMIUM, { role: 'owner', scope: 'merchant', merchant_id: shopPremium });

    // Earlier tests in this file have already used this shop's one banner for the month, so
    // a backdated request is exactly the exploit: an empty month of its own choosing.
    const backdated = await role('authenticated', () => db.query(`
      insert into promotions (city_id, merchant_id, channel, title, body, start_at, end_at, requested_by, created_at)
      values ('edku', $1, 'homeBanner', 'B', '', now() + interval '1 day', now() + interval '2 days', $2,
              now() - interval '2 months')
      returning id, included_in_plan, created_at;
    `, [shopPremium, OWNER_PREMIUM]));
    assert.equal(backdated.rows[0].included_in_plan, false);
    assert.ok(
      new Date(backdated.rows[0].created_at).getTime() > Date.now() - 60_000,
      'the server stamped it, not the client',
    );

    // Nor can an edit move the month it counts against.
    const moved = await role('authenticated', () => db.query(`
      update promotions set created_at = now() - interval '2 months'
       where id = $1 returning created_at;
    `, [backdated.rows[0].id]));
    if (moved.rows.length > 0) {
      assert.ok(new Date(moved.rows[0].created_at).getTime() > Date.now() - 60_000);
    }
  });
  // Found in review: banners and pushes are counted apart, so an included banner edited into
  // a push arrived inside the push quota without ever being counted against it.
  it('an included placement edited into another kind stops being included', async () => {
    const admin = await db.query(`
      insert into promotions (city_id, merchant_id, channel, title, body, start_at, end_at,
                              requested_by, included_in_plan)
      values ('edku', $1, 'homeBanner', 'C', '', now() + interval '1 day',
              now() + interval '2 days', $2, true)
      returning id;
    `, [shopPremium, OWNER_PREMIUM]);

    await as(OWNER_PREMIUM, { role: 'owner', scope: 'merchant', merchant_id: shopPremium });
    const edited = await role('authenticated', () => db.query(`
      update promotions set channel = 'push' where id = $1 returning channel, included_in_plan;
    `, [admin.rows[0].id]));

    assert.equal(edited.rows[0].channel, 'push');
    assert.equal(edited.rows[0].included_in_plan, false);
  });
});
