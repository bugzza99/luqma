import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * How many opened the app — per day, week, month.
 *
 * Table public.app_opens records device opens once per day.
 * admin_active_users reports active devices and signed-in accounts per app.
 */
describe('how many opened the app', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000a1';
  const USER_1 = '00000000-0000-0000-0000-000000000011';
  const USER_2 = '00000000-0000-0000-0000-000000000012';
  const DEVICE_1 = '00000000-0000-0000-0000-0000000000d1';
  const DEVICE_2 = '00000000-0000-0000-0000-0000000000d2';
  const DEVICE_3 = '00000000-0000-0000-0000-0000000000d3';
  const DEVICE_4 = '00000000-0000-0000-0000-0000000000d4';
  // Used only on the window boundaries, so a window that is a day too wide or too narrow
  // changes a count rather than re-counting ids already inside it.
  const USER_3 = '00000000-0000-0000-0000-000000000013';
  const USER_4 = '00000000-0000-0000-0000-000000000014';
  const DEVICE_6 = '00000000-0000-0000-0000-0000000000d6';
  const DEVICE_7 = '00000000-0000-0000-0000-0000000000d7';
  const DEVICE_8 = '00000000-0000-0000-0000-0000000000d8';
  const DEVICE_9 = '00000000-0000-0000-0000-0000000000d9';
  let db;

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
      insert into auth.users (id) values ('${ADMIN}'), ('${USER_1}'), ('${USER_2}'), ('${USER_3}'), ('${USER_4}');
      insert into staff (uid, scope, role, is_active) values ('${ADMIN}', 'platform', 'admin', true);
      grant usage on schema auth to anon, authenticated;
    `);
  });

  after(async () => {
    await db?.close();
  });

  it('records an open once per device per day however many times called', async () => {
    await as(null);
    await role('anon', () => db.query('select public.record_app_open($1, $2)', ['customer', DEVICE_1]));
    await role('anon', () => db.query('select public.record_app_open($1, $2)', ['customer', DEVICE_1]));
    await role('anon', () => db.query('select public.record_app_open($1, $2)', ['customer', DEVICE_1]));

    const rows = (await db.query(
      'select * from public.app_opens where app = $1 and device_id = $2',
      ['customer', DEVICE_1]
    )).rows;

    assert.equal(rows.length, 1);
    assert.equal(rows[0].uid, null);
  });

  it('a later signed-in call fills uid and preserves it on subsequent anonymous call', async () => {
    await as(USER_1, {});
    await role('authenticated', () => db.query('select public.record_app_open($1, $2)', ['customer', DEVICE_1]));

    let rows = (await db.query(
      'select * from public.app_opens where app = $1 and device_id = $2',
      ['customer', DEVICE_1]
    )).rows;
    assert.equal(rows.length, 1);
    assert.equal(rows[0].uid, USER_1);

    // Subsequent anonymous call does not overwrite uid
    await as(null);
    await role('anon', () => db.query('select public.record_app_open($1, $2)', ['customer', DEVICE_1]));

    rows = (await db.query(
      'select * from public.app_opens where app = $1 and device_id = $2',
      ['customer', DEVICE_1]
    )).rows;
    assert.equal(rows.length, 1);
    assert.equal(rows[0].uid, USER_1);
  });

  it('rejects unknown app or null device with an exception', async () => {
    await as(null);
    await assert.rejects(
      () => role('anon', () => db.query('select public.record_app_open($1, $2)', ['bad_app', DEVICE_1])),
      /unknown app/i
    );
    await assert.rejects(
      () => role('anon', () => db.query('select public.record_app_open($1, $2)', ['customer', null])),
      /device_id is required/i
    );
  });

  it('reports counts accurately per window (day, week, month)', async () => {
    // Clear test table to have precise baseline
    await db.exec('delete from public.app_opens');

    // Customer opens:
    // Today: DEVICE_1 (USER_1), DEVICE_2 (null)
    // 3 days ago: DEVICE_1 (USER_1), DEVICE_3 (USER_2)
    // 10 days ago: DEVICE_4 (null)
    // 40 days ago: DEVICE_4 (USER_1) -> outside month
    await db.exec(`
      insert into public.app_opens (day, app, device_id, uid) values
        ((now() at time zone 'Africa/Cairo')::date, 'customer', '${DEVICE_1}', '${USER_1}'),
        ((now() at time zone 'Africa/Cairo')::date, 'customer', '${DEVICE_2}', null),
        (((now() at time zone 'Africa/Cairo')::date - 3), 'customer', '${DEVICE_1}', '${USER_1}'),
        (((now() at time zone 'Africa/Cairo')::date - 3), 'customer', '${DEVICE_3}', '${USER_2}'),
        (((now() at time zone 'Africa/Cairo')::date - 10), 'customer', '${DEVICE_4}', null),
        (((now() at time zone 'Africa/Cairo')::date - 40), 'customer', '${DEVICE_4}', '${USER_1}'),
        (((now() at time zone 'Africa/Cairo')::date - 6), 'customer', '${DEVICE_9}', null),
        (((now() at time zone 'Africa/Cairo')::date - 7), 'customer', '${DEVICE_6}', '${USER_3}'),
        (((now() at time zone 'Africa/Cairo')::date - 29), 'customer', '${DEVICE_8}', null),
        (((now() at time zone 'Africa/Cairo')::date - 30), 'customer', '${DEVICE_7}', '${USER_4}');
    `);

    // Merchant opens:
    // Today: DEVICE_3 (USER_2)
    // 20 days ago: DEVICE_2 (null)
    await db.exec(`
      insert into public.app_opens (day, app, device_id, uid) values
        ((now() at time zone 'Africa/Cairo')::date, 'merchant', '${DEVICE_3}', '${USER_2}'),
        (((now() at time zone 'Africa/Cairo')::date - 20), 'merchant', '${DEVICE_2}', null);
    `);

    await as(ADMIN, { admin: true });
    const res = await role('authenticated', () => db.query('select * from public.admin_active_users()'));
    const rows = res.rows;

    assert.equal(rows.length, 6);

    const map = Object.fromEntries(rows.map((r) => [`${r.app}_${r.period}`, { devices: Number(r.devices), accounts: Number(r.accounts) }]));

    // Customer:
    // Today: DEVICE_1, DEVICE_2 -> 2 devices; USER_1 -> 1 account
    assert.deepEqual(map['customer_day'], { devices: 2, accounts: 1 });
    // Week (today, -3d): DEVICE_1, DEVICE_2, DEVICE_3 -> 3 devices; USER_1, USER_2 -> 2 accounts
    // plus DEVICE_9 on day -6, the last day inside the week; DEVICE_6 on day -7 is outside it
    assert.deepEqual(map['customer_week'], { devices: 4, accounts: 2 });
    // Month (today, -3d, -10d): DEVICE_1, DEVICE_2, DEVICE_3, DEVICE_4 -> 4 devices; USER_1, USER_2 -> 2 accounts
    // plus DEVICE_9, DEVICE_6/USER_3 and DEVICE_8 on day -29; DEVICE_7/USER_4 on day -30 is outside
    assert.deepEqual(map['customer_month'], { devices: 7, accounts: 3 });

    // Merchant:
    // Today: DEVICE_3 -> 1 device, USER_2 -> 1 account
    assert.deepEqual(map['merchant_day'], { devices: 1, accounts: 1 });
    // Week: DEVICE_3 -> 1 device, USER_2 -> 1 account
    assert.deepEqual(map['merchant_week'], { devices: 1, accounts: 1 });
    // Month: DEVICE_3, DEVICE_2 -> 2 devices; USER_2 -> 1 account
    assert.deepEqual(map['merchant_month'], { devices: 2, accounts: 1 });
  });

  it('refuses non-admin calling admin_active_users', async () => {
    await as(USER_1, {});
    await assert.rejects(
      () => role('authenticated', () => db.query('select * from public.admin_active_users()')),
      /insufficient privilege/i
    );
  });

  it('anon cannot select from app_opens table', async () => {
    await as(null);
    await assert.rejects(
      () => role('anon', () => db.query('select * from public.app_opens')),
      /permission denied/i
    );
  });
});
