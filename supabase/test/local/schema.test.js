import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { freshDatabase } from './harness.mjs';

/**
 * The schema, applied to a real Postgres and then argued with.
 *
 * PGlite is Postgres compiled to WebAssembly: no Docker, no service, and the same
 * planner and the same constraint machinery as the server this will run on. That matters
 * more here than convenience — half the point of moving to Postgres is that rules the
 * app used to enforce become constraints the database enforces, and a constraint nobody
 * has watched refuse anything is a comment with punctuation.
 *
 * Every test below tries to write something the product must never contain.
 */

let db;
let edku;
let zone;
let merchant;

// One hook, not two: node:test starts a second top-level `before` without waiting for
// the first, so anything the second needs from the first is undefined when it runs.
before(async () => {
  db = await freshDatabase();

  // The fixtures every group below leans on: one city, one zone, one approved merchant.
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

/** Runs `sql` and returns the error message, or null when it was accepted. */
async function refused(sql, params = []) {
  try {
    await db.query(sql, params);
    return null;
  } catch (error) {
    return error.message;
  }
}

const uid = async () => {
  const r = await db.query('insert into auth.users default values returning id');
  return r.rows[0].id;
};

describe('the schema applies at all', () => {
  it('creates every table the product needs', async () => {
    const r = await db.query(`
      select table_name from information_schema.tables
       where table_schema = 'public' order by table_name
    `);
    const tables = r.rows.map((t) => t.table_name);

    for (const expected of [
      'addresses', 'audit_log', 'cities', 'config', 'coupon_redemptions', 'coupons',
      'daily_meals', 'home_sections', 'landmarks', 'media', 'menu_categories',
      'menu_items', 'merchant_served_zones', 'merchants', 'order_issues', 'orders',
      'plans', 'promotions', 'ratings', 'staff', 'subscriptions', 'users', 'zones',
    ]) {
      assert.ok(tables.includes(expected), `missing table: ${expected}`);
    }
  });

  it('keeps updated_at without being asked', async () => {
    const before = await db.query('select updated_at from merchants where id = $1', [merchant]);
    await db.query("update merchants set name = 'مطعم تاني' where id = $1", [merchant]);
    const after = await db.query('select updated_at from merchants where id = $1', [merchant]);

    assert.ok(after.rows[0].updated_at > before.rows[0].updated_at);
  });
});

describe('money cannot go backwards', () => {
  // This was a check inside `Coupon.evaluate`, found missing by the pre-launch audit. A
  // negative discount is arithmetic that raises the total, and the courier collects the
  // higher figure at the door.
  it('a coupon cannot carry a negative value', async () => {
    const error = await refused(
      `insert into coupons (code, city_id, type, value, max_discount)
       values ('BAD', $1, 'fixedAmount', -2000, null)`,
      [edku],
    );
    assert.match(error ?? '', /coupons_value_check|violates check constraint/);
  });

  // Uncapped, a 15% code on a 2000 EGP order costs the merchant 300 against the 30 they
  // had in mind. In Firestore this was a branch in Dart; here it cannot be written.
  it('a percentage coupon must carry a cap', async () => {
    const error = await refused(
      `insert into coupons (code, city_id, type, value, max_discount)
       values ('UNCAPPED', $1, 'percentage', 1500, null)`,
      [edku],
    );
    assert.match(error ?? '', /coupons_percentage_is_capped/);
  });

  it('a capped percentage is fine', async () => {
    const error = await refused(
      `insert into coupons (code, city_id, type, value, max_discount)
       values ('AHLAN', $1, 'percentage', 1500, 3000)`,
      [edku],
    );
    assert.equal(error, null);
  });

  it('the same code cannot exist twice in one city, whatever its case', async () => {
    const error = await refused(
      `insert into coupons (code, city_id, type, value, max_discount)
       values ('ahlan', $1, 'percentage', 1000, 2000)`,
      [edku],
    );
    assert.match(error ?? '', /coupons_code_idx|duplicate key/);
  });

  // Mirrored from Remote Config. Clamping only in the app leaves the real limit to
  // whoever is holding the phone.
  it('a delivery fee override outside the range is refused', async () => {
    const error = await refused(
      'update merchants set delivery_fee_override = 9000 where id = $1',
      [merchant],
    );
    assert.match(error ?? '', /delivery_fee_override|check constraint/);
  });

  it('zero is allowed, because free delivery is a real offer', async () => {
    assert.equal(
      await refused('update merchants set delivery_fee_override = 0 where id = $1', [merchant]),
      null,
    );
  });
});

describe('a merchant that has traded cannot be deleted', () => {
  // The decision in docs/16: a merchant added by mistake is a typo and should go; one
  // that has taken orders is history and must not. It was going to be a count the app
  // remembered to make. Here the foreign key is the whole of it.
  it('a merchant with no orders deletes cleanly', async () => {
    const m = await db.query(
      `insert into merchants (city_id, type, name, zone_id, phone)
       values ($1, 'restaurant', 'غلطة', $2, '0100') returning id`,
      [edku, zone],
    );
    assert.equal(await refused('delete from merchants where id = $1', [m.rows[0].id]), null);
  });

  it('a merchant with an order does not', async () => {
    const customer = await uid();
    // The ensure_user_profile trigger already made the row; the name still lands here.
    await db.query(
      'insert into users (id, name) values ($1, $2) on conflict (id) do update set name = excluded.name',
      [customer, 'عميل'],
    );
    await db.query(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                           merchant_id, merchant_name, zone_id, type, items, pricing)
       values ($1, $2, 'عميل', '0100', $3, 'مطعم', $4, 'instant', '[]'::jsonb,
               '{"total":0}'::jsonb)`,
      [edku, customer, merchant, zone],
    );

    const error = await refused('delete from merchants where id = $1', [merchant]);
    assert.match(error ?? '', /foreign key|violates/);
  });
});

describe('the last portion', () => {
  let meal;

  before(async () => {
    const r = await db.query(
      `insert into daily_meals (merchant_id, city_id, name, price, date, total_qty,
                                remaining_qty, pickup_window_start, pickup_window_end)
       values ($1, $2, 'محشي', 9000, '2026-08-24', 20, 3, 720, 900) returning id`,
      [merchant, edku],
    );
    meal = r.rows[0].id;
  });

  // The race the whole daily_meals design exists to prevent, now settled by the database
  // rather than by a Cloud Function: whoever loses affects no rows.
  it('two people taking the last portion — one of them loses', async () => {
    await db.query('update daily_meals set remaining_qty = 1 where id = $1', [meal]);

    const first = await db.query(
      'update daily_meals set remaining_qty = remaining_qty - 1 where id = $1 and remaining_qty >= 1',
      [meal],
    );
    const second = await db.query(
      'update daily_meals set remaining_qty = remaining_qty - 1 where id = $1 and remaining_qty >= 1',
      [meal],
    );

    assert.equal(first.affectedRows, 1);
    assert.equal(second.affectedRows, 0, 'the second reservation must find nothing left');
  });

  it('what is left can never go below zero', async () => {
    const error = await refused(
      'update daily_meals set remaining_qty = -1 where id = $1',
      [meal],
    );
    assert.match(error ?? '', /remaining_qty|check constraint/);
  });

  it('or above what was cooked', async () => {
    const error = await refused(
      'update daily_meals set remaining_qty = 999 where id = $1',
      [meal],
    );
    assert.match(error ?? '', /daily_meals_remaining_within_total/);
  });

  it('a collection window has to end after it starts', async () => {
    const error = await refused(
      `insert into daily_meals (merchant_id, city_id, name, price, date, total_qty,
                                remaining_qty, pickup_window_start, pickup_window_end)
       values ($1, $2, 'مقلوب', 9000, '2026-08-25', 5, 5, 900, 720)`,
      [merchant, edku],
    );
    assert.match(error ?? '', /daily_meals_window_ordered/);
  });
});

describe('one rating per order', () => {
  // Keyed by the order rather than guarded by a rule: rating again corrects the first
  // instead of moving a merchant's average a second time.
  it('a second rating for the same order replaces the first', async () => {
    const customer = await uid();
    // The ensure_user_profile trigger already made the row; this is now a no-op guard.
    await db.query('insert into users (id) values ($1) on conflict (id) do nothing', [customer]);
    const o = await db.query(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                           merchant_id, merchant_name, zone_id, type, items, pricing, status)
       values ($1, $2, 'عميل', '0100', $3, 'مطعم', $4, 'instant', '[]'::jsonb,
               '{"total":0}'::jsonb, 'delivered') returning id`,
      [edku, customer, merchant, zone],
    );
    const order = o.rows[0].id;

    await db.query(
      'insert into ratings (order_id, merchant_id, customer_uid, stars) values ($1, $2, $3, 5)',
      [order, merchant, customer],
    );

    const error = await refused(
      `insert into ratings (order_id, merchant_id, customer_uid, stars) values ($1, $2, $3, 1)
       on conflict (order_id) do update set stars = excluded.stars`,
      [order, merchant, customer],
    );
    assert.equal(error, null);

    const r = await db.query('select count(*)::int as n, max(stars) as stars from ratings where order_id = $1', [order]);
    assert.equal(r.rows[0].n, 1, 'a second vote must not exist');
    assert.equal(r.rows[0].stars, 1);
  });

  it('stars outside one to five are refused', async () => {
    const customer = await uid();
    // The ensure_user_profile trigger already made the row; this is now a no-op guard.
    await db.query('insert into users (id) values ($1) on conflict (id) do nothing', [customer]);
    const o = await db.query(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                           merchant_id, merchant_name, zone_id, type, items, pricing)
       values ($1, $2, 'ع', '0100', $3, 'م', $4, 'instant', '[]'::jsonb, '{}'::jsonb)
       returning id`,
      [edku, customer, merchant, zone],
    );

    const error = await refused(
      'insert into ratings (order_id, merchant_id, customer_uid, stars) values ($1, $2, $3, 9)',
      [o.rows[0].id, merchant, customer],
    );
    assert.match(error ?? '', /stars|check constraint/);
  });
});

describe('promotions', () => {
  let requester;

  before(async () => {
    requester = await uid();
  });

  const promotion = (extra = {}) => ({
    render_mode: 'text',
    media_id: null,
    status: 'requested',
    rejection_reason: null,
    start_at: '2026-08-01',
    end_at: '2026-09-01',
    ...extra,
  });

  const insert = (p) =>
    refused(
      `insert into promotions (city_id, merchant_id, channel, status, render_mode, media_id,
                               start_at, end_at, requested_by, rejection_reason)
       values ($1, $2, 'homeBanner', $3, $4, $5, $6, $7, $8, $9)`,
      [edku, merchant, p.status, p.render_mode, p.media_id, p.start_at, p.end_at,
       requester, p.rejection_reason],
    );

  it('text alone needs no artwork — which is the commercial point', async () => {
    assert.equal(await insert(promotion()), null);
  });

  // A banner promising an image and carrying none renders as a broken box on the home
  // screen of every customer in the city.
  it('an image banner with no image is refused', async () => {
    const error = await insert(promotion({ render_mode: 'image' }));
    assert.match(error ?? '', /promotions_image_has_media/);
  });

  it('a run has to end after it starts', async () => {
    const error = await insert(promotion({ end_at: '2026-07-01' }));
    assert.match(error ?? '', /promotions_run_ordered/);
  });

  // A refusal with no reason gives the merchant nothing to fix, and guarantees they ask
  // again with the same thing.
  it('a rejection without a reason is refused', async () => {
    const error = await insert(promotion({ status: 'rejected', rejection_reason: '   ' }));
    assert.match(error ?? '', /promotions_rejection_has_reason/);
  });

  it('a rejection with one is fine', async () => {
    assert.equal(
      await insert(promotion({ status: 'rejected', rejection_reason: 'الصورة مش واضحة' })),
      null,
    );
  });
});

describe('staff', () => {
  // An owner and their courier carry the same merchant; scope is what says whether an
  // account acts for a shop or for the platform, and the two must agree.
  it('a merchant account without a merchant is refused', async () => {
    const u = await uid();
    const error = await refused(
      "insert into staff (uid, scope, role) values ($1, 'merchant', 'owner')",
      [u],
    );
    assert.match(error ?? '', /staff_scope_matches_merchant/);
  });

  it('a platform account bound to one shop is refused too', async () => {
    const u = await uid();
    const error = await refused(
      "insert into staff (uid, scope, role, merchant_id) values ($1, 'platform', 'admin', $2)",
      [u, merchant],
    );
    assert.match(error ?? '', /staff_scope_matches_merchant/);
  });

  it('an owner of a merchant is fine', async () => {
    const u = await uid();
    assert.equal(
      await refused(
        "insert into staff (uid, scope, role, merchant_id) values ($1, 'merchant', 'owner', $2)",
        [u, merchant],
      ),
      null,
    );
  });
});

describe('orders', () => {
  // The countdown is shown on instant orders only: a pre-order is dated and collected in
  // a window, so a deadline on one is a countdown to nothing.
  it('a pre-order cannot carry an accept deadline', async () => {
    const customer = await uid();
    // The ensure_user_profile trigger already made the row; this is now a no-op guard.
    await db.query('insert into users (id) values ($1) on conflict (id) do nothing', [customer]);

    const error = await refused(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                           merchant_id, merchant_name, zone_id, type, items, pricing,
                           accept_deadline_at)
       values ($1, $2, 'ع', '0100', $3, 'م', $4, 'preorder', '[]'::jsonb, '{}'::jsonb, now())`,
      [edku, customer, merchant, zone],
    );
    assert.match(error ?? '', /orders_preorder_has_no_deadline/);
  });

  it('an unknown status cannot be written at all', async () => {
    const customer = await uid();
    // The ensure_user_profile trigger already made the row; this is now a no-op guard.
    await db.query('insert into users (id) values ($1) on conflict (id) do nothing', [customer]);

    const error = await refused(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                           merchant_id, merchant_name, zone_id, type, items, pricing, status)
       values ($1, $2, 'ع', '0100', $3, 'م', $4, 'instant', '[]'::jsonb, '{}'::jsonb,
               'teleported')`,
      [edku, customer, merchant, zone],
    );
    assert.match(error ?? '', /status|check constraint/);
  });

  it('order numbers are handed out without being asked for', async () => {
    const customer = await uid();
    // The ensure_user_profile trigger already made the row; this is now a no-op guard.
    await db.query('insert into users (id) values ($1) on conflict (id) do nothing', [customer]);

    const r = await db.query(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                           merchant_id, merchant_name, zone_id, type, items, pricing)
       values ($1, $2, 'ع', '0100', $3, 'م', $4, 'instant', '[]'::jsonb, '{}'::jsonb)
       returning order_number`,
      [edku, customer, merchant, zone],
    );
    assert.ok(r.rows[0].order_number >= 1000);
  });
});

describe('the audit log', () => {
  // Append-only, including for an admin. A log its own subject can edit proves nothing —
  // and that is a rule in S1, not a constraint. What the schema can promise is that the
  // entry carries who and when.
  it('records who did it and when, without being told the time', async () => {
    const actor = await uid();
    await db.query(
      "insert into audit_log (action, actor, merchant_id) values ('suspendMerchant', $1, $2)",
      [actor, merchant],
    );
    const r = await db.query('select at, actor from audit_log order by at desc limit 1');

    assert.ok(r.rows[0].at instanceof Date);
    assert.equal(r.rows[0].actor, actor);
  });
});
