import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A platform courier can be deleted, by an admin.
 *
 * `delete_my_account` refuses every staff account, and `admin_delete_account` refused
 * every `scope = 'platform'` row — so a courier who delivered for the platform itself
 * had no way out of the product at all. The owner decided (2026-09-23): an admin deletes
 * one exactly as they delete a shop's rider. Platform admins and moderators stay
 * undeletable from here.
 *
 * And a rider carrying an order right now is not deleted from under it: the order would
 * lose its courier in the street, the same reason a customer with an order on its way
 * waits (A9). That holds for a shop's rider too.
 */
describe('a platform courier can be let go', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000a1';
  const MODERATOR = '00000000-0000-0000-0000-0000000000a2';
  const RIDER = '00000000-0000-0000-0000-0000000000d1';
  const BUSY = '00000000-0000-0000-0000-0000000000d2';
  let db, zoneId, merchantId;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);
  const role = async (fn) => {
    await db.exec('set role authenticated');
    try { return await fn(); } finally { await db.exec('reset role'); }
  };
  const remove = (uid) => role(() => db.query('select public.admin_delete_account($1)', [uid]));
  const exists = async (uid) => (await db.query(
    'select count(*)::int n from auth.users where id = $1', [uid])).rows[0].n === 1;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${ADMIN}'), ('${MODERATOR}'), ('${RIDER}'), ('${BUSY}');
      insert into staff (uid, scope, role, is_active) values
        ('${ADMIN}', 'platform', 'admin', true),
        ('${MODERATOR}', 'platform', 'moderator', true),
        ('${RIDER}', 'platform', 'courier', true),
        ('${BUSY}', 'platform', 'courier', true);
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('pc', 'إدكو');`);
    zoneId = (await db.query(`insert into zones (city_id, name) values ('pc', 'منطقة')
      returning id`)).rows[0].id;
    merchantId = (await db.query(`insert into merchants
      (city_id, type, name, zone_id, phone, status)
      values ('pc', 'restaurant', 'مطعم', $1, '0100', 'approved') returning id`,
      [zoneId])).rows[0].id;
    await db.query(`insert into orders (
        city_id, customer_name, customer_phone, courier_uid, merchant_id, merchant_name,
        zone_id, address, delivery_by, type, items, pricing, revenue, status
      ) values ('pc', 'عميل', '0100', $1, $2, 'مطعم', $3, '{}'::jsonb, 'platform',
        'instant', '[]'::jsonb, '{"total":2000}'::jsonb, '{}'::jsonb, 'outForDelivery')`,
      [BUSY, merchantId, zoneId]);
    await as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
  });
  after(async () => { await db?.close(); });

  it('an admin deletes a platform courier', async () => {
    await remove(RIDER);
    assert.equal(await exists(RIDER), false);
  });

  it('not while they are carrying an order', async () => {
    await assert.rejects(remove(BUSY), /carrying an order/);
    assert.equal(await exists(BUSY), true);
  });

  it('a moderator on the platform is still not deletable from here', async () => {
    await assert.rejects(remove(MODERATOR), /cannot delete platform staff/);
  });
});
