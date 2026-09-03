import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { freshDatabase } from './harness.mjs';

/**
 * The round-two launch fixes, argued with on PGlite.
 *
 * These are the parts that can be proven without a live stack: the user-profile trigger,
 * the daily-meal reservation window, the promotion expiry pass, the coupon preview's
 * uncapped-percentage refusal, and the status-history append. What needs a real token
 * (RLS, the claims hook, the transition guard) still belongs in test/stack.
 */

let db;
let edku;
let zone;
let merchant;

before(async () => {
  db = await freshDatabase();

  edku = 'edku';
  await db.query("insert into cities (id, name) values ($1, 'إدكو')", [edku]);

  const z = await db.query(
    'insert into zones (city_id, name, default_delivery_fee) values ($1, $2, $3) returning id',
    [edku, 'المنطقة الأولى', 1000],
  );
  zone = z.rows[0].id;

  const m = await db.query(
    `insert into merchants (city_id, type, name, zone_id, phone, status)
     values ($1, 'restaurant', 'مطعم', $2, '0100', 'approved') returning id`,
    [edku, zone],
  );
  merchant = m.rows[0].id;
});

after(() => db?.close());

const uid = async () => {
  const r = await db.query('insert into auth.users default values returning id');
  return r.rows[0].id;
};

describe('every account gets a user row', () => {
  it('inserting an auth user creates the matching public.users row', async () => {
    const u = await uid();

    const r = await db.query('select id from users where id = $1', [u]);
    assert.equal(r.rows.length, 1, 'a public.users row must exist for the account');
  });

  it('re-inserting the same account is a no-op, not a duplicate', async () => {
    // The trigger is `on conflict do nothing`, so an idempotent re-fire leaves one row.
    const u = await uid();

    await db.query('insert into users (id) values ($1) on conflict (id) do nothing', [u]);

    const r = await db.query('select count(*)::int as n from users where id = $1', [u]);
    assert.equal(r.rows[0].n, 1);
  });

  it('defaults come from the schema, not the trigger', async () => {
    const u = await uid();
    const r = await db.query(
      'select is_blocked, rejected_orders_count, fcm_tokens from users where id = $1',
      [u],
    );
    assert.equal(r.rows[0].is_blocked, false);
    assert.equal(r.rows[0].rejected_orders_count, 0);
    assert.deepEqual(r.rows[0].fcm_tokens, []);
  });
});

describe('a daily meal is reservable only today, and only before its window ends', () => {
  let meal;

  before(async () => {
    const r = await db.query(
      `insert into daily_meals (merchant_id, city_id, name, price, date, total_qty,
                                remaining_qty, pickup_window_start, pickup_window_end, status)
       values ($1, $2, 'محشي', 9000, '2026-08-25', 20, 20, 720, 900, 'published') returning id`,
      [merchant, edku],
    );
    meal = r.rows[0].id;
  });

  // `::timestamp at time zone 'Africa/Cairo'` builds the instant, so the test is correct
  // whatever Egypt's DST rule happens to be on that date — and, because of the cast,
  // whatever the session's own `TimeZone` is.
  //
  // The cast is load-bearing and was missing. `'2026-08-25 10:00'` on its own is an
  // untyped literal, and Postgres resolves it against the session zone: as a naive
  // `timestamp` here, where `at time zone` then *interprets* it as Cairo local, and as a
  // `timestamptz` on a UTC session, where the same operator *converts* it instead and the
  // instant lands three hours out. So this passed on a developer's machine in Cairo and
  // failed in CI, which runs in UTC — the one place nobody was looking.
  const reservable = async (atSql) => {
    const r = await db.query(
      `select public.meal_is_reservable(m, ${atSql}) as ok
         from daily_meals m where id = $1`,
      [meal],
    );
    return r.rows[0].ok;
  };

  it('refuses a meal for yesterday', async () => {
    assert.equal(
      await reservable("'2026-08-26 10:00'::timestamp at time zone 'Africa/Cairo'"),
      false,
    );
  });

  it('accepts today\'s meal while the window is still open', async () => {
    assert.equal(
      await reservable("'2026-08-25 10:00'::timestamp at time zone 'Africa/Cairo'"),
      true,
    );
  });

  it('refuses today\'s meal once the window has closed', async () => {
    assert.equal(
      await reservable("'2026-08-25 15:30'::timestamp at time zone 'Africa/Cairo'"),
      false,
    );
  });
});

describe('expired approved promotions become ended', () => {
  let requester;

  before(async () => {
    requester = await uid();
  });

  const insert = (status, startAt, endAt) =>
    db.query(
      `insert into promotions (city_id, merchant_id, channel, status, render_mode,
                               start_at, end_at, requested_by)
       values ($1, $2, 'push', $3, 'text', $4, $5, $6) returning id`,
      [edku, merchant, status, startAt, endAt, requester],
    );

  it('marks an approved push whose end has passed, and leaves the rest', async () => {
    const expired = (await insert('approved', '2026-08-01', '2026-08-02')).rows[0].id;
    const live = (await insert('approved', '2026-08-01', '2099-01-01')).rows[0].id;
    const requested = (await insert('requested', '2026-08-01', '2026-08-02')).rows[0].id;

    const ended = (await db.query('select public.end_expired_promotions() as n')).rows[0].n;
    assert.equal(ended, 1);

    const statusOf = async (id) =>
      (await db.query('select status from promotions where id = $1', [id])).rows[0].status;
    assert.equal(await statusOf(expired), 'ended');
    assert.equal(await statusOf(live), 'approved');
    assert.equal(await statusOf(requested), 'requested');
  });
});

describe('the push slot count is city-wide', () => {
  let requester;

  before(async () => {
    requester = await uid();
  });

  it('returns true when the city has pushes left', async () => {
    // No push rows seeded here beyond what other tests leave; the cap of 1 with nothing
    // sent is open.
    const r = await db.query('select public.push_slot_available($1, 1) as ok', [edku]);
    assert.equal(r.rows[0].ok, true);
  });

  it('returns false once the cap is reached', async () => {
    // One approved push already started counts as "sent".
    await db.query(
      `insert into promotions (city_id, merchant_id, channel, status, render_mode,
                               start_at, end_at, requested_by)
       values ($1, $2, 'push', 'approved', 'text',
               now() - interval '1 day', now() + interval '1 day', $3)`,
      [edku, merchant, requester],
    );

    const r = await db.query('select public.push_slot_available($1, 1) as ok', [edku]);
    assert.equal(r.rows[0].ok, false);
  });
});

describe('the coupon preview refuses what the placement refuses', () => {
  it('an uncapped percentage is malformed, never a discount', async () => {
    // The table constraint blocks writing one, so force it in past the CHECK by
    // disabling it only for this fixture — the shared check must still refuse.
    await db.query('alter table coupons drop constraint coupons_percentage_is_capped');
    try {
      await db.query(
        `insert into coupons (code, city_id, type, value, max_discount, is_active)
         values ('UNCAPPED', $1, 'percentage', 1500, null, true)`,
        [edku],
      );

      // The same function place_order and evaluate_coupon both call; PGlite has no
      // auth.uid(), so this is the reachable seam for the shared rule.
      const r = await db.query(
        'select public.percentage_coupon_is_capped(c) as ok from coupons c where code = $1',
        ['UNCAPPED'],
      );
      assert.equal(r.rows[0].ok, false);
    } finally {
      await db.query('delete from coupons where code = \'UNCAPPED\'');
      await db.query(
        'alter table coupons add constraint coupons_percentage_is_capped ' +
        'check (type <> \'percentage\' or max_discount is not null)',
      );
    }
  });
});

describe('every status change leaves a trace', () => {
  it('appends a history row when the status moves', async () => {
    const customer = await uid();
    await db.query('insert into users (id) values ($1) on conflict (id) do nothing', [customer]);
    const o = await db.query(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                           merchant_id, merchant_name, zone_id, type, items, pricing)
       values ($1, $2, 'ع', '0100', $3, 'م', $4, 'instant', '[]'::jsonb, '{}'::jsonb)
       returning id`,
      [edku, customer, merchant, zone],
    );
    const order = o.rows[0].id;

    await db.query("update orders set status = 'accepted' where id = $1", [order]);

    const r = await db.query(
      'select status, status_history from orders where id = $1',
      [order],
    );
    assert.equal(r.rows[0].status, 'accepted');
    assert.equal(r.rows[0].status_history.length, 1);
    assert.equal(r.rows[0].status_history[0].from, 'placed');
    assert.equal(r.rows[0].status_history[0].to, 'accepted');
    // PGlite serialises the timestamptz inside jsonb as a string; the stack suite
    // (pg driver) sees a Date. Either way it has to be there.
    assert.ok(r.rows[0].status_history[0].at);
  });

  it('does not append when nothing changed', async () => {
    const customer = await uid();
    await db.query('insert into users (id) values ($1) on conflict (id) do nothing', [customer]);
    const o = await db.query(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                           merchant_id, merchant_name, zone_id, type, items, pricing)
       values ($1, $2, 'ع', '0100', $3, 'م', $4, 'instant', '[]'::jsonb, '{}'::jsonb)
       returning id`,
      [edku, customer, merchant, zone],
    );
    const order = o.rows[0].id;

    await db.query("update orders set status = 'placed' where id = $1", [order]);

    const r = await db.query(
      'select status_history from orders where id = $1',
      [order],
    );
    assert.equal(r.rows[0].status_history.length, 0);
  });
});
