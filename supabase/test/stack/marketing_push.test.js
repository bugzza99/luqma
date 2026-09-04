import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * The marketing channel, which for two phases had no sender and no way out.
 *
 * An admin could approve a `push` promotion, `push_slot_available` would ration it, and
 * nothing anywhere turned it into a notification. The other half is the one that is not
 * merely a missing feature: a customer who found the advertising intrusive could not
 * stop it, and stopping it must not stop being told where their food is.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

const makeAccount = async () => (await q(
  `insert into auth.users (id, instance_id, aud, role)
   values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000',
           'authenticated', 'authenticated')
   returning id`,
)).rows[0].id;

describe('send_promotion_push', () => {
  let city, near, far, merchant, owner, subscriber, refuser, blocked, elsewhere;
  let priorLimit;

  const promote = async ({ zones = [], startAt = 'now() - interval \'1 minute\'' } = {}) =>
    (await q(
      `insert into promotions
         (city_id, merchant_id, channel, status, title, body, zone_ids,
          start_at, end_at, requested_by)
       values ($1, $2, 'push', 'approved', 'خصم النهارده', 'خصم ٢٠٪ على كل حاجة',
               $3, ${startAt}, (${startAt}) + interval '1 day', $4)
       returning id`,
      [city, merchant, zones, owner],
    )).rows[0].id;

  const queued = async (promotionId) => Number((await q(
    "select count(*) from push_outbox where data ->> 'promotionId' = $1",
    [promotionId],
  )).rows[0].count);

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = `marketing-${Date.now()}`;
    await q('insert into cities (id, name) values ($1, $2)', [city, 'مدينة العروض']);
    near = (await q(
      'insert into zones (city_id, name) values ($1, $2) returning id',
      [city, 'المعمورة'],
    )).rows[0].id;
    far = (await q(
      'insert into zones (city_id, name) values ($1, $2) returning id',
      [city, 'الشاطئ'],
    )).rows[0].id;

    owner = await makeAccount();
    merchant = (await q(
      `insert into merchants
         (city_id, type, name, zone_id, phone, status, revenue_model, revenue_value,
          owner_uid)
       values ($1, 'restaurant', 'مطعم', $2, '01000000000', 'approved',
               'commission', 1000, $3)
       returning id`,
      [city, near, owner],
    )).rows[0].id;

    // Four customers, one of each kind the fan-out has to tell apart.
    subscriber = await makeAccount();
    refuser = await makeAccount();
    blocked = await makeAccount();
    elsewhere = await makeAccount();

    // `marketing_push` needs no declaration — it is the customer's own switch, and the
    // guard letting it through is half of what this suite is here to prove. `is_blocked`
    // is the server's, so blocking somebody has to say so.
    await q('update users set marketing_push = false where id = $1', [refuser]);
    await q('begin');
    await q("select set_config('app.server_mode', 'on', true)");
    await q('update users set is_blocked = true where id = $1', [blocked]);
    await q('commit');

    for (const [uid, zone] of [
      [subscriber, near], [refuser, near], [blocked, near], [elsewhere, far],
    ]) {
      await q(
        `insert into addresses (user_id, zone_id, street, label)
         values ($1, $2, 'شارع', 'البيت')`,
        [uid, zone],
      );
    }

    priorLimit = (await q(
      "select value from config where key = 'marketing_push_per_week'",
    )).rows[0]?.value;
    await q(
      `insert into config (key, value) values ('marketing_push_per_week', '5'::jsonb)
         on conflict (key) do update set value = excluded.value`,
    );
  });

  after(async () => {
    await q(
      "delete from push_outbox where uid = any($1::uuid[])",
      [[subscriber, refuser, blocked, elsewhere]],
    ).catch(() => {});
    await q('delete from promotions where city_id = $1', [city]).catch(() => {});
    await q('delete from merchants where id = $1', [merchant]).catch(() => {});
    await q('delete from auth.users where id = any($1::uuid[])', [
      [owner, subscriber, refuser, blocked, elsewhere],
    ]).catch(() => {});
    await q('delete from zones where city_id = $1', [city]).catch(() => {});
    await q('delete from cities where id = $1', [city]).catch(() => {});
    if (priorLimit !== undefined) {
      await q(
        "update config set value = $1 where key = 'marketing_push_per_week'",
        [priorLimit],
      ).catch(() => {});
    }
    await db.end();
  });

  it('reaches everyone who has not opted out, and nobody who has', async () => {
    const promotion = await promote();

    await q('select public.send_promotion_push()');

    const recipients = (await q(
      `select uid, channel from push_outbox where data ->> 'promotionId' = $1`,
      [promotion],
    )).rows;

    assert.deepEqual(recipients.map((r) => r.uid).sort(), [subscriber, elsewhere].sort());
    // Its own channel, so silencing the offers on the phone cannot silence the three
    // messages that say where the food is.
    assert.deepEqual([...new Set(recipients.map((r) => r.channel))], ['marketing']);
  });

  it('is sent once however often the pass runs', async () => {
    const promotion = await promote();

    await q('select public.send_promotion_push()');
    const first = await queued(promotion);
    await q('select public.send_promotion_push()');

    assert.equal(first, 2);
    assert.equal(await queued(promotion), first);
    assert.notEqual(
      (await q('select pushed_at from promotions where id = $1', [promotion]))
        .rows[0].pushed_at,
      null,
    );
  });

  // An empty `zone_ids` is the whole city; a narrowed campaign is only the zones named.
  it('narrows to the zones the campaign asked for', async () => {
    const promotion = await promote({ zones: [far] });

    await q('select public.send_promotion_push()');

    assert.deepEqual(
      (await q(
        "select uid from push_outbox where data ->> 'promotionId' = $1",
        [promotion],
      )).rows.map((r) => r.uid),
      [elsewhere],
    );
  });

  it('leaves a campaign that has not started yet alone', async () => {
    const promotion = await promote({ startAt: "now() + interval '2 days'" });

    await q('select public.send_promotion_push()');

    assert.equal(await queued(promotion), 0);
    assert.equal(
      (await q('select pushed_at from promotions where id = $1', [promotion]))
        .rows[0].pushed_at,
      null,
    );
  });

  // The cap is the city's patience, and it is read from config rather than passed in —
  // a limit the caller supplies is a limit the caller can raise.
  it('stops at the weekly cap instead of emptying the queue', async () => {
    await q("update config set value = '0'::jsonb where key = 'marketing_push_per_week'");
    const promotion = await promote();

    await q('select public.send_promotion_push()');

    assert.equal(await queued(promotion), 0);
    await q("update config set value = '5'::jsonb where key = 'marketing_push_per_week'");
  });

  it('is not something a signed-in customer may run', async () => {
    await q('begin');
    await q('set local role authenticated');
    await q("select set_config('request.jwt.claims', $1, true)", [
      JSON.stringify({ sub: subscriber, role: 'authenticated' }),
    ]);

    await assert.rejects(
      q('select public.send_promotion_push()'),
      (error) => error.code === '42501',
    );

    await q('rollback');
  });
});
