import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * The outbox is deliberately unreadable from a phone, so the report is tested through
 * the same authenticated admin boundary that AdminApp uses rather than by granting the
 * table away for the sake of a count.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
let city, zone, merchant, adminUid, customerUid, promotionId, emptyPromotionId;

const q = (sql, params) => db.query(sql, params);

const makeAccount = async () => (await q(
  `insert into auth.users (id, instance_id, aud, role)
   values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000',
           'authenticated', 'authenticated')
   returning id`,
)).rows[0].id;

/** A transaction keeps one test identity and its effects from leaking into the next. */
async function as(identity, fn) {
  await q('begin');
  try {
    await q("select set_config('role', 'authenticated', true)");
    await q("select set_config('request.jwt.claims', $1, true)", [JSON.stringify({
      sub: identity.uid,
      role: 'authenticated',
      app_metadata: identity.claims ?? {},
    })]);
    return await fn();
  } finally {
    await q('rollback');
  }
}

describe('promotion_push_report', () => {
  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = `push-report-${Date.now()}`;
    await q('insert into cities (id, name) values ($1, $2)', [city, 'مدينة التقرير']);
    zone = (await q(
      'insert into zones (city_id, name) values ($1, $2) returning id',
      [city, 'منطقة'],
    )).rows[0].id;

    adminUid = await makeAccount();
    customerUid = await makeAccount();
    await q(
      "insert into staff (uid, scope, role) values ($1, 'platform', 'admin')",
      [adminUid],
    );
    merchant = (await q(
      `insert into merchants
         (city_id, type, name, zone_id, phone, status, owner_uid)
       values ($1, 'restaurant', 'مطعم', $2, '01000000000', 'approved', $3)
       returning id`,
      [city, zone, adminUid],
    )).rows[0].id;

    const makePromotion = async () => (await q(
      `insert into promotions
         (city_id, merchant_id, channel, status, title, start_at, end_at,
          requested_by, pushed_at)
       values ($1, $2, 'push', 'approved', 'عرض', now() - interval '1 hour',
               now() + interval '1 day', $3, now())
       returning id`,
      [city, merchant, adminUid],
    )).rows[0].id;

    promotionId = await makePromotion();
    emptyPromotionId = await makePromotion();

    for (const [sent, attempts, error] of [
      [true, 1, null],
      [false, 0, null],
      [false, 4, 'temporary'],
      [false, 5, 'gave up'],
    ]) {
      await q(
        `insert into push_outbox
           (uid, title, body, data, channel, sent_at, attempts, last_error)
         values ($1, 'عرض', 'تفاصيل', jsonb_build_object('promotionId', $2::text),
                 'marketing', case when $3 then now() else null end, $4, $5)`,
        [customerUid, promotionId, sent, attempts, error],
      );
    }
  });

  after(async () => {
    await q(
      "delete from push_outbox where data ->> 'promotionId' = any($1::text[])",
      [[promotionId, emptyPromotionId]],
    ).catch(() => {});
    await q('delete from promotions where city_id = $1', [city]).catch(() => {});
    await q('delete from merchants where id = $1', [merchant]).catch(() => {});
    await q('delete from auth.users where id = any($1::uuid[])', [
      [adminUid, customerUid],
    ]).catch(() => {});
    await q('delete from zones where city_id = $1', [city]).catch(() => {});
    await q('delete from cities where id = $1', [city]).catch(() => {});
    await db?.end();
  });

  it('separates sent, waiting, and exhausted rows inside the queued total', async () => {
    const report = await as(
      { uid: adminUid, claims: { admin: true, role: 'admin', scope: 'platform' } },
      async () => (await q(
        'select public.promotion_push_report($1) as report',
        [promotionId],
      )).rows[0].report,
    );

    assert.deepEqual(report, { queued: 4, sent: 1, waiting: 2, failed: 1 });
  });

  it('answers zero when nobody was queued for the campaign', async () => {
    const report = await as(
      { uid: adminUid, claims: { admin: true, role: 'admin', scope: 'platform' } },
      async () => (await q(
        'select public.promotion_push_report($1) as report',
        [emptyPromotionId],
      )).rows[0].report,
    );

    assert.deepEqual(report, { queued: 0, sent: 0, waiting: 0, failed: 0 });
  });

  it('refuses a signed-in caller who is not an active admin', async () => {
    await assert.rejects(
      as(
        { uid: customerUid },
        () => q('select public.promotion_push_report($1)', [promotionId]),
      ),
      (error) => error.code === '42501',
    );
  });
});
