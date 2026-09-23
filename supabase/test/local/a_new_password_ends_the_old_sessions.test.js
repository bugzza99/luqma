import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A17. A password an admin sets ends every session the old one opened.
 *
 * `reset-customer-password` changed the password and left every signed-in device inside
 * the account. `end_sessions_of` is what it calls afterwards: the person's sessions go,
 * nobody else's, and only the server may ask.
 */
describe('a new password ends the old sessions', () => {
  const PERSON = '00000000-0000-0000-0000-0000000000a1';
  const OTHER = '00000000-0000-0000-0000-0000000000a2';
  let db;
  const count = async (uid) => (await db.query(
    'select count(*)::int n from auth.sessions where user_id = $1', [uid])).rows[0].n;

  before(async () => {
    db = await freshDatabase();
    await db.query('insert into auth.users (id) values ($1), ($2)', [PERSON, OTHER]);
    await db.query(`insert into auth.sessions (user_id) values ($1), ($1), ($2)`,
      [PERSON, OTHER]);
  });
  after(async () => { await db?.close(); });

  it('a customer cannot call it', async () => {
    await db.exec('set role authenticated');
    try {
      await assert.rejects(db.query('select public.end_sessions_of($1)', [OTHER]),
        /permission denied/);
    } finally {
      await db.exec('reset role');
    }
  });

  it('ends every session of that person and of nobody else', async () => {
    const ended = (await db.query('select public.end_sessions_of($1) as n', [PERSON])).rows[0].n;
    assert.equal(ended, 2);
    assert.equal(await count(PERSON), 0);
    assert.equal(await count(OTHER), 1);
  });
});
