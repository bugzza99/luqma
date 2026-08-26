import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * The boundary.
 *
 * The port of `firebase/test/firestore.rules.test.js`, against the real local stack —
 * real policies, real `auth.uid()`, real column grants. Everything the pre-launch audit
 * found is in here, because the whole point of moving the boundary is not to leave a
 * hole behind in the move.
 *
 * A user is simulated the way PostgREST does it: become `authenticated` and set the JWT
 * claims for the transaction. That is the same path a request takes, minus the HTTP.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;

/** Runs `fn` as the given identity, in a transaction that is always rolled back. */
async function as(identity, fn) {
  await db.query('begin');
  try {
    if (identity === null) {
      await db.query("select set_config('role', 'anon', true)");
      await db.query("select set_config('request.jwt.claims', '{\"role\":\"anon\"}', true)");
    } else {
      const claims = JSON.stringify({
        sub: identity.uid,
        role: 'authenticated',
        app_metadata: identity.claims ?? {},
      });
      await db.query("select set_config('role', 'authenticated', true)");
      await db.query("select set_config('request.jwt.claims', $1, true)", [claims]);
    }
    return await fn();
  } finally {
    await db.query('rollback');
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

const q = (sql, params) => db.query(sql, params);

/// A fixture write that the column guards would otherwise refuse.
///
/// `is_blocked` and `rejected_orders_count` belong to the server, which is the whole
/// point of the tests below — so putting a customer *into* that state cannot be done as
/// a customer. `app.server_mode` is the same declaration the real server functions make,
/// and it is transaction-local, so it cannot leak into the assertion that follows.
async function asServer(sql, params) {
  await q('begin');
  try {
    await q("select set_config('app.server_mode', 'on', true)");
    return await q(sql, params);
  } finally {
    await q('commit');
  }
}

// --- the cast --------------------------------------------------------------
let customer, otherCustomer, owner, otherOwner, courier, platformCourier, admin;
let edku, zone, merchant, otherMerchant;

// The real `auth.users` has no default for its key — unlike the stub the PGlite schema
// tests use — so the id is supplied here. Everything else about the row is irrelevant to
// a policy: what a policy reads is the token, and the token is set per transaction below.
const uid = async () => (await q(
  "insert into auth.users (id, instance_id, aud, role) " +
  "values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', " +
  "'authenticated') returning id",
)).rows[0].id;

before(async () => {
  db = new Client({ connectionString: DB });
  await db.connect();

  // A clean slate. The stack is shared with `npm run seed`, so nothing here assumes an
  // empty database — it makes its own city.
  edku = 'rls-test-city';
  await q("insert into cities (id, name) values ($1, 'مدينة الاختبار') on conflict do nothing",
          [edku]);

  zone = (await q(
    'insert into zones (city_id, name) values ($1, $2) returning id', [edku, 'منطقة'],
  )).rows[0].id;

  const makeMerchant = async (name) => (await q(
    `insert into merchants (city_id, type, name, zone_id, phone, status)
     values ($1, 'restaurant', $2, $3, '0100', 'approved') returning id`,
    [edku, name, zone],
  )).rows[0].id;

  merchant = await makeMerchant('مطعم');
  otherMerchant = await makeMerchant('مطعم تاني');

  customer = { uid: await uid(), claims: {} };
  otherCustomer = { uid: await uid(), claims: {} };
  admin = { uid: await uid(), claims: { admin: true, role: 'admin', scope: 'platform' } };
  owner = { uid: await uid(),
            claims: { role: 'owner', scope: 'merchant', merchant_id: merchant } };
  otherOwner = { uid: await uid(),
                 claims: { role: 'owner', scope: 'merchant', merchant_id: otherMerchant } };
  courier = { uid: await uid(),
              claims: { role: 'courier', scope: 'merchant', merchant_id: merchant } };
  platformCourier = { uid: await uid(), claims: { role: 'courier', scope: 'platform' } };

  for (const person of [customer, otherCustomer, admin, owner, otherOwner, courier,
                        platformCourier]) {
    await q('insert into users (id) values ($1) on conflict do nothing', [person.uid]);
  }
});

// Torn down in dependency order rather than hopefully: the suite has to be re-runnable,
// and a leftover coupon code from the last run collides with this one on a unique index.
after(async () => {
  for (const sql of [
    'delete from coupons where city_id = $1',
    'delete from orders where city_id = $1',
    'delete from promotions where city_id = $1',
    'delete from daily_meals where city_id = $1',
    'delete from menu_items where merchant_id in (select id from merchants where city_id = $1)',
    'delete from merchants where city_id = $1',
    'delete from landmarks where city_id = $1',
    'delete from home_sections where city_id = $1',
    'delete from zones where city_id = $1',
    'delete from cities where id = $1',
  ]) {
    await q(sql, [edku]).catch((e) => console.error('teardown:', sql, e.message));
  }
  await db?.end();
});

// --------------------------------------------------------------------------

describe('the claims hook', () => {
  // Everything below rests on this. A role in a table a client can write is a role a
  // client can grant itself; this is the server copying it into the token instead.
  it('puts a merchant owner on the token', async () => {
    const u = await uid();
    await q("insert into staff (uid, scope, role, merchant_id) values ($1, 'merchant', 'owner', $2)",
            [u, merchant]);

    const r = await q(
      "select public.custom_access_token_hook($1::jsonb) as out",
      [JSON.stringify({ user_id: u, claims: {} })],
    );
    const meta = r.rows[0].out.claims.app_metadata;

    assert.equal(meta.role, 'owner');
    assert.equal(meta.merchant_id, merchant);
    assert.equal(meta.admin, undefined, 'an owner is not an admin');
  });

  it('marks an admin as one', async () => {
    const u = await uid();
    await q("insert into staff (uid, scope, role) values ($1, 'platform', 'admin')", [u]);

    const r = await q("select public.custom_access_token_hook($1::jsonb) as out",
                      [JSON.stringify({ user_id: u, claims: {} })]);
    assert.equal(r.rows[0].out.claims.app_metadata.admin, true);
  });

  // A deactivated account keeps its row and loses its claims, which is what
  // `staff.js deactivate` is for.
  it('gives a deactivated account nothing', async () => {
    const u = await uid();
    await q(`insert into staff (uid, scope, role, merchant_id, is_active)
             values ($1, 'merchant', 'owner', $2, false)`, [u, merchant]);

    const r = await q("select public.custom_access_token_hook($1::jsonb) as out",
                      [JSON.stringify({ user_id: u, claims: {} })]);
    assert.deepEqual(r.rows[0].out.claims.app_metadata, {});
  });

  // A customer's token carries no app_metadata at all. Reading a claim that is not there
  // has to be false, never an error — the lesson `token.get('x', default)` taught.
  it('a customer with no claims reads as nobody, not as an error', async () => {
    const answers = await as(customer, async () => (await db.query(
      `select public.is_admin() as admin, public.staff_role() as role,
              public.is_merchant_owner($1) as owner`, [merchant],
    )).rows[0]);

    assert.equal(answers.admin, false);
    assert.equal(answers.role, '');
    assert.equal(answers.owner, false);
  });
});

describe('merchants', () => {
  it('anyone may read an approved merchant, signed in or not', async () => {
    const r = await as(null, () => db.query('select id from merchants where id = $1', [merchant]));
    assert.equal(r.rows.length, 1);
  });

  it('a pending merchant is not public', async () => {
    const pending = (await q(
      `insert into merchants (city_id, type, name, zone_id, phone)
       values ($1, 'restaurant', 'لسه', $2, '0100') returning id`, [edku, zone],
    )).rows[0].id;

    const r = await as(customer, () => db.query('select id from merchants where id = $1', [pending]));
    assert.equal(r.rows.length, 0);
  });

  // A policy refuses by making the row invisible to the statement, not by raising. An
  // update that matches nothing is what "no" looks like here.
  it('a customer cannot edit a merchant', async () => {
    const r = await as(customer,
      () => db.query("update merchants set name = 'مخترق' where id = $1", [merchant]));
    assert.equal(r.rowCount, 0);
  });

  it('an owner renames their own shop', async () => {
    assert.equal(
      await refused(owner, () => db.query("update merchants set name = 'اسم جديد' where id = $1",
                                          [merchant])),
      null,
    );
  });

  // A merchant that can set its own revenue model sets its own price.
  // Changed to something it is not: the guard compares old against new, so writing the
  // value a column already holds is not a change and is correctly ignored.
  it('an owner cannot set their own revenue model', async () => {
    const error = await refused(owner,
      () => db.query("update merchants set revenue_model = 'commission' where id = $1",
                     [merchant]));
    assert.match(error ?? '', /column not yours/i);
  });

  it('an owner cannot approve themselves', async () => {
    const pending = (await q(
      `insert into merchants (city_id, type, name, zone_id, phone)
       values ($1, 'restaurant', 'لسه', $2, '0100') returning id`, [edku, zone])).rows[0].id;
    const its = { uid: await uid(),
                  claims: { role: 'owner', scope: 'merchant', merchant_id: pending } };

    const error = await refused(its,
      () => db.query("update merchants set status = 'approved' where id = $1", [pending]));
    assert.match(error ?? '', /column not yours/i);
  });

  it('an owner cannot top up their own wallet', async () => {
    const error = await refused(owner,
      () => db.query('update merchants set wallet_balance = 999999 where id = $1', [merchant]));
    assert.match(error ?? '', /column not yours/i);
  });

  it('an owner cannot rename somebody else\'s shop', async () => {
    const r = await as(owner, () => db.query(
      "update merchants set name = 'مسروق' where id = $1", [otherMerchant]));
    assert.equal(r.rowCount, 0, 'the row must not even be visible to the update');
  });
});

describe('menu items', () => {
  let item, otherItem;

  beforeEach(async () => {
    item = (await q(
      `insert into menu_items (merchant_id, name, price) values ($1, 'فراخ', 12000)
       returning id`, [merchant])).rows[0].id;
    otherItem = (await q(
      `insert into menu_items (merchant_id, name, price) values ($1, 'كبدة', 9000)
       returning id`, [otherMerchant])).rows[0].id;
  });

  it('an owner edits their own item', async () => {
    const r = await as(owner,
      () => db.query('update menu_items set price = 13000 where id = $1', [item]));
    assert.equal(r.rowCount, 1);
  });

  // The Firestore rule read the merchantId being *written* rather than the one already
  // there, so rewriting it to your own turned another shop's dish into yours.
  it('an owner cannot claim an item belonging to another', async () => {
    const r = await as(owner, () => db.query(
      'update menu_items set merchant_id = $1 where id = $2', [merchant, otherItem]));
    assert.equal(r.rowCount, 0);
  });

  it('an owner cannot give their own item away', async () => {
    const error = await refused(owner, () => db.query(
      'update menu_items set merchant_id = $1 where id = $2', [otherMerchant, item]));
    assert.ok(error, 'the result has to stay theirs');
  });

  // `allow write` covered delete, and on a delete there is no incoming document — so the
  // rule threw and refused every merchant, letting only the admin through. A menu nobody
  // could take a dish out of.
  it('an owner deletes their own item', async () => {
    const r = await as(owner, () => db.query('delete from menu_items where id = $1', [item]));
    assert.equal(r.rowCount, 1);
  });

  it('an owner cannot delete an item belonging to another', async () => {
    const r = await as(owner, () => db.query('delete from menu_items where id = $1', [otherItem]));
    assert.equal(r.rowCount, 0);
  });

  it('anyone may read a menu', async () => {
    const r = await as(null, () => db.query('select id from menu_items where id = $1', [item]));
    assert.equal(r.rows.length, 1);
  });
});

describe('moving an order through its states', () => {
  const makeOrder = async (extra = {}) => (await q(
    `insert into orders (city_id, customer_uid, customer_name, customer_phone, merchant_id,
                         merchant_name, zone_id, type, items, pricing, status, delivery_by,
                         courier_uid)
     values ($1, $2, 'عميل', '0100', $3, 'مطعم', $4, 'instant', '[]'::jsonb,
             '{"total":13000}'::jsonb, $5, $6, $7) returning id`,
    [edku, extra.customerUid ?? customer.uid, extra.merchantId ?? merchant, zone,
     extra.status ?? 'placed', extra.deliveryBy ?? 'merchant', extra.courierUid ?? null],
  )).rows[0].id;

  const move = (who, id, status) =>
    refused(who, () => db.query('update orders set status = $2 where id = $1', [id, status]));

  describe('the merchant', () => {
    it('accepts an order that was just placed', async () => {
      assert.equal(await move(owner, await makeOrder(), 'accepted'), null);
    });

    it('starts cooking one they accepted', async () => {
      assert.equal(await move(owner, await makeOrder({ status: 'accepted' }), 'preparing'), null);
    });

    it('sends out one that is cooked', async () => {
      assert.equal(
        await move(owner, await makeOrder({ status: 'preparing' }), 'outForDelivery'), null);
    });

    // The transition that moves money. `on_order_delivered` will fire on it and spend a
    // prepaid wallet or accrue a commission, so an order must reach it through a courier
    // rather than by a merchant writing the word.
    it('cannot jump a fresh order straight to delivered', async () => {
      const error = await move(owner, await makeOrder(), 'delivered');
      assert.match(error ?? '', /may not move an order/);
    });

    it('cannot mark one delivered at all', async () => {
      const error = await move(owner, await makeOrder({ status: 'preparing' }), 'delivered');
      assert.match(error ?? '', /may not move an order/);
    });

    it('cannot cancel one that is already on the road', async () => {
      const error = await move(owner, await makeOrder({ status: 'outForDelivery' }), 'cancelled');
      assert.match(error ?? '', /may not move an order/);
    });

    it('cannot reopen a delivered order', async () => {
      const error = await move(owner, await makeOrder({ status: 'delivered' }), 'preparing');
      assert.match(error ?? '', /is finished/);
    });

    it('cannot revive a cancelled one', async () => {
      const error = await move(owner, await makeOrder({ status: 'cancelled' }), 'accepted');
      assert.match(error ?? '', /is finished/);
    });

    it('cannot touch another merchant\'s order', async () => {
      const theirs = await makeOrder({ merchantId: otherMerchant });
      const r = await as(owner,
        () => db.query("update orders set status = 'accepted' where id = $1", [theirs]));
      assert.equal(r.rowCount, 0);
    });

    // A merchant naming anyone as courier hands that person read and write over the
    // order, and the cash on it.
    it('cannot hand the order to somebody who is not their courier', async () => {
      const id = await makeOrder({ status: 'preparing' });
      const error = await refused(owner, () => db.query(
        'update orders set courier_uid = $2 where id = $1', [id, otherCustomer.uid]));
      assert.ok(error, 'only a courier writes their own name');
    });
  });

  describe('the courier', () => {
    it('takes out an order that is cooked, under their own name', async () => {
      const id = await makeOrder({ status: 'preparing' });
      assert.equal(
        await refused(courier, () => db.query(
          "update orders set status = 'outForDelivery', courier_uid = $2 where id = $1",
          [id, courier.uid])),
        null,
      );
    });

    it('marks one they are carrying as delivered', async () => {
      const id = await makeOrder({ status: 'outForDelivery', courierUid: courier.uid });
      assert.equal(await move(courier, id, 'delivered'), null);
    });

    // Nobody cooked it. Marking it delivered would charge the merchant for an order that
    // never left the kitchen.
    it('cannot mark a freshly placed order delivered', async () => {
      const error = await move(courier, await makeOrder(), 'delivered');
      assert.match(error ?? '', /may not move an order|is finished/);
    });

    it('cannot accept an order on the merchant\'s behalf', async () => {
      const error = await move(courier, await makeOrder(), 'accepted');
      assert.match(error ?? '', /may not move an order/);
    });

    // Cash: whoever marks it delivered is saying the money changed hands, and in a shop
    // with two riders that has to be the one holding the bag.
    it('another courier cannot take an order off the one carrying it', async () => {
      const second = { uid: await uid(),
                       claims: { role: 'courier', scope: 'merchant', merchant_id: merchant } };
      const id = await makeOrder({ status: 'outForDelivery', courierUid: courier.uid });

      const r = await as(second, () => db.query(
        "update orders set status = 'delivered' where id = $1", [id]));
      assert.equal(r.rowCount, 0);
    });

    it('the platform courier sees work the platform delivers', async () => {
      const id = await makeOrder({ status: 'preparing', deliveryBy: 'platform' });
      const r = await as(platformCourier,
        () => db.query('select id from orders where id = $1', [id]));
      assert.equal(r.rows.length, 1);
    });

    it("the platform courier cannot read a merchant's own deliveries", async () => {
      const id = await makeOrder({ status: 'preparing', merchantId: otherMerchant });
      const r = await as(platformCourier,
        () => db.query('select id from orders where id = $1', [id]));
      assert.equal(r.rows.length, 0);
    });
  });

  describe('the customer', () => {
    it('cancels while it is still unanswered', async () => {
      assert.equal(await move(customer, await makeOrder(), 'cancelled'), null);
    });

    it('cannot cancel once the kitchen has started', async () => {
      const error = await move(customer, await makeOrder({ status: 'preparing' }), 'cancelled');
      assert.match(error ?? '', /may not move an order/);
    });

    it('cannot mark their own order delivered', async () => {
      const error = await move(customer, await makeOrder({ status: 'outForDelivery' }), 'delivered');
      assert.match(error ?? '', /may not move an order/);
    });

    it('cannot read somebody else\'s order', async () => {
      const id = await makeOrder();
      const r = await as(otherCustomer, () => db.query('select id from orders where id = $1', [id]));
      assert.equal(r.rows.length, 0);
    });

    it('cannot rewrite the price', async () => {
      const id = await makeOrder();
      const error = await refused(customer, () => db.query(
        `update orders set pricing = '{"total":1}'::jsonb where id = $1`, [id]));
      assert.match(error ?? '', /permission denied|column/i);
    });
  });
});

describe('promotions', () => {
  const makePromotion = async (status) => (await q(
    `insert into promotions (city_id, merchant_id, channel, status, start_at, end_at,
                             requested_by)
     values ($1, $2, 'homeBanner', $3, now() - interval '1 day', now() + interval '30 days', $4)
     returning id`, [edku, merchant, status, owner.uid])).rows[0].id;

  // The query the customer app actually makes. A policy that allows less than the query
  // asks for returns nothing rather than less — which is how the entire feature shipped
  // invisible to every customer in the city.
  it('a customer can run the live-promotions query the app runs', async () => {
    const approved = await makePromotion('approved');
    const r = await as(customer, () => db.query(
      "select id from promotions where city_id = $1 and status = any(array['approved','active'])",
      [edku]));
    assert.ok(r.rows.some((row) => row.id === approved));
  });

  it('one still waiting for approval is not public', async () => {
    const waiting = await makePromotion('requested');
    const r = await as(customer, () => db.query('select id from promotions where id = $1',
                                                [waiting]));
    assert.equal(r.rows.length, 0);
  });

  it('the merchant who asked sees their own while it waits', async () => {
    const waiting = await makePromotion('requested');
    const r = await as(owner, () => db.query('select id from promotions where id = $1', [waiting]));
    assert.equal(r.rows.length, 1);
  });

  it('a merchant may ask', async () => {
    assert.equal(
      await refused(owner, () => db.query(
        `insert into promotions (city_id, merchant_id, channel, status, start_at, end_at,
                                 requested_by)
         values ($1, $2, 'homeBanner', 'requested', now(), now() + interval '7 days', $3)`,
        [edku, merchant, owner.uid])),
      null,
    );
  });

  // The asymmetry the whole feature rests on: a merchant who could approve their own
  // placement could put unmoderated push on every phone in the city.
  it('a merchant may not approve their own', async () => {
    const error = await refused(owner, () => db.query(
      `insert into promotions (city_id, merchant_id, channel, status, start_at, end_at,
                               requested_by)
       values ($1, $2, 'homeBanner', 'approved', now(), now() + interval '7 days', $3)`,
      [edku, merchant, owner.uid]));
    assert.ok(error);
  });

  it('a merchant may not approve one already requested', async () => {
    const waiting = await makePromotion('requested');
    const r = await as(owner, () => db.query(
      "update promotions set status = 'approved' where id = $1", [waiting]));
    assert.equal(r.rowCount, 0);
  });
});

describe('ratings', () => {
  const deliveredOrder = async (who = customer, m = merchant) => (await q(
    `insert into orders (city_id, customer_uid, customer_name, customer_phone, merchant_id,
                         merchant_name, zone_id, type, items, pricing, status)
     values ($1, $2, 'ع', '0100', $3, 'م', $4, 'instant', '[]'::jsonb, '{}'::jsonb,
             'delivered') returning id`,
    [edku, who.uid, m, zone])).rows[0].id;

  it('a customer rates an order they received', async () => {
    const order = await deliveredOrder();
    assert.equal(
      await refused(customer, () => db.query(
        'insert into ratings (order_id, merchant_id, customer_uid, stars) values ($1, $2, $3, 5)',
        [order, merchant, customer.uid])),
      null,
    );
  });

  // Without this a merchant's average is anybody's to move, from anywhere, for nothing.
  it('cannot rate a merchant they never ordered from', async () => {
    const order = await deliveredOrder(otherCustomer);
    const error = await refused(customer, () => db.query(
      'insert into ratings (order_id, merchant_id, customer_uid, stars) values ($1, $2, $3, 1)',
      [order, merchant, customer.uid]));
    assert.ok(error);
  });

  it('cannot rate an order that has not arrived', async () => {
    const order = (await q(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone, merchant_id,
                           merchant_name, zone_id, type, items, pricing, status)
       values ($1, $2, 'ع', '0100', $3, 'م', $4, 'instant', '[]'::jsonb, '{}'::jsonb,
               'preparing') returning id`, [edku, customer.uid, merchant, zone])).rows[0].id;

    const error = await refused(customer, () => db.query(
      'insert into ratings (order_id, merchant_id, customer_uid, stars) values ($1, $2, $3, 5)',
      [order, merchant, customer.uid]));
    assert.ok(error);
  });

  it('cannot name a merchant the order was not from', async () => {
    const order = await deliveredOrder();
    const error = await refused(customer, () => db.query(
      'insert into ratings (order_id, merchant_id, customer_uid, stars) values ($1, $2, $3, 5)',
      [order, otherMerchant, customer.uid]));
    assert.ok(error);
  });
});

describe('who can read the staff list', () => {
  // `belongs_to_merchant` is true for an owner *and* for their courier — they carry the
  // same merchant. It is the distinction the first audit found in the order rules and
  // the menu rules, and the staff policy still had it: a courier could read every
  // account under their shop, names and phone numbers included.
  //
  // A courier manages nobody. Their own row is the whole of what they need.
  before(async () => {
    await q("insert into staff (uid, scope, role, merchant_id) " +
            "values ($1, 'merchant', 'owner', $2) on conflict (uid) do nothing",
            [owner.uid, merchant]);
    await q("insert into staff (uid, scope, role, merchant_id) " +
            "values ($1, 'merchant', 'courier', $2) on conflict (uid) do nothing",
            [courier.uid, merchant]);
    await q("insert into staff (uid, scope, role, merchant_id) " +
            "values ($1, 'merchant', 'owner', $2) on conflict (uid) do nothing",
            [otherOwner.uid, otherMerchant]);
  });

  // Named rather than counted: earlier groups in this file leave staff rows against the
  // same merchant, and an exact total would fail for their reasons rather than this one.
  it('an owner reads the accounts under their own shop', async () => {
    const r = await as(owner, () => db.query(
      'select uid from staff where merchant_id = $1', [merchant]));
    const seen = r.rows.map((row) => row.uid);

    assert.ok(seen.includes(owner.uid), 'their own row');
    assert.ok(seen.includes(courier.uid), 'and the courier under them');
  });

  // The tightening. A courier reading the roster learns the owner's phone number and
  // every other rider's, for a screen they do not have and a job that does not need it.
  it('a courier reads only themselves', async () => {
    const r = await as(courier, () => db.query(
      'select uid from staff where merchant_id = $1', [merchant]));

    assert.equal(r.rows.length, 1);
    assert.equal(r.rows[0].uid, courier.uid);
  });

  it('an owner cannot read another shop\'s accounts', async () => {
    const r = await as(owner, () => db.query(
      'select uid from staff where merchant_id = $1', [otherMerchant]));
    assert.equal(r.rows.length, 0);
  });

  it('a customer reads no staff at all', async () => {
    const r = await as(customer, () => db.query('select uid from staff'));
    assert.equal(r.rows.length, 0);
  });

  it('an admin reads all of it', async () => {
    const r = await as(admin, () => db.query(
      'select uid from staff where merchant_id is not null'));
    assert.ok(r.rows.length >= 3);
  });

  // Only an admin issues an account, because a claim is what the policies read and a
  // merchant able to write one could grant itself anything.
  it('an owner cannot add an account to their own shop', async () => {
    const stranger = await uid();
    const error = await refused(owner, () => db.query(
      "insert into staff (uid, scope, role, merchant_id) " +
      "values ($1, 'merchant', 'courier', $2)", [stranger, merchant]));
    assert.ok(error, 'accounts are the admin\'s to create');
  });
});

describe('what is deliberately unreadable', () => {
  // A readable coupons table is one anybody can enumerate — every merchant-specific code
  // and every campaign that has not launched yet.
  it('no client can read coupons', async () => {
    await q(`insert into coupons (code, city_id, type, value, max_discount)
             values ('SECRET', $1, 'percentage', 1500, 3000)`, [edku]);

    const r = await as(customer, () => db.query('select id from coupons'));
    assert.equal(r.rows.length, 0);
  });

  it('the admin can', async () => {
    const r = await as(admin, () => db.query('select id from coupons where city_id = $1', [edku]));
    assert.ok(r.rows.length >= 1);
  });

  it('no client can read the audit log', async () => {
    const r = await as(owner, () => db.query('select id from audit_log'));
    assert.equal(r.rows.length, 0);
  });

  // Append-only, including for an admin. A log its own subject can edit proves nothing.
  it('not even an admin can edit an entry', async () => {
    await q("insert into audit_log (action, actor) values ('suspendMerchant', $1)", [admin.uid]);
    const error = await refused(admin, () => db.query(
      "update audit_log set action = 'nothing happened'"));
    assert.match(error ?? '', /permission denied/i);
  });
});

describe('users', () => {
  it('a customer edits their own name', async () => {
    assert.equal(
      await refused(customer,
        () => db.query("update users set name = 'اسمي' where id = $1", [customer.uid])),
      null,
    );
  });

  // Unblocking yourself or resetting your own refusal count would make the whole abuse
  // defence decorative. Both start in the state that makes the attempt a real change:
  // asking whether `false` may be written over `false` proves nothing.
  it('a customer cannot unblock themselves', async () => {
    const blocked = { uid: await uid(), claims: {} };
    // `ensure_user_profile` on auth.users already made the row, so this sets the state
    // rather than creating it — and sets it as the server, because a client cannot.
    await asServer('update users set is_blocked = true where id = $1', [blocked.uid]);

    const error = await refused(blocked,
      () => db.query('update users set is_blocked = false where id = $1', [blocked.uid]));
    assert.match(error ?? '', /column not yours/i);

    const still = await q('select is_blocked from users where id = $1', [blocked.uid]);
    assert.equal(still.rows[0].is_blocked, true);
  });

  it('a customer cannot reset their own refusal count', async () => {
    const refuser = { uid: await uid(), claims: {} };
    await asServer('update users set rejected_orders_count = 3 where id = $1',
                   [refuser.uid]);

    const error = await refused(refuser,
      () => db.query('update users set rejected_orders_count = 0 where id = $1', [refuser.uid]));
    assert.match(error ?? '', /column not yours/i);
  });

  it('a customer cannot read another customer', async () => {
    const r = await as(customer,
      () => db.query('select id from users where id = $1', [otherCustomer.uid]));
    assert.equal(r.rows.length, 0);
  });
});

describe('uploading an image', () => {
  it('the uploader is recorded as the person uploading', async () => {
    assert.equal(
      await refused(customer, () => db.query(
        `insert into media (kind, url, status, uploaded_by)
         values ('menuItem', 'x.jpg', 'pending', $1)`, [customer.uid])),
      null,
    );
  });

  // Otherwise an upload can be filed under somebody else's name, and read by them.
  it('cannot be filed under another name', async () => {
    const error = await refused(customer, () => db.query(
      `insert into media (kind, url, status, uploaded_by)
       values ('menuItem', 'x.jpg', 'pending', $1)`, [otherCustomer.uid]));
    assert.ok(error);
  });

  // An uploader approving their own upload is the gate with a hole in it.
  it('cannot arrive already approved', async () => {
    const error = await refused(customer, () => db.query(
      `insert into media (kind, url, status, uploaded_by)
       values ('menuItem', 'x.jpg', 'approved', $1)`, [customer.uid]));
    assert.ok(error);
  });

  it('only an admin moves an image out of pending', async () => {
    const id = (await q(
      `insert into media (kind, url, status, uploaded_by)
       values ('menuItem', 'x.jpg', 'pending', $1) returning id`, [customer.uid])).rows[0].id;

    const byUploader = await as(customer,
      () => db.query("update media set status = 'approved' where id = $1", [id]));
    assert.equal(byUploader.rowCount, 0);

    const byAdmin = await as(admin,
      () => db.query("update media set status = 'approved' where id = $1", [id]));
    assert.equal(byAdmin.rowCount, 1);
  });
});

/// The account a customer signs up with, and what the rest of the system learns from it.
///
/// A customer's identity is their phone number, but GoTrue's phone identity needs an SMS
/// provider — so the number is folded into a synthetic address and the real one travels
/// in the signup metadata. `ensure_user_profile` is what lands it on the `users` row,
/// and `users.phone` is what `place_order` copies onto an order: get this wrong and the
/// courier arrives at the right door with nobody to call.
describe('a customer signing up with a phone number', () => {
  /// Creates an auth account the way GoTrue does at sign-up, metadata and all.
  const signUp = async (email, meta) => (await q(
    "insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) " +
    "values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', " +
    "'authenticated', $1, $2) returning id",
    [email, JSON.stringify(meta)],
  )).rows[0].id;

  // A fresh number per run: these rows are committed, not rolled back, and a fixed
  // address would collide with its own previous run.
  const someNumber = () =>
    '010' + String(Date.now() % 100000000).padStart(8, '0');

  it('arrives on the users row with their name and number', async () => {
    const phone = someNumber();
    const id = await signUp(`${phone}@phone.luqma.app`,
                            { name: 'أحمد محمود', phone });

    const row = (await q('select name, phone from users where id = $1', [id])).rows[0];
    assert.equal(row.phone, phone,
                 'the courier calls this number — it has to be the one they typed');
    assert.equal(row.name, 'أحمد محمود');
  });

  // A staff account is made by an admin with neither, and must still get its row.
  it('an account with no metadata still gets a row', async () => {
    const id = await signUp(`staff-${Date.now()}@luqma.app`, {});

    const row = (await q('select id, phone from users where id = $1', [id])).rows[0];
    assert.ok(row, 'every account has a profile row, metadata or not');
    assert.equal(row.phone, null);
  });
});
