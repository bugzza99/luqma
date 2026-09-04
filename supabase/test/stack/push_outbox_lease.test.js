import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * The gap between claiming a notification and hearing back from FCM.
 *
 * A claim statement's row lock ends before the Edge Function starts its HTTPS calls.
 * These tests use separate committed sessions because a transaction that rolls back
 * cannot prove what the next cron invocation observes after the first one has left.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
let workerA;
let workerB;
let account;

const insertRow = async () => (await db.query(
  `insert into push_outbox (uid, title, body, created_at)
   values ($1, 'lease', 'lease', '-infinity'::timestamptz)
   returning id`,
  [account],
)).rows[0].id;

before(async () => {
  db = new Client({ connectionString: DB });
  workerA = new Client({ connectionString: DB });
  workerB = new Client({ connectionString: DB });
  await Promise.all([db.connect(), workerA.connect(), workerB.connect()]);
  // Another stack file exercises the same global queue. Serialising their fixtures
  // prevents its drain from becoming a third worker in this concurrency proof.
  await db.query("select pg_advisory_lock(hashtext('luqma push outbox stack tests'))");

  account = (await db.query(
    `insert into auth.users (id, instance_id, aud, role)
     values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000',
             'authenticated', 'authenticated')
     returning id`,
  )).rows[0].id;
});

beforeEach(async () => {
  await db.query('delete from push_outbox where uid = $1', [account]);
});

after(async () => {
  await db.query('delete from push_outbox where uid = $1', [account]);
  await db.query('delete from auth.users where id = $1', [account]);
  await db.query("select pg_advisory_unlock(hashtext('luqma push outbox stack tests'))");
  await Promise.all([db.end(), workerA.end(), workerB.end()]);
});

describe('a push claim lease', () => {
  it('lets only one of two concurrent drains claim the row', async () => {
    const id = await insertRow();

    const claims = await Promise.all([
      workerA.query('select * from claim_push_batch(1)'),
      workerB.query('select * from claim_push_batch(1)'),
    ]);
    const copies = claims.flatMap((result) => result.rows)
      .filter((row) => row.id === id);

    assert.equal(copies.length, 1);
    assert.ok(copies[0].claim_token);
  });

  it('offers a crashed worker\'s row again after the lease expires', async () => {
    const id = await insertRow();
    const first = (await workerA.query('select * from claim_push_batch(1)')).rows[0];

    await db.query(
      `update push_outbox set claimed_at = now() - interval '16 minutes' where id = $1`,
      [id],
    );
    const second = (await workerB.query('select * from claim_push_batch(1)')).rows[0];

    assert.equal(first.id, id);
    assert.equal(second.id, id);
    assert.notEqual(second.claim_token, first.claim_token);
  });

  it('accepts only the worker that owns the current claim', async () => {
    const id = await insertRow();
    const first = (await workerA.query('select * from claim_push_batch(1)')).rows[0];
    await db.query(
      `update push_outbox set claimed_at = now() - interval '16 minutes' where id = $1`,
      [id],
    );
    const second = (await workerB.query('select * from claim_push_batch(1)')).rows[0];

    await workerA.query('select settle_push($1, $2)', [id, first.claim_token]);
    const afterStale = (await db.query(
      'select sent_at, claim_token from push_outbox where id = $1',
      [id],
    )).rows[0];
    assert.equal(afterStale.sent_at, null);
    assert.equal(afterStale.claim_token, second.claim_token);

    await workerB.query('select settle_push($1, $2)', [id, second.claim_token]);
    const afterCurrent = (await db.query(
      'select sent_at, claim_token from push_outbox where id = $1',
      [id],
    )).rows[0];
    assert.ok(afterCurrent.sent_at);
    assert.equal(afterCurrent.claim_token, null);
  });
});
