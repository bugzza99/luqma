import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A way in that is an application, not an account.
 *
 * `staff` is what every policy in this database reads to decide who you are, so a signup
 * page writing it directly would give that boundary an anonymous writer. This table is what
 * an applicant may reach, and a row in it grants nothing at all.
 *
 * **Since 20261005000000 an application is signed.** It was anonymous, and both halves of
 * that cost something: an anonymous row wakes every admin on the critical channel and can be
 * written as fast as somebody can post it, and an application with no account behind it is
 * the incident itself — approved, and creating nobody. So the applicant makes the ordinary
 * phone account first (which carries nothing), and the row names it.
 *
 * Everything below runs as `anon` or `authenticated` — PGlite's owner is a superuser and
 * FORCE does not constrain one.
 */
describe('applying to join', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000f1';
  const OWNER = '00000000-0000-0000-0000-0000000000f2';
  // An account per number. A customer's address is their number folded into the reserved
  // domain, and an application has to be for the number its account is on.
  const APPLICANTS = {
    '01000000100': '00000000-0000-0000-0000-0000000000f4',
    '01000000888': '00000000-0000-0000-0000-0000000000f3',
    '01000000199': '00000000-0000-0000-0000-0000000000f5',
    '01000000101': '00000000-0000-0000-0000-0000000000f6',
  };
  let db;

  const as = (uid, claims) => db.exec(`
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
      insert into auth.users (id) values ('${ADMIN}'), ('${OWNER}');
      insert into auth.users (id, email) values
        ${Object.entries(APPLICANTS)
          .map(([phone, uid]) => `('${uid}', '${phone}@phone.luqma.app')`)
          .join(', ')};
      grant usage on schema auth to anon, authenticated;
      insert into cities (id,name) values ('edku','إدكو');`);
    const zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee)
       values ('edku','الزغبي',1000) returning id`)).rows[0].id;
    const shop = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ('edku','restaurant','مطعم',$1,'0100','approved') returning id`,
      [zone])).rows[0].id;
    await db.query(
      `insert into staff (uid,scope,role,is_active) values ($1,'platform','admin',true)`,
      [ADMIN]);
    await db.query(
      `insert into staff (uid,scope,role,merchant_id,is_active)
       values ($1,'merchant','owner',$2,true)`, [OWNER, shop]);
  });

  after(async () => { await db?.close(); });

  // No `returning`: an applicant is granted insert and nothing else, so asking for the row
  // back needs a select they do not have. The app does not ask for it either — the applicant
  // has no use for an id they cannot look up.
  const apply = (kind, name, phone, note = null) => db.query(
    `insert into staff_applications (kind,name,phone,note,applicant_uid)
     values ($1,$2,$3,$4,$5)`,
    [kind, name, phone, note, APPLICANTS[phone]]);

  // Applying the way the app does it: signed in as the account the number belongs to.
  const applyAs = async (kind, name, phone, note = null) => {
    await as(APPLICANTS[phone], {});
    return role('authenticated', () => apply(kind, name, phone, note));
  };

  it('lets somebody who has just made an account leave their name and number', async () => {
    const r = await applyAs('courier', 'محمود', '01000000100');
    assert.equal(r.rowCount, 1);
  });

  it('and refuses an anonymous one outright', async () => {
    await as(null, {});
    await assert.rejects(
      () => role('anon', () => db.query(
        `insert into staff_applications (kind,name,phone)
         values ('courier','مجهول','01000000102')`)),
      /permission denied|row-level security/i,
      'an application with no account behind it is the incident this closes');
  });

  // The whole reason this table exists rather than a row in `staff`.
  it('and that row grants nothing', async () => {
    const applicant = APPLICANTS['01000000888'];
    await applyAs('courier', 'Applicant', '01000000888');
    await assert.rejects(() => role('authenticated', () => db.query(
      `insert into staff(uid,scope,role) values ($1,'platform','admin')`, [applicant])),
      { code: '42501' });
    assert.equal((await db.query('select uid from staff where uid=$1',[applicant])).rowCount,0);
  });

  it('cannot read the queue it just wrote to', async () => {
    await as(APPLICANTS['01000000100'], {});
    const r = await role('authenticated', () => db.query('select id from staff_applications'));
    assert.equal(r.rowCount, 0, 'the queue is the admin’s, and a filtered read is an empty one');
  });

  // Somebody tapping twice must not fill the queue with themselves.
  it('refuses a second open application from the same number', async () => {
    await as(APPLICANTS['01000000100'], {});
    await assert.rejects(
      () => role('authenticated', () => db.query(
        `insert into staff_applications (kind,name,phone,applicant_uid)
         values ('courier','محمود','٠١٠٠٠٠٠٠١٠٠',$1)`, [APPLICANTS['01000000100']])),
      /staff_applications_one_open/,
      'the same number in Arabic-Indic digits is the same number');
  });

  it('and refuses an applicant who arrives pre-approved', async () => {
    await as(APPLICANTS['01000000199'], {});
    await assert.rejects(
      () => role('authenticated', () => db.query(
        `insert into staff_applications (kind,name,phone,status,applicant_uid)
         values ('courier','ذكي','01000000199','approved',$1)`, [APPLICANTS['01000000199']])),
      /row-level security|violates|permission denied/i);
  });

  describe('the queue', () => {
    it('is the admin’s', async () => {
      await as(ADMIN, { role: 'admin', scope: 'platform', admin: true });
      const r = await role('authenticated',
        () => db.query('select id from staff_applications'));
      assert.ok(r.rowCount >= 1);
    });

    it('and a shop owner sees none of it', async () => {
      await as(OWNER, { role: 'owner', scope: 'merchant' });
      const r = await role('authenticated',
        () => db.query('select id from staff_applications'));
      assert.equal(r.rowCount, 0, 'other people applying is not a merchant’s business');
    });

    it('records who decided it, from the token and not from a parameter', async () => {
      await as(ADMIN, { role: 'admin', scope: 'platform', admin: true });
      const id = (await db.query(
        `select id from staff_applications where status = 'pending' limit 1`)).rows[0].id;

      // Fields off the composite rather than the whole row: a composite comes back as an
      // opaque string here, and `.status` on a string is quietly `undefined` — which is
      // how an assertion passes against nothing at all.
      // Two statements, not one select with both in its target list: Postgres does not
      // promise the order of a target list, so the sub-select read the row *before* the
      // function had written it and the assertion compared against a null it had asked
      // for itself.
      // Rejection, because approval no longer goes through this function: approval creates
      // the account now, and `review_staff_application` never could.
      const row = await role('authenticated', () => db.query(
        `select (public.review_staff_application($1,'rejected','اتكلمنا')).status as status`,
        [id]));
      assert.equal(row.rows[0].status, 'rejected');

      const saved = await db.query(
        'select reviewed_by from staff_applications where id = $1', [id]);
      assert.equal(saved.rows[0].reviewed_by, ADMIN);
    });

    it('and refuses to decide the same one twice', async () => {
      await as(ADMIN, { role: 'admin', scope: 'platform', admin: true });
      const id = (await db.query(
        `select id from staff_applications where status = 'rejected' limit 1`)).rows[0].id;

      await assert.rejects(
        () => role('authenticated', () => db.query(
          `select public.review_staff_application($1,'rejected') as r`, [id])),
        /already been decided/);
    });

    it('and refuses anybody who is not an admin', async () => {
      await as(null, {});
      const id = (await db.query(
        `insert into staff_applications (kind,name,phone,applicant_uid)
         values ('restaurant','مطعم جديد','01000000101',$1) returning id`,
        [APPLICANTS['01000000101']])).rows[0].id;

      await as(OWNER, { role: 'owner', scope: 'merchant' });
      await assert.rejects(
        () => role('authenticated', () => db.query(
          `select public.review_staff_application($1,'rejected') as r`, [id])),
        /only an admin/);
    });
  });
});
