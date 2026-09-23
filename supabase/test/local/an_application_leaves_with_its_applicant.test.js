import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * An application leaves with the person who filed it.
 *
 * Somebody who applied to deliver or to open a shop, and then deleted their account
 * before anybody approved them, left the application behind: `applicant_uid` went to null
 * and the name, the telephone number and whatever they wrote about themselves stayed in
 * the admin's queue with nobody attached. Both deletion paths now take an application
 * that never became an account with them.
 */
describe('an application leaves with its applicant', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000a1';
  const SELF = '00000000-0000-0000-0000-0000000000c1';
  const BY_ADMIN = '00000000-0000-0000-0000-0000000000c2';
  const PHONES = { [SELF]: '01277077561', [BY_ADMIN]: '01277077562' };
  let db;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const asRole = async (fn) => {
    await db.exec('set role authenticated');
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  const applications = async (phone) => (await db.query(
    'select count(*)::int n from staff_applications where phone = $1', [phone])).rows[0].n;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id, email) values
        ('${ADMIN}', 'owner@luqma.app'),
        ('${SELF}', '${PHONES[SELF]}@phone.luqma.app'),
        ('${BY_ADMIN}', '${PHONES[BY_ADMIN]}@phone.luqma.app');
      grant usage on schema auth to anon, authenticated;
      insert into staff (uid, scope, role, is_active) values ('${ADMIN}', 'platform', 'admin', true);`);
    for (const uid of [SELF, BY_ADMIN]) {
      await db.query(`insert into staff_applications (kind, name, phone, note, applicant_uid)
        values ('courier', 'مندوب', $1, 'عندي موتوسيكل', $2)`, [PHONES[uid], uid]);
    }
  });
  after(async () => { await db?.close(); });

  it('deleting your own account takes your application with it', async () => {
    assert.equal(await applications(PHONES[SELF]), 1);
    await as(SELF);
    await asRole(() => db.query('select public.delete_my_account()'));
    assert.equal(await applications(PHONES[SELF]), 0);
  });

  it('so does an admin deleting it', async () => {
    assert.equal(await applications(PHONES[BY_ADMIN]), 1);
    await as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
    await asRole(() => db.query('select public.admin_delete_account($1)', [BY_ADMIN]));
    assert.equal(await applications(PHONES[BY_ADMIN]), 0);
  });
});
