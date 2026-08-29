import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * Two policies that were narrower than the rule they were written to enforce.
 *
 * Both had been green for weeks, for the same reason the promotions bug was: nothing
 * tested them. `storage.objects` had no boundary test at all, and `correct_own_rating`
 * was covered only by the insert path beside it — which is careful, and is not the
 * policy that was wrong.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

const uid = async () => (await q(
  "insert into auth.users (id, instance_id, aud, role) values (gen_random_uuid(), "
  + "'00000000-0000-0000-0000-000000000000','authenticated','authenticated') returning id",
)).rows[0].id;

/** Runs `fn` as one identity, in a transaction that is always rolled back. */
async function as(identity, fn) {
  await q('begin');
  try {
    await q("select set_config('role','authenticated',true)");
    await q("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
      sub: identity.uid, role: 'authenticated', app_metadata: identity.claims ?? {},
    })]);
    return await fn();
  } finally {
    await q('rollback');
  }
}

/** Whatever `fn` does, reported as the error message or null when it was allowed. */
async function refused(identity, fn) {
  return as(identity, async () => {
    try {
      await fn();
      return null;
    } catch (error) {
      return error.message;
    }
  });
}

describe('two policies that were too narrow', () => {
  let city, zone, merchantA, merchantB, customer, other;
  const uids = [];

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = 'rbf-' + Date.now();
    await q('insert into cities (id,name) values ($1,$2)', [city, 'مدينة']);
    zone = (await q('insert into zones (city_id,name) values ($1,$2) returning id',
                    [city, 'منطقة'])).rows[0].id;
    const shop = async (name) => (await q(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ($1,'restaurant',$2,$3,'0100','approved') returning id`,
      [city, name, zone])).rows[0].id;
    merchantA = await shop('المطعم اللي طلب منه');
    merchantB = await shop('المطعم اللي عمره ما شافه');

    customer = { uid: await uid(), claims: {} };
    other = { uid: await uid(), claims: {} };
    uids.push(customer.uid, other.uid);
  });

  // Everything this file makes, it removes. The two cloud suites are destructive by
  // nature and that is why they have a project of their own; it is not a reason to add
  // to the pile. `auth.users` last — `users` rows hang off it by foreign key.
  after(async () => {
    await q('delete from ratings where merchant_id in ($1,$2)', [merchantA, merchantB]);
    await q('delete from order_settlements where order_id in (select id from orders where city_id = $1)', [city]);
    await q('delete from orders where city_id = $1', [city]);
    await q('delete from merchants where city_id = $1', [city]);
    await q('delete from zones where city_id = $1', [city]);
    await q('delete from cities where id = $1', [city]);
    await q('delete from auth.users where id = any($1)', [uids]);
    await db.end();
  });

  describe('what a customer may write into the media bucket', () => {
    // `media_upload` checked only the bucket. The bucket is public, so every object is
    // served from the project's own domain the instant it lands — an unbounded number of
    // 2 MiB files under any name at all, against a 1 GB tier.
    const put = (who, name) => refused(who, () => q(
      "insert into storage.objects (bucket_id, name) values ('media', $1)", [name]));

    it('under their own id, which is the whole point', async () => {
      assert.equal(await put(customer, `${customer.uid}/menuItem/a.jpg`), null);
    });

    it('but not under somebody else\'s', async () => {
      assert.ok(await put(customer, `${other.uid}/menuItem/a.jpg`),
        'an object attributable to the wrong person is worse than no attribution');
    });

    it('and not at the root of the bucket', async () => {
      assert.ok(await put(customer, 'a.jpg'),
        'a name with no prefix belongs to nobody');
    });

    it('nor by dressing the prefix up as a path', async () => {
      assert.ok(await put(customer, `not-a-uuid/${customer.uid}/a.jpg`),
        'it is the first segment that is checked, not any segment');
    });
  });

  describe('correcting a rating, and inventing one', () => {
    // `rate_own_delivered_order` demands an order this customer actually received from
    // this merchant. `correct_own_rating` demanded only that the row be theirs — so the
    // careful check could be walked around by rating one shop and then editing the row.
    const deliveredOrder = async (merchantId) => (await q(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                           merchant_id, merchant_name, zone_id, type, items, pricing, status)
       values ($1, $2, 'ع', '0100', $3, 'م', $4, 'instant', '[]'::jsonb, '{}'::jsonb,
               'delivered') returning id`,
      [city, customer.uid, merchantId, zone])).rows[0].id;

    it('they may still fix the stars they gave', async () => {
      const order = await deliveredOrder(merchantA);
      await q(`insert into ratings (order_id, merchant_id, customer_uid, stars)
               values ($1,$2,$3,5)`, [order, merchantA, customer.uid]);
      assert.equal(
        await refused(customer, () => q(
          'update ratings set stars = 3 where order_id = $1', [order])),
        null,
        'changing your mind about a shop you used is the point of the policy',
      );
      await q('delete from ratings where order_id = $1', [order]);
    });

    it('but not move them onto a shop they never ordered from', async () => {
      const order = await deliveredOrder(merchantA);
      await q(`insert into ratings (order_id, merchant_id, customer_uid, stars)
               values ($1,$2,$3,5)`, [order, merchantA, customer.uid]);
      assert.ok(
        await refused(customer, () => q(
          'update ratings set merchant_id = $2, stars = 1 where order_id = $1',
          [order, merchantB])),
        'one star on a merchant they never bought anything from, as often as there are '
        + 'merchants',
      );
      await q('delete from ratings where order_id = $1', [order]);
    });

    it('and not hand their rating to somebody else', async () => {
      const order = await deliveredOrder(merchantA);
      await q(`insert into ratings (order_id, merchant_id, customer_uid, stars)
               values ($1,$2,$3,5)`, [order, merchantA, customer.uid]);
      assert.ok(
        await refused(customer, () => q(
          'update ratings set customer_uid = $2 where order_id = $1', [order, other.uid])),
        'the using clause is judged on the row as it was; the check must judge the row '
        + 'as it will be',
      );
      await q('delete from ratings where order_id = $1', [order]);
    });
  });
  describe('the nightly sweep can actually delete', () => {
    // Found while chasing the two above. Hosted Supabase carries a trigger on
    // `storage.objects` — `protect_delete` — that refuses any direct DELETE and tells you
    // to use the Storage API. `sweep_orphan_media` is a direct DELETE, so the 03:30 cron
    // job had been failing every night since the day it was scheduled.
    //
    // Nothing noticed because nothing could: the job's only output is a cron log nobody
    // reads, PGlite has no such trigger so the schema suite is happy, and the thing it
    // fails to do — reclaim space from images nobody attached — looks exactly like an
    // empty bucket until the tier fills up.
    it('an orphan older than a week loses its row and its object', async () => {
      await q('begin');
      try {
        const name = `${customer.uid}/menuItem/sweep-${Date.now()}.jpg`;
        await q("insert into storage.objects (bucket_id, name) values ('media', $1)", [name]);
        const id = (await q(
          `insert into media (kind, url, status, uploaded_by, created_at)
           values ('menuItem', $1, 'pending', $2, now() - interval '8 days') returning id`,
          [`https://x.supabase.co/storage/v1/object/public/media/${name}`, customer.uid],
        )).rows[0].id;

        await q('select public.sweep_orphan_media()');

        assert.equal((await q('select 1 from media where id = $1', [id])).rowCount, 0,
          'the row is gone');
        assert.equal(
          (await q("select 1 from storage.objects where bucket_id = 'media' and name = $1",
                   [name])).rowCount,
          0, 'and so are the bytes it was pointing at');
      } finally {
        // Whatever happened, nothing here is kept: the sweep is project-wide by design
        // and this test must not be the thing that deletes somebody else's fixture.
        await q('rollback');
      }
    });
  });
});
