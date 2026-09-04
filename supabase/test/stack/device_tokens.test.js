import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * Device ownership at the real authentication boundary.
 *
 * PGlite cannot say who auth.uid() is. These calls therefore use the same role and JWT
 * settings as PostgREST, so a passing test proves the definer functions derive ownership
 * from the caller and not from a convenient fixture parameter.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

const uid = async () => (await q(
  "insert into auth.users (id, instance_id, aud, role) " +
  "values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', " +
  "'authenticated') returning id",
)).rows[0].id;

/** Commits because B's later request must observe the ownership written by A's request. */
async function as(userId, fn) {
  await q('begin');
  try {
    await q("select set_config('role', 'authenticated', true)");
    await q("select set_config('request.jwt.claims', $1, true)", [JSON.stringify({
      sub: userId,
      role: 'authenticated',
      app_metadata: {},
    })]);
    const result = await fn();
    await q('commit');
    return result;
  } catch (error) {
    await q('rollback');
    throw error;
  }
}

describe('device push tokens', () => {
  let accountA;
  let accountB;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();
    // Both stack files drain one global queue. Serialising their fixtures keeps one
    // proof from consuming the row the other proof was about to inspect.
    await q("select pg_advisory_lock(hashtext('luqma push outbox stack tests'))");
    accountA = await uid();
    accountB = await uid();
  });

  after(async () => {
    await q('delete from push_outbox where uid = any($1::uuid[])', [[accountA, accountB]]);
    await q('delete from device_tokens where uid = any($1::uuid[])', [[accountA, accountB]]);
    await q('delete from auth.users where id = any($1::uuid[])', [[accountA, accountB]]);
    await q("select pg_advisory_unlock(hashtext('luqma push outbox stack tests'))");
    await db.end();
  });

  it('moves an installation, delivers both stores once, and prunes both', async () => {
    const deviceToken = `stack-device-${accountA}`;
    const legacyToken = `stack-legacy-${accountA}`;

    await as(accountA, () => q('select register_device_token($1)', [deviceToken]));
    await as(accountB, () => q('select register_device_token($1)', [deviceToken]));

    const owners = await q(
      'select uid from device_tokens where token = $1',
      [deviceToken],
    );
    assert.equal(owners.rowCount, 1, 'the token key permits only one owner');
    assert.equal(owners.rows[0].uid, accountB);

    // The duplicates model the rollout window: the new app has claimed the token, while
    // older builds left the same value in both profile arrays.
    await q('update users set fcm_tokens = array[$2, $3] where id = $1', [
      accountA,
      legacyToken,
      deviceToken,
    ]);
    await q('update users set fcm_tokens = array[$2] where id = $1', [accountB, deviceToken]);

    const outbox = await q(
      `insert into push_outbox (uid, title, body, created_at)
       values ($1, 'A', 'legacy', '1900-01-01'::timestamptz),
              ($2, 'B', 'device', '1900-01-01 00:00:01'::timestamptz)
       returning id, uid`,
      [accountA, accountB],
    );
    const idFor = (uidValue) => outbox.rows.find((row) => row.uid === uidValue).id;

    // Dating these two rows first keeps this queue claim isolated from other stack files
    // that may be running against the shared test database at the same time.
    const claimed = (await q('select * from claim_push_batch(2)')).rows;
    const forA = claimed.find((row) => row.id === idFor(accountA));
    const forB = claimed.find((row) => row.id === idFor(accountB));

    assert.deepEqual(forA.tokens, [legacyToken]);
    assert.ok(!forA.tokens.includes(deviceToken), 'A lost the installation when B claimed it');
    assert.deepEqual(forB.tokens, [deviceToken], 'the two stores are deduplicated');

    await q('select settle_push($1, $2, null, array[$3])', [
      forB.id,
      forB.claim_token,
      deviceToken,
    ]);
    await q('select settle_push($1, $2)', [forA.id, forA.claim_token]);

    assert.equal((await q(
      'select 1 from device_tokens where token = $1',
      [deviceToken],
    )).rowCount, 0);
    assert.deepEqual((await q(
      'select fcm_tokens from users where id = $1',
      [accountB],
    )).rows[0].fcm_tokens, []);
    assert.deepEqual((await q(
      'select fcm_tokens from users where id = $1',
      [accountA],
    )).rows[0].fcm_tokens, [legacyToken]);
  });

  it('does not let one account forget another account\'s installation', async () => {
    const token = `stack-protected-${accountB}`;
    await as(accountB, () => q('select register_device_token($1)', [token]));

    await as(accountA, () => q('select forget_device_token($1)', [token]));

    const row = (await q('select uid from device_tokens where token = $1', [token])).rows[0];
    assert.equal(row.uid, accountB);
  });
});
