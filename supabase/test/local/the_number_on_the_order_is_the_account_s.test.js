import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A customer's number comes from their account, not from what the app said about them.
 *
 * `users.phone` is where `place_order` reads the number it freezes onto an order — the
 * number the courier rings from the street — and it is what the admin's customer search
 * matches when somebody telephones having forgotten their password. It was copied
 * straight out of signup metadata with no check, while the account's real identity was
 * the number folded into the synthetic address. Nothing made the two agree.
 */
describe("the number on the order is the account's", () => {
  let db;

  const rows = async (sql, params) => (await db.query(sql, params)).rows;

  /** Signs somebody up the way GoTrue does: an address, and metadata beside it. */
  const signUp = async (email, meta) => (await rows(
    `insert into auth.users (id, email, raw_user_meta_data)
     values (gen_random_uuid(), $1, $2::jsonb) returning id`,
    [email, JSON.stringify(meta)]))[0].id;

  const profile = async (id) => (await rows(
    'select name, phone from users where id = $1', [id]))[0];

  before(async () => { db = await freshDatabase(); });
  after(async () => { await db?.close(); });
  beforeEach(async () => { await db.exec('delete from auth.users;'); });

  it('takes the number from the address, not from the metadata', async () => {
    // The defect, in one assertion. An account held on one number could put a different
    // one on the profile, and every order would carry a number that reaches somebody
    // else: a courier at the right door ringing the wrong person.
    const id = await signUp('01012345678@phone.luqma.app',
      { name: 'أميرة', phone: '01099998888' });

    assert.equal((await profile(id)).phone, '01012345678');
  });

  it('agrees with the address even when the app spells the number differently',
    async () => {
      // An older APK sending Arabic-Indic digits or spaces is not wrong, it is just not
      // the authority — so this is ignored rather than refused.
      const id = await signUp('01012345678@phone.luqma.app',
        { name: 'أميرة', phone: '٠١٠ ١٢٣٤ ٥٦٧٨' });

      assert.equal((await profile(id)).phone, '01012345678');
    });

  it('keeps the name, which really is the person\'s to choose', async () => {
    const id = await signUp('01012345678@phone.luqma.app', { name: '  أميرة  ' });

    assert.equal((await profile(id)).name, 'أميرة', 'trimmed, and kept');
  });

  it('bounds the name rather than storing whatever arrives', async () => {
    // Signup metadata is client-controlled and unbounded. A profile row with a megabyte
    // in it is a cheap way to fill a free-tier database.
    const id = await signUp('01012345678@phone.luqma.app', { name: 'ا'.repeat(5000) });

    assert.equal((await profile(id)).name.length, 80);
  });

  it('leaves a staff account on a real address with its metadata number', async () => {
    // `create-staff-account` makes these, and an email carries no number to derive.
    const id = await signUp('team@luqma.app', { name: 'الفريق', phone: '01055556666' });

    assert.equal((await profile(id)).phone, '01055556666');
  });

  it('stores no number rather than a blank one', async () => {
    // Null and empty are different answers, and a screen that renders an empty string
    // where a phone number goes reads as a bug rather than as "we do not have one".
    const id = await signUp('team@luqma.app', { name: 'الفريق' });

    assert.equal((await profile(id)).phone, null);
  });

  it('still makes exactly one profile row per account', async () => {
    // The rule the rest of the suite leans on: a fixture that also inserts a `users` row
    // collides on the primary key, which is how "no such customer" became unreachable
    // through a real account.
    const id = await signUp('01012345678@phone.luqma.app', { name: 'أميرة' });

    assert.equal(
      (await rows('select count(*)::int n from users where id = $1', [id]))[0].n, 1);
  });
});
