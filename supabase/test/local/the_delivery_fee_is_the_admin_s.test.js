import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A12. What a delivery costs is the admin's to set, not the shop's.
 *
 * `delivery_fee_override` was on the list of columns a shop owner may write. A shop whose
 * orders the platform's riders carry could set it to zero: the rider delivered for
 * nothing, and the platform's cut — a share of that fee — was zero too. CLAUDE.md settled
 * long ago that the zone, the delivery fee and the plan stay the owner's to settle, and
 * the owner confirmed it on 2026-09-23. No screen in MerchantApp ever offered the field.
 */
describe("the delivery fee is the admin's", () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000a1';
  const OWNER = '00000000-0000-0000-0000-0000000000b1';
  let db, shop;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const asRole = async (fn) => {
    await db.exec('set role authenticated');
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  const fee = async () => (await db.query(
    'select delivery_fee_override from merchants where id = $1', [shop])).rows[0]
    .delivery_fee_override;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${ADMIN}'), ('${OWNER}');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;`);
    const zone = (await db.query(`insert into zones (city_id, name, default_delivery_fee)
      values ('edku', 'منطقة', 1000) returning id`)).rows[0].id;
    shop = (await db.query(`insert into merchants
      (city_id, type, name, zone_id, phone, status, owner_uid, delivers_self)
      values ('edku', 'restaurant', 'مطعم', $1, '0100', 'approved', $2, false)
      returning id`, [zone, OWNER])).rows[0].id;
    await db.exec(`
      insert into staff (uid, scope, role, is_active) values ('${ADMIN}', 'platform', 'admin', true);
      insert into staff (uid, scope, role, merchant_id, is_active)
        values ('${OWNER}', 'merchant', 'owner', '${shop}', true);`);
  });

  after(async () => { await db?.close(); });

  it('a shop owner cannot set their own delivery fee', async () => {
    await as(OWNER, { role: 'owner', scope: 'merchant', merchant_id: shop });
    await assert.rejects(
      asRole(() => db.query(
        'update merchants set delivery_fee_override = 0 where id = $1', [shop])),
      /not yours to change/);
    assert.equal(await fee(), null);
  });

  it('the rest of what the shop edits is still theirs', async () => {
    await as(OWNER, { role: 'owner', scope: 'merchant', merchant_id: shop });
    await asRole(() => db.query(
      `update merchants set description = 'أحلى أكل', min_order = 5000 where id = $1`,
      [shop]));
    const row = (await db.query(
      'select description, min_order from merchants where id = $1', [shop])).rows[0];
    assert.equal(row.description, 'أحلى أكل');
    assert.equal(row.min_order, 5000);
  });

  it('an admin still sets it', async () => {
    await as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
    await asRole(() => db.query(
      'update merchants set delivery_fee_override = 1500 where id = $1', [shop]));
    assert.equal(await fee(), 1500);
  });
});
