import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * A notification leaves within seconds, not within the minute.
 *
 * `luqma-send-push` ran once a minute, so a new order's alarm waited up to sixty seconds
 * in `push_outbox` before FCM heard of it — forty-two seconds for the test order on
 * 2026-09-24 — and the owner reported notifications as very slow. It runs every five
 * seconds now, and calls the Edge Function only when a row is due, so the function's
 * free-tier invocations still count sends rather than ticks.
 *
 * pg_cron keeps a row per run in `cron.job_run_details`; at 17,280 runs a day that table
 * would grow without bound, so a nightly job keeps three days of it.
 */
const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

describe('a notification leaves within seconds', () => {
  let db;
  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();
  });
  after(async () => { await db.end(); });

  const job = async (name) => (await db.query(
    'select schedule, command, active from cron.job where jobname = $1', [name])).rows[0];

  it('the drain runs every five seconds', async () => {
    const drain = await job('luqma-send-push');
    assert.equal(drain.schedule, '5 seconds');
    assert.equal(drain.active, true);
  });

  it('and calls the function only when something is due', async () => {
    const drain = await job('luqma-send-push');
    assert.match(drain.command, /push_outbox/);
    assert.match(drain.command, /sent_at is null/);
  });

  it('the run log is kept to a few days', async () => {
    const prune = await job('luqma-prune-cron-runs');
    assert.ok(prune, 'a job prunes cron.job_run_details');
    assert.match(prune.command, /job_run_details/);
  });
});
