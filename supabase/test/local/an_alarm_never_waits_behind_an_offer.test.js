import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * An order alarm never waits behind a marketing campaign.
 *
 * Every notification shares one queue, and the drain took it strictly oldest first, twenty
 * a minute. `send_promotion_push` writes one row per customer in the city — so a campaign
 * at 19:00 queues about fifteen hundred rows, and the merchant's alarm for an order placed
 * at 19:02 sits behind all of them for over an hour. The accept deadline is five minutes.
 * The order escalates to `needsAttention` and the phone in the kitchen never rang.
 *
 * The channel decides who goes first; `created_at` only decides the order within one.
 */
describe('an alarm never waits behind an offer', () => {
  const PERSON = '00000000-0000-0000-0000-00000000e101';

  let db;

  const rows = async (sql, params) => (await db.query(sql, params)).rows;

  /** Queues `count` due rows on `channel`, written `ago` in the past, a second apart. */
  const queue = (channel, count, ago) => rows(
    `insert into push_outbox (uid, title, body, channel, created_at)
     select $1, $2, $2, $2, now() - $3::interval + make_interval(secs => g)
       from generate_series(1, $4) as g
     returning id`, [PERSON, channel, ago, count]);

  const claim = async (n) => rows('select * from claim_push_batch($1)', [n]);

  before(async () => {
    db = await freshDatabase();
    await db.exec(`insert into auth.users (id) values ('${PERSON}');`);
  });

  after(async () => { await db?.close(); });

  beforeEach(async () => {
    await db.exec('delete from push_outbox;');
  });

  it('takes the alarm and the order update in the first batch after a campaign', async () => {
    // The campaign went out an hour ago and is still draining; the order came in a
    // minute ago. Before the fix all twenty slots went to the campaign.
    await queue('marketing', 60, '1 hour');
    const [critical] = await queue('orders_critical', 1, '1 minute');
    const [update] = await queue('orders', 1, '1 minute');

    const batch = await claim(20);
    const ids = batch.map((r) => r.id);

    assert.equal(batch.length, 20);
    assert.ok(ids.includes(critical.id), 'the merchant\'s alarm is in the first batch');
    assert.ok(ids.includes(update.id), 'and so is the customer\'s order update');
    assert.equal(batch.filter((r) => r.channel === 'marketing').length, 18,
      'the campaign still gets every slot nobody operational needed');
  });

  it('claims the alarm before the order update, and both before the offer', async () => {
    // One slot at a time, so the order between channels is visible rather than hidden
    // inside one batch. The offer is the oldest of the three and still goes last.
    await queue('marketing', 1, '1 hour');
    await queue('orders', 1, '10 minutes');
    await queue('orders_critical', 1, '1 minute');

    const order = [];
    for (let i = 0; i < 3; i++) order.push((await claim(1))[0].channel);

    assert.deepEqual(order, ['orders_critical', 'orders', 'marketing']);
  });

  it('still takes the oldest first within one channel', async () => {
    const older = await queue('orders_critical', 3, '30 minutes');
    await queue('orders_critical', 3, '1 minute');

    const batch = await claim(3);

    assert.deepEqual(batch.map((r) => r.id).sort(), older.map((r) => r.id).sort());
  });

  it('drains a campaign at the full batch size when nothing operational is due', async () => {
    // Priority must not become starvation: on a quiet afternoon the offer goes out at the
    // same twenty a minute it always did.
    await queue('marketing', 60, '1 hour');

    const batch = await claim(20);

    assert.equal(batch.length, 20);
    assert.ok(batch.every((r) => r.channel === 'marketing'));
  });

  it('does not let an alarm that is not due yet hold back the campaign', async () => {
    // A failed alarm waiting out its backoff is not operational work for this minute; the
    // priority applies to rows the drain may take, not to rows that merely exist.
    await queue('marketing', 5, '1 hour');
    const [critical] = await queue('orders_critical', 1, '1 minute');
    await db.query(
      `update push_outbox set attempts = 1, next_attempt_at = now() + interval '10 minutes'
        where id = $1`, [critical.id]);

    const batch = await claim(20);

    assert.equal(batch.length, 5);
    assert.ok(batch.every((r) => r.channel === 'marketing'));
  });
});
