import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * An installation can take itself off an account without a session.
 *
 * Removing a device token used to need the JWT, which is the wrong shape for the one
 * moment it exists for: if the last deletion fails after GoTrue has signed out, the token
 * stays, and the old account goes on being woken on a phone nobody is signed into. A
 * secret minted per registration is proof of ownership that does not expire with a
 * session.
 */
describe('a device can let go without a session', () => {
  const ALICE = '00000000-0000-0000-0000-00000000f001';
  const BASSEM = '00000000-0000-0000-0000-00000000f002';
  const TOKEN = 'fcm-token-of-one-installation';

  let db;

  const as = (uid) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select ${uid ? `'${uid}'::uuid` : 'null::uuid'} $fn$;`);

  const register = async (uid, token = TOKEN) => {
    await as(uid);
    return (await db.query('select register_device_token($1) as s', [token])).rows[0].s;
  };

  const revoke = async (token, secret) =>
    (await db.query('select revoke_device_token($1, $2) as ok', [token, secret])).rows[0].ok;

  const owner = async (token = TOKEN) =>
    (await db.query('select uid from device_tokens where token = $1', [token])).rows[0]?.uid;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${ALICE}'), ('${BASSEM}');
      grant usage on schema auth to anon, authenticated;`);
  });

  after(async () => { await db?.close(); });

  beforeEach(async () => { await db.exec('delete from device_tokens;'); });

  it('hands a secret back to whoever registered', async () => {
    const secret = await register(ALICE);

    assert.ok(secret, 'registering returns something to revoke with');
    assert.equal(await owner(), ALICE);
  });

  it('lets that secret revoke the token with nobody signed in', async () => {
    // The whole point. This is the state a device is in after sign-out: no session, and
    // a token the server still believes belongs to the account that has gone.
    const secret = await register(ALICE);
    await as(null);

    assert.equal(await revoke(TOKEN, secret), true);
    assert.equal(await owner(), undefined);
  });

  it('refuses a wrong secret, and says so rather than pretending', async () => {
    await register(ALICE);

    const wrong = await revoke(TOKEN, '00000000-0000-0000-0000-000000000009');

    assert.equal(wrong, false, 'a client told false must not report a clean sign-out');
    assert.equal(await owner(), ALICE, 'and nothing was removed');
  });

  it('refuses a null secret without raising', async () => {
    await register(ALICE);

    assert.equal(await revoke(TOKEN, null), false);
    assert.equal(await owner(), ALICE);
  });

  it('rotates the secret when the installation changes hands', async () => {
    // Otherwise the account that handed this phone on could revoke it out from under the
    // account holding it now — a shared till, and a shop that stops ringing for no reason
    // anybody present can explain.
    const alicesSecret = await register(ALICE);
    await register(BASSEM);

    assert.equal(await owner(), BASSEM);
    assert.equal(await revoke(TOKEN, alicesSecret), false);
    assert.equal(await owner(), BASSEM, 'the previous holder cannot take it away');
  });

  it('still moves the installation rather than copying it', async () => {
    // The rule the table was built on, re-checked because the registration path changed:
    // two owners of one token are structurally impossible.
    await register(ALICE);
    await register(BASSEM);

    const rows = (await db.query(
      'select uid from device_tokens where token = $1', [TOKEN])).rows;
    assert.equal(rows.length, 1);
    assert.equal(rows[0].uid, BASSEM);
  });

  it('still refuses to register with nobody signed in', async () => {
    await as(null);

    await assert.rejects(
      () => db.query('select register_device_token($1)', [TOKEN]),
      /authentication required/);
  });

  it('revoking something that was never registered is false, not an error', async () => {
    // A client retrying a deletion it already completed must not be handed an exception
    // to interpret.
    assert.equal(
      await revoke('a-token-nobody-registered', '00000000-0000-0000-0000-000000000001'),
      false);
  });
});
