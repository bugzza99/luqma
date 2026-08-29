import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * The scheduled server work, against the real local stack.
 *
 * The escalator and the nightly pass move what no client may - which makes them exactly
 * the kind of code whose boundary needs proving rather than assuming. Here they run as
 * production will run them (by hand or by cron; both hit the same SECURITY DEFINER),
 * beside the proof that a customer holding a real token still cannot do what the
 * machine does.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

/** Simulates a caller the way PostgREST does, per transaction. */
async function as(identity, fn) {
  await q('begin');
  try {
    if (identity.anon) {
      await q("select set_config('role', 'anon', true)");
      await q("select set_config('request.jwt.claims', '{\"role\":\"anon\"}', true)");
      return await fn();
    }
    const claims = JSON.stringify({
      sub: identity.uid,
      role: 'authenticated',
      app_metadata: identity.claims ?? {},
    });
    await q("select set_config('role', 'authenticated', true)");
    await q("select set_config('request.jwt.claims', $1, true)", [claims]);
    return await fn();
  } finally {
    await q('rollback');
  }
}

const uid = async () => (await q(
  "insert into auth.users (id, instance_id, aud, role) " +
  "values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', " +
  "'authenticated') returning id",
)).rows[0].id;

describe('scheduled jobs', () => {
  let city, zone, merchant, plan;
  let customerUid;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = 'jobs-test-city';
    await q("insert into cities (id, name) values ($1, 'مدينة الوظائف') on conflict do nothing",
            [city]);
    zone = (await q(
      'insert into zones (city_id, name) values ($1, $2) returning id',
      [city, 'منطقة'],
    )).rows[0].id;

    merchant = (await q(
      `insert into merchants (city_id, type, name, zone_id, phone, status)
       values ($1, 'restaurant', 'مطعم الوظائف', $2, '0100', 'approved')
       returning id`,
      [city, zone],
    )).rows[0].id;

    customerUid = await uid();

    // A plan to hand out and take away.
    plan = 'jobs-test-plan';
    await q(`insert into plans (id, name, price_monthly) values ($1, 'خطة الوظائف', 30000)
             on conflict (id) do nothing`, [plan]);
  });

  after(async () => {
    // Everything here restricts its parent - the whole schema is built so live business
    // rows cannot vanish underneath history - so teardown goes leaf-first.
    await q('delete from order_settlements where order_id in (select id from orders where city_id = $1)', [city]);
    await q('delete from orders where city_id = $1', [city]);
    await q(`delete from subscriptions where merchant_id in
               (select id from merchants where city_id = $1)`, [city]);
    await q('delete from merchants where city_id = $1', [city]);
    await q('delete from zones where city_id = $1', [city]);
    await q('delete from cities where id = $1', [city]);
    await q('delete from plans where id = $1', [plan]);
    await db.end();
  });

  /** Seeds one placed order with full control over its deadline. */
  async function seedOrder({ type = 'instant', deadline, status = 'placed' } = {}) {
    return (await q(
      `insert into orders
         (city_id, customer_uid, customer_name, customer_phone, merchant_id,
          merchant_name, zone_id, delivery_by, type, items, pricing,
          status, accept_deadline_at)
       values ($1, $2, 'عميل', '0100', $3, 'مطعم', $4, 'platform', $5,
               '[]'::jsonb, '{"subtotal":12000,"deliveryFee":1500,"total":13500}'::jsonb,
               $6, $7)
       returning id`,
      [city, customerUid, merchant, zone, type, status, deadline ?? null],
    )).rows[0].id;
  }

  describe('the deadline escalator', () => {
    it('raises an order whose deadline passed, and says who did it', async () => {
      const id = await seedOrder({ deadline: new Date(Date.now() - 60_000) });

      const moved = (await q('select public.escalate_unanswered_orders() as n')).rows[0].n;
      assert.ok(moved >= 1);

      const row = (await q('select status, status_history from orders where id = $1', [id]))
        .rows[0];
      assert.equal(row.status, 'needsAttention');
      const last = row.status_history.at(-1);
      assert.equal(last.by, 'system');
      assert.equal(last.to, 'needsAttention');
    });

    it('leaves pre-orders, future deadlines and answered orders alone', async () => {
      const preorderId = await seedOrder({ type: 'preorder' });
      const futureId = await seedOrder({ deadline: new Date(Date.now() + 600_000) });
      const acceptedId = await seedOrder({
        status: 'accepted',
        deadline: new Date(Date.now() - 600_000),
      });

      await q('select public.escalate_unanswered_orders()');

      for (const [label, id, expected] of [
        ['the pre-order', preorderId, 'placed'],
        ['the future deadline', futureId, 'placed'],
        ['the accepted order', acceptedId, 'accepted'],
      ]) {
        const row = (await q('select status from orders where id = $1', [id])).rows[0];
        assert.equal(row.status, expected, label);
      }
    });

    it('refuses a customer who tries to raise the flag themselves', async () => {
      const id = await seedOrder({ deadline: new Date(Date.now() + 600_000) });

      const refusal = await as({ uid: customerUid }, async () => {
        try {
          await q("update orders set status = 'needsAttention' where id = $1", [id]);
          return null;
        } catch (error) {
          return error.message;
        }
      });
      assert.match(refusal ?? '', /may not move an order|column not yours/);
    });
  });

  describe('the nightly billing pass', () => {
    /** Seeds plan state through the same door the server itself uses. */
    // Seeds both halves, because they mean different things now.
    //
    // `subscriptions` is the receipt — what was paid, and when. `merchants.plan_expires_at`
    // is the state, and it is what the nightly pass reads: one current truth instead of N
    // historical rows, so the query is bounded *and* correct. A fixture that wrote only
    // the receipt left the pass nothing to find.
    async function seedPlanState(startedSql, expiresSql) {
      await q('begin');
      try {
        await q("select set_config('app.server_mode', 'on', true)");
        await q(
          `update merchants set plan_id = $1, plan_expires_at = ${expiresSql.replace(/\)$/, '')}
            where id = $2`,
          [plan, merchant],
        );
        await q(
          `insert into subscriptions
             (merchant_id, plan_id, amount, started_at, expires_at)
           values ($1, $2, 30000, ${startedSql}, ${expiresSql}`,
          [merchant, plan],
        );
        await q('commit');
      } catch (error) {
        await q('rollback');
        throw error;
      }
    }

    it('clears the plan of a merchant whose newest term has ended', async () => {
      // Seeded through server_mode - the guard rightly refuses plan writes to anyone
      // else, including this connection's superuser.
      await seedPlanState(`now() - interval '40 days'`, `now() - interval '10 days')`);

      const downgraded =
        (await q('select public.downgrade_expired_subscriptions() as n')).rows[0].n;
      assert.ok(downgraded >= 1);

      const row =
        (await q('select plan_id from merchants where id = $1', [merchant])).rows[0];
      assert.equal(row.plan_id, null);
    });

    it('keeps the plan of a merchant with a live term', async () => {
      await seedPlanState(`now()`, `now() + interval '30 days')`);

      await q('select public.downgrade_expired_subscriptions()');

      const row =
        (await q('select plan_id from merchants where id = $1', [merchant])).rows[0];
      assert.equal(row.plan_id, plan);
    });
  });

  describe('daily meal drafts', () => {
    /** Reads daily_meals as the given identity, returning how many rows it sees. */
    async function mealsSeen(identity) {
      return as(identity, async () => {
        const rows = await q('select id from daily_meals where id = $1', [draftId]);
        return rows.rowCount;
      });
    }

    let draftId;
    let ownerUid;

    before(async () => {
      draftId = (await q(
        `insert into daily_meals
           (merchant_id, city_id, name, price, date, total_qty, remaining_qty,
            pickup_window_start, pickup_window_end, status)
         values ($1, $2, 'أكلة مسودة', 8000, current_date, 5, 5, 780, 960, 'draft')
         returning id`,
        [merchant, city],
      )).rows[0].id;

      // The kitchen's owner, exactly as their app signs in.
      ownerUid = await uid();
      await q('insert into users (id) values ($1) on conflict (id) do nothing', [ownerUid]);
      await q(
        `insert into staff (uid, scope, role, merchant_id)
         values ($1, 'merchant', 'owner', $2)`,
        [ownerUid, merchant],
      );
    });

    after(async () => {
      await q('delete from staff where uid = $1', [ownerUid]);
      await q('delete from users where id = $1', [ownerUid]);
      await q('delete from daily_meals where id = $1', [draftId]);
    });

    it('hides a draft from anon', async () => {
      assert.equal(await mealsSeen({ uid: null, anon: true }), 0);
    });

    it('hides a draft from other customers', async () => {
      assert.equal(await mealsSeen({ uid: customerUid }), 0);
    });

    it('shows a draft to its own kitchen', async () => {
      assert.equal(
        await mealsSeen({
          uid: ownerUid,
          claims: { role: 'owner', scope: 'merchant', merchant_id: merchant },
        }),
        1,
      );
    });

    it('shows a published meal to everyone', async () => {
      // The suite's own after() removes the row; no status reset needed.
      await q("update daily_meals set status = 'published' where id = $1", [draftId]);
      assert.equal(await mealsSeen({ uid: customerUid }), 1);
    });
  });
});
