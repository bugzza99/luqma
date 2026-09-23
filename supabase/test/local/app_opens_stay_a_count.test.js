import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A13. The app-open count stays a count, not a free place to put rows.
 *
 * `record_app_open` is callable without an account — it has to be, because a customer
 * browsing before signing up is exactly who the owner wants counted — and it took any
 * device uuid, for ever. A loop of random uuids inflated «المستخدمين النشطين» and grew the
 * table without limit on a 500 MB free-tier database; nothing ever removed a row, though
 * the report reads thirty days at most.
 *
 * Two bounds, neither of which a real phone can reach: a ceiling on new devices per app
 * per day, far above anything Edku will produce (an extra open is ignored, never an error
 * a phone would report), and a nightly prune of anything older than ninety days.
 */
describe('app opens stay a count', () => {
  let db;

  const open = (device) => db.query(
    "select record_app_open('customer', $1::uuid)", [device]);
  const today = async () => (await db.query(
    `select count(*)::int n from app_opens
      where day = (now() at time zone 'Africa/Cairo')::date and app = 'customer'`)).rows[0].n;

  before(async () => { db = await freshDatabase(); });
  after(async () => { await db?.close(); });
  beforeEach(async () => { await db.exec('delete from app_opens'); });

  it('past the ceiling a new device is not recorded, and the call does not fail', async () => {
    await db.exec(`
      insert into app_opens (day, app, device_id)
      select (now() at time zone 'Africa/Cairo')::date, 'customer', gen_random_uuid()
        from generate_series(1, public.app_open_daily_ceiling());`);

    await open('11111111-1111-4111-8111-111111111111');

    assert.equal(await today(), await (async () =>
      (await db.query('select public.app_open_daily_ceiling() n')).rows[0].n)());
  });

  it('a device already counted today is still refreshed past the ceiling', async () => {
    const device = '22222222-2222-4222-8222-222222222222';
    await open(device);
    await db.exec(`
      insert into app_opens (day, app, device_id)
      select (now() at time zone 'Africa/Cairo')::date, 'customer', gen_random_uuid()
        from generate_series(1, public.app_open_daily_ceiling());`);

    await open(device);

    const row = (await db.query(
      'select last_at > first_at as refreshed from app_opens where device_id = $1',
      [device])).rows[0];
    assert.ok(row, 'still there');
  });

  it('the prune removes what the report can no longer show, and keeps the rest', async () => {
    await db.exec(`
      insert into app_opens (day, app, device_id) values
        ((now() at time zone 'Africa/Cairo')::date - 91, 'customer', gen_random_uuid()),
        ((now() at time zone 'Africa/Cairo')::date - 30, 'customer', gen_random_uuid()),
        ((now() at time zone 'Africa/Cairo')::date, 'merchant', gen_random_uuid());`);

    const removed = (await db.query('select public.prune_app_opens() n')).rows[0].n;

    assert.equal(removed, 1);
    const left = (await db.query('select count(*)::int n from app_opens')).rows[0].n;
    assert.equal(left, 2);
  });
});
