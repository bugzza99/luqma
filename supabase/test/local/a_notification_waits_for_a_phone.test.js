import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A notification waits for a phone, instead of giving up in five minutes.
 *
 * Found on production rather than in a review: seven rows dead-lettered, all with the same
 * `last_error` — `no tokens` — and every recipient carrying a registered device by the time
 * anybody looked. Five were from one day, four of them «طلب انضمام جديد» to the owner.
 *
 * `send-push` settles a recipient with no device as an error and its comment claims that
 * settles the row. It does not: `settle_push` with an error records the error and releases
 * the claim without ever setting `sent_at`, so the next minute's cron takes it again, five
 * times, and the row dies about five minutes after it was written.
 *
 * The attempts were never the problem. The spacing was.
 */
describe('a notification waits for a phone', () => {
  const PERSON = '00000000-0000-0000-0000-00000000e001';

  let db;

  const rows = async (sql, params) => (await db.query(sql, params)).rows;

  /** Queues one message and returns its id. */
  const queue = async () => (await rows(
    `insert into push_outbox (uid, title, body, data, channel)
     values ($1, 'طلب انضمام جديد', 'مندوب', '{}'::jsonb, 'orders_critical')
     returning id`, [PERSON]))[0].id;

  const claim = async () => rows('select * from claim_push_batch(20)');

  const state = async (id) => (await rows(
    `select attempts, sent_at, last_error, next_attempt_at,
            next_attempt_at <= now() as due
       from push_outbox where id = $1`, [id]))[0];

  /** Pretends the wait has passed, so the schedule can be tested without sleeping. */
  const rewind = (id, amount) => db.query(
    `update push_outbox set next_attempt_at = next_attempt_at - $2::interval,
                            claimed_at = null
      where id = $1`, [id, amount]);

  before(async () => {
    db = await freshDatabase();
    await db.exec(`insert into auth.users (id) values ('${PERSON}');`);
  });

  after(async () => { await db?.close(); });

  beforeEach(async () => {
    await db.exec('delete from push_outbox; delete from device_tokens;');
  });

  describe('the schedule', () => {
    it('grows with each failure', async () => {
      const seen = [];
      for (const attempts of [1, 2, 3, 4, 5]) {
        seen.push((await rows(
          'select extract(epoch from push_retry_delay($1))::int as s', [attempts]))[0].s);
      }

      assert.deepEqual(seen, [120, 600, 3600, 21600, 21600]);
      for (let i = 1; i < seen.length; i++) {
        assert.ok(seen[i] >= seen[i - 1], 'a later attempt never waits less');
      }
    });

    it('covers about seven hours in total', async () => {
      const total = (await rows(`select extract(epoch from
        push_retry_delay(1) + push_retry_delay(2) + push_retry_delay(3) + push_retry_delay(4)
      )::int as s`))[0].s;

      // Long enough for somebody to install the app and register a device that evening;
      // short enough that «أوردرك اتقبل» never lands the following morning.
      assert.ok(total > 6 * 3600 && total < 9 * 3600, `spans ${total / 3600} hours`);
    });
  });

  describe('a recipient with no device yet', () => {
    it('is not burnt through in five minutes', async () => {
      // The production incident, reproduced. Before the fix this row reached attempts=5
      // within five cron runs and was never delivered.
      const id = await queue();

      const batch = await claim();
      assert.equal(batch.length, 1, 'it is claimed');
      assert.deepEqual(batch[0].tokens, [], 'and there is nobody to send to');

      await db.query(`select settle_push($1, $2, 'no tokens')`, [id, batch[0].claim_token]);

      const after = await state(id);
      assert.equal(after.attempts, 1);
      assert.equal(after.sent_at, null);
      assert.equal(after.due, false, 'it is not due again on the next minute');
    });

    it('is invisible to the drain until its wait has passed', async () => {
      const id = await queue();
      const first = await claim();
      await db.query(`select settle_push($1, $2, 'no tokens')`, [id, first[0].claim_token]);

      assert.equal((await claim()).length, 0, 'the next cron run skips it');

      await rewind(id, '3 minutes');
      assert.equal((await claim()).length, 1, 'and takes it once the wait is over');
    });

    it('reaches them once they register a phone', async () => {
      // The point of all of it. The owner installs AdminApp that evening; the join
      // application they were never told about is still waiting to be delivered.
      const id = await queue();
      const first = await claim();
      await db.query(`select settle_push($1, $2, 'no tokens')`, [id, first[0].claim_token]);

      await db.query(
        `insert into device_tokens (token, uid) values ('the-owners-phone', $1)`, [PERSON]);
      await rewind(id, '3 minutes');

      const second = await claim();
      assert.deepEqual(second[0].tokens, ['the-owners-phone']);

      await db.query('select settle_push($1, $2)', [id, second[0].claim_token]);
      const after = await state(id);
      assert.ok(after.sent_at, 'delivered');
      assert.equal(after.last_error, null, 'and the failure is cleared, not left to read');
      assert.equal(after.next_attempt_at, null);
    });

    it('still gives up rather than trying for ever', async () => {
      // Bounded on purpose: a notification is about something that was true when it was
      // written, and «أوردرك اتقبل» arriving on Thursday for Monday's order is worse than
      // silence.
      const id = await queue();

      for (let i = 0; i < 5; i++) {
        const batch = await claim();
        assert.equal(batch.length, 1, `attempt ${i + 1} is allowed`);
        await db.query(`select settle_push($1, $2, 'no tokens')`, [id, batch[0].claim_token]);
        await rewind(id, '7 hours');
      }

      assert.equal((await claim()).length, 0, 'the sixth is not');
      assert.equal((await state(id)).attempts, 5);
    });
  });

  describe('what the change must not break', () => {
    it('a row written before the column existed is still claimable', async () => {
      // `next_attempt_at` is null on every row already in the table, and a claim query
      // that compared it directly would silently stop draining the queue.
      const id = await queue();
      await db.query('update push_outbox set next_attempt_at = null where id = $1', [id]);

      assert.equal((await claim()).length, 1);
    });

    it('a delivery still clears the claim and the error', async () => {
      const id = await queue();
      await db.query(
        `insert into device_tokens (token, uid) values ('a-phone', $1)`, [PERSON]);
      const batch = await claim();

      await db.query('select settle_push($1, $2)', [id, batch[0].claim_token]);

      const after = await state(id);
      assert.ok(after.sent_at);
      assert.equal(after.attempts, 1);
    });

    it('a stale claim is still a silent no-op', async () => {
      // Crash recovery: the ten-minute lease expired, another run took the row, and the
      // first drain finally answered. It must not raise and turn a healthy cron run into
      // a failed one — and it must not settle a row it no longer holds.
      const id = await queue();
      const first = await claim();
      await db.query(
        'update push_outbox set claimed_at = now() - interval $$20 minutes$$ where id = $1',
        [id]);
      const second = await claim();
      assert.notEqual(first[0].claim_token, second[0].claim_token);

      await db.query(`select settle_push($1, $2, 'too late')`, [id, first[0].claim_token]);

      assert.equal((await state(id)).last_error, null, 'the stale answer changed nothing');
    });

    it('still prunes the tokens FCM says it no longer knows', async () => {
      // The thing that decides whether this works in six months. A merchant who has
      // changed phones twice keeps dead tokens for ever without it.
      const id = await queue();
      await db.query(
        `insert into device_tokens (token, uid) values ('gone', $1), ('alive', $1)`,
        [PERSON]);
      const batch = await claim();

      await db.query(`select settle_push($1, $2, null, array['gone'])`,
                     [id, batch[0].claim_token]);

      assert.deepEqual(
        (await rows('select token from device_tokens order by token')).map((r) => r.token),
        ['alive']);
    });
  });
});
