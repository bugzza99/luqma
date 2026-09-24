import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * The platform can send a notification of its own, and it reaches the city.
 *
 * The owner reported, 2026-09-24, that a campaign push "does not work at all", and that
 * it should not need a shop. Two faults behind that:
 *   - A push reached only customers with a saved address in the city, because an address
 *     is how a customer's city was known. Somebody who installed the app and has not
 *     ordered yet has none — the very person a welcome message is for. On production
 *     that was two customers in three.
 *   - `promotions.merchant_id` was required, so the owner could not announce anything as
 *     Luqma itself.
 * A push may name no shop now, and a whole-city push reaches a customer with no address
 * while there is only one city to belong to. The day a second city opens, that stops —
 * an Edku announcement must not reach a stranger — and a city of its own on the account
 * is what would take its place. Staff accounts are never sent one: their apps have no
 * marketing channel, and an offer would ring the kitchen's alarm.
 */
describe('a platform announcement', () => {
  const WITH_ADDRESS = '00000000-0000-0000-0000-0000000000c1';
  const NO_ADDRESS = '00000000-0000-0000-0000-0000000000c2';
  const OPTED_OUT = '00000000-0000-0000-0000-0000000000c3';
  const OWNER = '00000000-0000-0000-0000-0000000000c4';
  let db, zoneId, otherZone, merchantId;

  const announce = async ({ zones = [], merchant = null, channel = 'push' } = {}) =>
    (await db.query(`insert into promotions
      (city_id, merchant_id, channel, status, title, body, zone_ids, start_at, end_at)
      values ('edku', $1, $2, 'approved', 'أهلًا بيكم في لقمة', 'اطلبوا دلوقتي',
              $3::uuid[], now() - interval '1 minute', now() + interval '1 day')
      returning id`, [merchant, channel, zones])).rows[0].id;

  const recipients = async () => (await db.query(
    `select uid::text, data ->> 'merchantId' as merchant from push_outbox
      where channel = 'marketing' order by uid`)).rows;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values
        ('${WITH_ADDRESS}'), ('${NO_ADDRESS}'), ('${OPTED_OUT}'), ('${OWNER}');
      insert into cities (id, name) values ('edku', 'إدكو');
      insert into config (key, value) values ('marketing_push_per_week', '21'::jsonb)
        on conflict (key) do update set value = excluded.value;
      update users set marketing_push = false where id = '${OPTED_OUT}';`);
    zoneId = (await db.query(`insert into zones (city_id, name) values ('edku', 'وسط')
      returning id`)).rows[0].id;
    otherZone = (await db.query(`insert into zones (city_id, name) values ('edku', 'بحري')
      returning id`)).rows[0].id;
    merchantId = (await db.query(`insert into merchants
      (city_id, type, name, zone_id, phone, status)
      values ('edku', 'restaurant', 'مطعم', $1, '0100', 'approved') returning id`,
      [zoneId])).rows[0].id;
    await db.query(`insert into staff (uid, scope, role, merchant_id, is_active)
      values ($1, 'merchant', 'owner', $2, true)`, [OWNER, merchantId]);
    await db.query(`insert into addresses (user_id, zone_id, label)
      values ($1, $2, 'البيت')`, [WITH_ADDRESS, zoneId]);
  });
  after(async () => { await db?.close(); });

  beforeEach(async () => {
    await db.exec(`delete from push_outbox; delete from promotions;`);
  });

  it('a push can be the platform own, naming no shop', async () => {
    await announce();
    const row = (await db.query('select merchant_id from promotions')).rows[0];
    assert.equal(row.merchant_id, null);
  });

  it('only a push: a banner still belongs to a shop', async () => {
    await assert.rejects(announce({ channel: 'homeBanner' }), /check|violates/);
  });

  it('reaches every customer in the city, address or not — and names no shop', async () => {
    await announce();
    await db.query('select send_promotion_push()');
    assert.deepEqual(await recipients(), [
      { uid: WITH_ADDRESS, merchant: '' },
      { uid: NO_ADDRESS, merchant: '' },
    ]);
  });

  it('never reaches a staff account, nor anybody who turned offers off', async () => {
    await announce({ merchant: merchantId });
    await db.query('select send_promotion_push()');
    const uids = (await recipients()).map((r) => r.uid);
    assert.ok(!uids.includes(OWNER), 'the kitchen phone would ring its alarm');
    assert.ok(!uids.includes(OPTED_OUT));
  });

  it('a push narrowed to zones reaches only the addresses in them', async () => {
    await announce({ zones: [otherZone] });
    await db.query('select send_promotion_push()');
    assert.deepEqual(await recipients(), []);
  });

  it('the day a second city opens, an account with no address is not assumed to be here',
    async () => {
      await db.exec(`insert into cities (id, name) values ('rosetta', 'رشيد');`);
      try {
        await announce();
        await db.query('select send_promotion_push()');
        assert.deepEqual((await recipients()).map((r) => r.uid), [WITH_ADDRESS]);
      } finally {
        await db.exec(`delete from cities where id = 'rosetta';`);
      }
    });
});
