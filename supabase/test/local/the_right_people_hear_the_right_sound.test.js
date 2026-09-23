import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * Who is woken, and how loudly.
 *
 * D5: an order nobody answered alerted platform admins only, while AdminApp's banner told
 * a moderator «أوردر محدش ردّ عليه بيوصلك بتنبيه». Watching that queue is exactly what a
 * moderator is for, and the owner decided (2026-09-23) that they are alerted too.
 *
 * A16: a new join application, and the «حسابك اتفعّل» that answers it, went out on
 * `orders_critical` — the alarm channel, which bypasses Do Not Disturb. Anybody who can
 * sign up could ring every admin's phone at three in the morning, and the same lesson was
 * learned once already from the Saturday commission reminder. Neither is an order waiting
 * on a kitchen; both go on the quiet `orders` channel, which AdminApp and MerchantApp both
 * create.
 */
describe('the right people hear the right sound', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000ad';
  const MODERATOR = '00000000-0000-0000-0000-0000000000a7';
  const APPLICANT = '00000000-0000-0000-0000-0000000000a8';
  const CUSTOMER = '00000000-0000-0000-0000-0000000000a9';
  let db, zoneId, merchantId;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const pushesTo = async (uid) => (await db.query(
    'select data, channel from push_outbox where uid = $1 order by created_at', [uid])).rows;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id, email) values
        ('${MODERATOR}', 'mod@luqma.app'),
        ('${APPLICANT}', '01288880000@phone.luqma.app'),
        ('${CUSTOMER}', '01288880001@phone.luqma.app');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;
      insert into staff (uid, scope, role, is_active)
        values ('${MODERATOR}', 'platform', 'moderator', true);`);
    zoneId = (await db.query(`insert into zones (city_id, name, default_delivery_fee)
      values ('edku', 'المعدية', 1000) returning id`)).rows[0].id;
    merchantId = (await db.query(`insert into merchants
      (city_id, type, name, zone_id, phone, status)
      values ('edku', 'restaurant', 'مطعم', $1, '0100', 'approved') returning id`,
      [zoneId])).rows[0].id;
  });

  after(async () => { await db?.close(); });
  beforeEach(async () => { await db.exec('delete from push_outbox'); });

  it('a moderator is alerted to an order nobody answered, as an admin is', async () => {
    const orderId = (await db.query(`insert into orders (
        city_id, customer_uid, customer_name, customer_phone, merchant_id, merchant_name,
        zone_id, address, delivery_by, type, items, pricing, revenue, status)
      values ('edku', $1, 'عميل', '01288880001', $2, 'مطعم', $3, '{}'::jsonb, 'merchant',
        'instant', '[]'::jsonb, '{"total":0}'::jsonb, '{"value":0}'::jsonb, 'placed')
      returning id`, [CUSTOMER, merchantId, zoneId])).rows[0].id;

    await db.query(`do $$ begin
      perform set_config('app.server_mode','on',true);
      update public.orders set status = 'needsAttention' where id = '${orderId}';
    end $$;`);

    for (const uid of [ADMIN, MODERATOR]) {
      const pushes = await pushesTo(uid);
      assert.equal(pushes.length, 1, `${uid} is told`);
      assert.equal(pushes[0].data.kind, 'needsAttention');
      assert.equal(pushes[0].channel, 'orders_critical', 'this one is the alarm, rightly');
    }
  });

  it('a new application reaches the admins on the quiet channel', async () => {
    await db.query(`insert into staff_applications (kind, name, phone, applicant_uid)
      values ('restaurant', 'مطعم جديد', '01288880000', $1)`, [APPLICANT]);

    const pushes = await pushesTo(ADMIN);
    assert.equal(pushes.length, 1);
    assert.equal(pushes[0].data.kind, 'staffApplication');
    assert.equal(pushes[0].channel, 'orders');
  });

  it('«حسابك اتفعّل» reaches the applicant on the quiet channel too', async () => {
    await db.exec('delete from staff_applications');
    const applicationId = (await db.query(`insert into staff_applications
      (kind, name, phone, applicant_uid)
      values ('restaurant', 'مطعم جديد', '01288880000', $1) returning id`,
      [APPLICANT])).rows[0].id;
    await db.exec('delete from push_outbox');

    await as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
    await db.query('select approve_staff_application($1, $2, null, null)',
      [applicationId, zoneId]);

    const pushes = await pushesTo(APPLICANT);
    assert.equal(pushes.length, 1);
    assert.equal(pushes[0].data.kind, 'staffApproved');
    assert.equal(pushes[0].channel, 'orders');
  });
});
