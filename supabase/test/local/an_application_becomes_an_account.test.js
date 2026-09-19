import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * An application becomes an account.
 *
 * The first real merchant applied on 2026-09-17: nothing asked them for a password, no admin
 * was told, and approving the application stamped `approved` without creating a staff row or
 * a shop — so the merchant left the queue and existed nowhere.
 */
describe('an application becomes an account', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000a1';
  const APPLICANT = '00000000-0000-0000-0000-0000000000b1';
  const COURIER = '00000000-0000-0000-0000-0000000000b2';
  const STRANGER = '00000000-0000-0000-0000-0000000000c1';
  const LATECOMER = '00000000-0000-0000-0000-0000000000c2';

  // The number each account is on. A customer's address is their number folded into the
  // reserved domain, and an application has to be for the number the account holds.
  const PHONES = {
    [APPLICANT]: '01277077556',
    [COURIER]: '01277077557',
    [STRANGER]: '01277077558',
    [LATECOMER]: '01277077559',
  };

  let db, zoneId, existingShop;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select ${uid ? `'${uid}'::uuid` : 'null::uuid'} $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const role = async (r, fn) => {
    await db.exec(`set role ${r}`);
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  // No `returning`: an applicant may insert and may not select, which is the point of the
  // queue. The id is read back with the role reset, the way the admin reads it.
  const apply = async (uid, kind = 'restaurant', name = 'ابو حاتم', phone = '01277077556') => {
    await role('authenticated', () => db.query(`
      insert into staff_applications (kind, name, phone, applicant_uid)
      values ($1, $2, $3, $4);
    `, [kind, name, phone, uid]));
    return db.query('select id from staff_applications where phone = $1 order by created_at desc limit 1',
      [phone]);
  };

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id, email) values
        ('${ADMIN}', 'owner@luqma.app'),
        ('${APPLICANT}', '${PHONES[APPLICANT]}@phone.luqma.app'),
        ('${COURIER}', '${PHONES[COURIER]}@phone.luqma.app'),
        ('${STRANGER}', '${PHONES[STRANGER]}@phone.luqma.app'),
        ('${LATECOMER}', '${PHONES[LATECOMER]}@phone.luqma.app');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;
      insert into staff (uid, scope, role, is_active) values ('${ADMIN}', 'platform', 'admin', true);
    `);

    zoneId = (await db.query(`
      insert into zones (city_id, name, default_delivery_fee)
      values ('edku', 'منشية الأمل', 1000) returning id;
    `)).rows[0].id;

    existingShop = (await db.query(`
      insert into merchants (city_id, type, name, zone_id, phone, status)
      values ('edku', 'restaurant', 'مطعم البحر', $1, '01000000000', 'approved') returning id;
    `, [zoneId])).rows[0].id;
  });

  after(async () => { await db?.close(); });

  it('tells every active admin that somebody applied', async () => {
    await as(APPLICANT);
    const { rows } = await apply(APPLICANT);

    const pushes = await db.query(
      `select uid, title, body from push_outbox where data->>'applicationId' = $1`,
      [rows[0].id],
    );
    const admins = (await db.query(
      `select uid from staff where scope = 'platform' and role = 'admin' and is_active`)).rows;
    assert.equal(pushes.rows.length, admins.length);
    assert.ok(pushes.rows.some((p) => p.uid === ADMIN));
    assert.match(pushes.rows[0].title, /طلب انضمام/);
    assert.match(pushes.rows[0].body, /ابو حاتم/);

    await db.query('delete from staff_applications where id = $1', [rows[0].id]);
  });

  it('an applicant cannot put somebody else down as the account', async () => {
    await as(APPLICANT);
    // Their own number, somebody else's account: the policy is what refuses this, which is
    // why the number matches — otherwise the trigger below would answer first and this would
    // pass for the wrong reason.
    await assert.rejects(
      () => apply(STRANGER, 'restaurant', 'ابو حاتم', PHONES[STRANGER]),
      /row-level security/i,
    );
  });

  it('approving a restaurant makes the shop and the owner account', async () => {
    await as(APPLICANT);
    const { rows } = await apply(APPLICANT);

    await as(ADMIN, { admin: true });
    const approved = await role('authenticated', () => db.query(
      'select * from public.approve_staff_application($1, $2)', [rows[0].id, zoneId]));

    assert.equal(approved.rows[0].status, 'approved');
    assert.equal(approved.rows[0].staff_uid, APPLICANT);

    const shop = (await db.query(
      `select * from merchants where owner_uid = $1`, [APPLICANT])).rows[0];
    assert.ok(shop, 'the shop exists');
    assert.equal(shop.name, 'ابو حاتم');
    assert.equal(shop.status, 'pending');
    assert.equal(shop.city_id, 'edku');
    assert.equal(shop.zone_id, zoneId);
    // The one rate every shop follows (20261010000000), not zero.
    assert.equal(shop.revenue_model, 'commission');
    assert.equal(shop.revenue_value, 500);

    const staff = (await db.query('select * from staff where uid = $1', [APPLICANT])).rows[0];
    assert.equal(staff.role, 'owner');
    assert.equal(staff.merchant_id, shop.id);
    assert.equal(staff.is_active, true);

    const told = await db.query(
      `select title from push_outbox where uid = $1 and data->>'kind' = 'staffApproved'`,
      [APPLICANT],
    );
    assert.equal(told.rows.length, 1);

    // And it cannot be approved a second time.
    await assert.rejects(
      () => role('authenticated', () => db.query(
        'select public.approve_staff_application($1, $2)', [rows[0].id, zoneId])),
      /already been decided/i,
    );
  });

  it('a courier needs a shop to start with, and gets attached to it', async () => {
    await as(COURIER);
    const { rows } = await apply(COURIER, 'courier', 'محمد', '01277077557');

    await as(ADMIN, { admin: true });
    await assert.rejects(
      () => role('authenticated', () => db.query(
        'select public.approve_staff_application($1)', [rows[0].id])),
      /shop to start with/i,
    );

    await role('authenticated', () => db.query(
      'select public.approve_staff_application($1, null, $2)', [rows[0].id, existingShop]));

    const staff = (await db.query('select * from staff where uid = $1', [COURIER])).rows[0];
    assert.equal(staff.role, 'courier');
    assert.equal(staff.merchant_id, existingShop);

    const attached = await db.query(
      'select is_active, attached_by from courier_merchants where courier_uid = $1', [COURIER]);
    assert.equal(attached.rows.length, 1);
    assert.equal(attached.rows[0].is_active, true);
    assert.equal(attached.rows[0].attached_by, ADMIN, 'who put the rider on the shop');
  });

  it('refuses a non-admin, an applicant with no account, and restores server mode', async () => {
    await as(STRANGER);
    const { rows } = await apply(STRANGER, 'restaurant', 'محل تاني', '01277077558');

    await assert.rejects(
      () => role('authenticated', () => db.query(
        'select public.approve_staff_application($1, $2)', [rows[0].id, zoneId])),
      /only an admin/i,
    );

    // An application made before this change carries no account.
    await db.query('update staff_applications set applicant_uid = null where id = $1', [rows[0].id]);
    await as(ADMIN, { admin: true });
    await assert.rejects(
      () => role('authenticated', () => db.query(
        'select public.approve_staff_application($1, $2)', [rows[0].id, zoneId])),
      /no account yet/i,
    );

    await db.query('update staff_applications set applicant_uid = $2 where id = $1',
      [rows[0].id, STRANGER]);

    // The setting is transaction-local, so the check has to be inside one transaction.
    await db.exec('begin');
    try {
      await db.query("select set_config('app.server_mode', 'custom', true)");
      await db.exec('set local role authenticated');
      await db.query('select public.approve_staff_application($1, $2)', [rows[0].id, zoneId]);
      const mode = (await db.query("select current_setting('app.server_mode', true) as m")).rows[0].m;
      assert.equal(mode, 'custom');
    } finally {
      await db.exec('rollback');
    }
  });

  it('an application has to be for the number the account is on', async () => {
    await as(STRANGER);

    // The theft this closes: a real restaurant's name and number against the attacker's own
    // account. The owner telephones the restaurant, agrees, approves — and the shop is the
    // attacker's.
    await assert.rejects(
      () => apply(STRANGER, 'restaurant', 'مطعم البحر', '01000000000'),
      /number your account is on/i,
    );

    assert.equal(
      (await db.query('select count(*)::int as n from staff_applications where phone = $1',
        ['01000000000'])).rows[0].n,
      0,
    );
  });

  it('a row that slipped in on a number the account does not hold cannot be approved', async () => {
    await as(LATECOMER);
    const { rows } = await apply(LATECOMER, 'restaurant', 'محل تالت', PHONES[LATECOMER]);

    // Written before the trigger existed: the rows already in production are the reason
    // approval asks the question a second time.
    await db.query('update staff_applications set phone = $2 where id = $1',
      [rows[0].id, '01000000000']);

    await as(ADMIN, { admin: true });
    await assert.rejects(
      () => role('authenticated', () => db.query(
        'select public.approve_staff_application($1, $2)', [rows[0].id, zoneId])),
      /not on the number applied for/i,
    );

    await db.query('delete from staff_applications where id = $1', [rows[0].id]);
  });

  it('anonymous applications are refused entirely', async () => {
    await as(null);
    await assert.rejects(
      () => role('anon', () => db.query(`
        insert into staff_applications (kind, name, phone) values ('restaurant', 'مجهول', '01000000001');
      `)),
      /permission denied|row-level security/i,
    );
  });

  it('the old review function rejects but no longer approves', async () => {
    await as(COURIER);
    const { rows } = await apply(COURIER, 'courier', 'محمد تاني', PHONES[COURIER]);

    await as(ADMIN, { admin: true });
    // An admin handset carrying the older APK would otherwise stamp `approved` and make
    // nothing, which is the incident itself.
    await assert.rejects(
      () => role('authenticated', () => db.query(
        `select public.review_staff_application($1, 'approved')`, [rows[0].id])),
      /update the admin app/i,
    );

    await role('authenticated', () => db.query(
      `select public.review_staff_application($1, 'rejected', 'اتكلمنا ومش مناسب')`, [rows[0].id]));

    const row = (await db.query('select * from staff_applications where id = $1', [rows[0].id])).rows[0];
    assert.equal(row.status, 'rejected');
    assert.equal(row.staff_uid, null);
  });
});
