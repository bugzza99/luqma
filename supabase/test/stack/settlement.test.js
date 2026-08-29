import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * Revenue settlement on delivery.
 *
 * The product spent eight phases recording what it would charge and charging nothing:
 * `wallet_balance` was only ever added to, `commission_owed` had never been written by
 * anything, and `pricing.platformOwesMerchant` was computed, frozen onto the order, and
 * read by no statement anywhere. `onOrderDelivered` left with Firebase.
 *
 * Against the real stack rather than PGlite because every question here is about a
 * trigger, a transition and a `security definer` boundary — the arithmetic on its own is
 * in `test/local/settlement_arithmetic.test.js`.
 *
 * The one that matters most is idempotence. A trigger inside the status transaction
 * cannot be *missed*; it can still run twice, and the difference between those two
 * sentences is a merchant charged twice for one order.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

const uid = async () => (await q(
  "insert into auth.users (id, instance_id, aud, role) values (gen_random_uuid(), " +
  "'00000000-0000-0000-0000-000000000000','authenticated','authenticated') returning id",
)).rows[0].id;

describe('settling a delivered order', () => {
  let city, zone, customer, admin, courier;

  /** A merchant on given terms, with a wallet. */
  const makeMerchant = async ({ model = 'subscription', value = 0, wallet = 0 } = {}) =>
    (await q(
      `insert into merchants (city_id, type, name, zone_id, phone, status,
                              revenue_model, revenue_value, wallet_balance)
       values ($1,'restaurant','مطعم',$2,'0100','approved',$3,$4,$5) returning id`,
      [city, zone, model, value, wallet])).rows[0].id;

  /**
   * An order sitting at `outForDelivery`, with the terms already frozen onto it the way
   * `place_order` freezes them.
   *
   * Inserted at that status rather than walked there from `placed`: what is under test
   * is the last transition, and the four before it have their own tests in `rls.test.js`.
   */
  const makeOrder = async (merchantId, {
    model = 'subscription', value = 0, subtotal = 20000, owes = 0,
    status = 'outForDelivery', courierUid = null, deliveryBy = 'merchant',
  } = {}) => (await q(
    `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                         merchant_id, merchant_name, zone_id, type, items, pricing,
                         revenue, status, courier_uid, delivery_by)
     values ($1,$2,'عميل','01000000000',$3,'مطعم',$4,'instant','[]'::jsonb,
             $5::jsonb, $6::jsonb, $7, $8, $9) returning id`,
    [city, customer, merchantId, zone,
     JSON.stringify({ subtotal, deliveryFee: 1000, total: subtotal + 1000,
                      platformOwesMerchant: owes }),
     JSON.stringify({ model, value, amount: 0 }),
     status, courierUid, deliveryBy])).rows[0].id;

  /**
   * Moves an order as the platform would. `app.server_mode` stands the transition and
   * column guards down — this suite is about what happens *after* they have spoken, and
   * who is allowed to speak is `rls.test.js`.
   */
  const deliver = async (orderId, status = 'delivered') => {
    await q('begin');
    await q("select set_config('app.server_mode','on',true)");
    await q('update orders set status = $2 where id = $1', [orderId, status]);
    await q('commit');
  };

  /**
   * Edits a fixture the way a server function would.
   *
   * `pricing` and `revenue` are behind `guard_order_columns` and belong to nobody with a
   * token — which is correct, and means a test that adjusts one has to say it is the
   * server, exactly as `place_order` does.
   */
  const asServer = async (sql, params) => {
    await q('begin');
    try {
      await q("select set_config('app.server_mode','on',true)");
      await q(sql, params);
      await q('commit');
    } catch (e) { await q('rollback'); throw e; }
  };

  const merchantRow = async (id) => (await q(
    'select wallet_balance, commission_owed from merchants where id=$1', [id])).rows[0];

  const settlement = async (orderId) => (await q(
    'select * from order_settlements where order_id=$1', [orderId])).rows[0];

  const takenOnOrder = async (orderId) => Number((await q(
    "select revenue ->> 'amount' as a from orders where id=$1", [orderId])).rows[0].a);

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = 'settle-' + Date.now();
    await q('insert into cities (id,name) values ($1,$2)', [city, 'مدينة التسوية']);
    zone = (await q('insert into zones (city_id,name) values ($1,$2) returning id',
                    [city, 'منطقة'])).rows[0].id;
    customer = await uid();
    await q('insert into users (id) values ($1) on conflict (id) do nothing', [customer]);
    admin = await uid();
    await q("insert into staff (uid,scope,role) values ($1,'platform','admin')", [admin]);
    courier = await uid();
    await q("insert into staff (uid,scope,role) values ($1,'platform','courier')", [courier]);
  });

  after(async () => {
    for (const sql of [
      'delete from order_settlements where merchant_id in (select id from merchants where city_id=$1)',
      'delete from orders where city_id = $1',
      'delete from merchants where city_id = $1',
      'delete from zones where city_id = $1',
      'delete from cities where id = $1',
    ]) await q(sql, [city]).catch((e) => console.error('teardown:', e.message));
    await q('delete from staff where uid = any($1)', [[admin, courier]]).catch(() => {});
    await q('delete from users where id = $1', [customer]).catch(() => {});
    await db.end();
  });

  // ------------------------------------------------------------------ the models

  describe('commission', () => {
    it('accrues what the frozen rate says, on the food', async () => {
      const m = await makeMerchant({ model: 'commission', value: 1000 });
      // 200 EGP of food and 10 EGP of delivery. The cut is on the food: 20 EGP, not 21.
      const o = await makeOrder(m, { model: 'commission', value: 1000, subtotal: 20000 });

      await deliver(o);

      assert.equal((await merchantRow(m)).commission_owed, 2000);
      assert.equal((await settlement(o)).basis, 20000, 'the basis is the food alone');
    });

    // The delivery fee is not the platform's to take a share of. When the platform
    // delivers, the fee is already the platform's and the merchant never sees it; when
    // the merchant delivers, it is fuel and a driver rather than a margin. It survives
    // one sentence in a shop, which in a cash market is worth more than the piastres.
    it('never on the delivery fee, however large it is', async () => {
      const m = await makeMerchant({ model: 'commission', value: 1000 });
      const o = await makeOrder(m, { model: 'commission', value: 1000, subtotal: 20000 });
      await asServer("update orders set pricing = pricing || '{\"deliveryFee\":50000}'::jsonb " +
                     'where id=$1', [o]);

      await deliver(o);

      assert.equal((await merchantRow(m)).commission_owed, 2000);
    });

    it('leaves the wallet alone', async () => {
      const m = await makeMerchant({ model: 'commission', value: 1000, wallet: 5000 });
      await deliver(await makeOrder(m, { model: 'commission', value: 1000 }));

      assert.equal((await merchantRow(m)).wallet_balance, 5000);
    });
  });

  describe('prepaid', () => {
    it('takes the flat fee out of the wallet', async () => {
      const m = await makeMerchant({ model: 'prepaid', value: 500, wallet: 2000 });
      await deliver(await makeOrder(m, { model: 'prepaid', value: 500 }));

      assert.equal((await merchantRow(m)).wallet_balance, 1500);
    });

    // The point of prepaid, and the reason `place_order` checks the balance before every
    // order: the platform stops carrying a merchant who has run out rather than accruing
    // a debt nobody will settle. That check was reading a number nothing ever lowered.
    it('and the balance actually runs out, which is the whole point', async () => {
      const m = await makeMerchant({ model: 'prepaid', value: 500, wallet: 1000 });
      await deliver(await makeOrder(m, { model: 'prepaid', value: 500 }));
      await deliver(await makeOrder(m, { model: 'prepaid', value: 500 }));

      assert.equal((await merchantRow(m)).wallet_balance, 0);
      // `acceptsOrdersAt` and `place_order` both answer no from here.
      const r = await q('select wallet_balance < revenue_value as spent from merchants ' +
                        'where id=$1', [m]);
      assert.equal(r.rows[0].spent, true);
    });

    it('does not touch commission_owed', async () => {
      const m = await makeMerchant({ model: 'prepaid', value: 500, wallet: 2000 });
      await deliver(await makeOrder(m, { model: 'prepaid', value: 500 }));

      assert.equal((await merchantRow(m)).commission_owed, 0);
    });
  });

  describe('subscription', () => {
    it('takes nothing from either', async () => {
      const m = await makeMerchant({ model: 'subscription', wallet: 3000 });
      await deliver(await makeOrder(m));

      const row = await merchantRow(m);
      assert.equal(row.wallet_balance, 3000);
      assert.equal(row.commission_owed, 0);
    });

    // A row even at zero. An audit trail with the uninteresting entries left out is one
    // nobody can count, and "how many orders did this shop deliver" is the first
    // question anybody asks of it.
    it('still leaves a settlement row', async () => {
      const m = await makeMerchant({ model: 'subscription', wallet: 3000 });
      const o = await makeOrder(m);
      await deliver(o);

      const s = await settlement(o);
      assert.equal(s.model, 'subscription');
      assert.equal(s.amount, 0);
    });
  });

  // ------------------------------------------------------------------ idempotence

  describe('charging exactly once', () => {
    // The reason this suite exists. Atomicity is not idempotence: the transaction stops
    // a *half*-applied settlement, and does nothing at all about a whole one applied
    // twice.
    it('a second write of the same status charges nothing more', async () => {
      const m = await makeMerchant({ model: 'prepaid', value: 500, wallet: 5000 });
      const o = await makeOrder(m, { model: 'prepaid', value: 500 });

      await deliver(o);
      await deliver(o);
      await deliver(o);

      assert.equal((await merchantRow(m)).wallet_balance, 4500);
    });

    // An admin editing a neighbouring column with `status` in the SET list. The `when`
    // clause on the trigger refuses this before the function is even entered.
    it('an update that does not move the status settles nothing', async () => {
      const m = await makeMerchant({ model: 'prepaid', value: 500, wallet: 5000 });
      const o = await makeOrder(m, { model: 'prepaid', value: 500, status: 'delivered' });

      await q('begin');
      await q("select set_config('app.server_mode','on',true)");
      await q("update orders set status = 'delivered', cancel_reason = 'x' where id=$1", [o]);
      await q('commit');

      assert.equal((await merchantRow(m)).wallet_balance, 5000,
        'inserted already delivered, so it was never settled and must not be now');
      assert.equal(await settlement(o), undefined);
    });

    it('calling the function directly twice is the same as calling it once', async () => {
      const m = await makeMerchant({ model: 'commission', value: 1500, wallet: 0 });
      const o = await makeOrder(m, { model: 'commission', value: 1500, subtotal: 10000 });

      await q('select apply_order_settlement($1, true)', [o]);
      await q('select apply_order_settlement($1, true)', [o]);

      assert.equal((await merchantRow(m)).commission_owed, 1500);
    });
  });

  // ------------------------------------------------------------------ reversal

  describe('taking it back', () => {
    // An admin can move a delivered order back out of delivered. A merchant left charged
    // for an order that was cancelled afterwards will notice, and will be right.
    it('cancelling a delivered order returns what was taken', async () => {
      const m = await makeMerchant({ model: 'prepaid', value: 500, wallet: 5000 });
      const o = await makeOrder(m, { model: 'prepaid', value: 500 });

      await deliver(o);
      assert.equal((await merchantRow(m)).wallet_balance, 4500);

      await deliver(o, 'cancelled');

      assert.equal((await merchantRow(m)).wallet_balance, 5000);
      assert.notEqual((await settlement(o)).reversed_at, null);
      assert.equal(await takenOnOrder(o), 0);
    });

    // "Charged and then returned" and "never charged" are different answers, and only
    // one of them is something a merchant should have to be told about.
    it('and the row stays, marked, rather than disappearing', async () => {
      const m = await makeMerchant({ model: 'commission', value: 1000 });
      const o = await makeOrder(m, { model: 'commission', value: 1000 });

      await deliver(o);
      await deliver(o, 'cancelled');

      const s = await settlement(o);
      assert.notEqual(s, undefined, 'the evidence is not deleted');
      assert.equal(s.amount, 2000, 'it still says what was taken');
    });

    it('reversing twice does not pay the merchant twice', async () => {
      const m = await makeMerchant({ model: 'prepaid', value: 500, wallet: 5000 });
      const o = await makeOrder(m, { model: 'prepaid', value: 500 });

      await deliver(o);
      await q('select apply_order_settlement($1, false)', [o]);
      await q('select apply_order_settlement($1, false)', [o]);

      assert.equal((await merchantRow(m)).wallet_balance, 5000);
    });

    // A charge made under terms that have since changed must be handed back at the
    // figure it was taken at, not at today's answer.
    it('returns what was taken, not what would be taken now', async () => {
      const m = await makeMerchant({ model: 'commission', value: 1000 });
      const o = await makeOrder(m, { model: 'commission', value: 1000, subtotal: 20000 });
      await deliver(o);

      // The order's snapshot is edited under it — an admin correcting a rate.
      await asServer("update orders set revenue = revenue || '{\"value\":9000}'::jsonb " +
                     'where id=$1', [o]);
      await deliver(o, 'cancelled');

      assert.equal((await merchantRow(m)).commission_owed, 0,
        'recomputing would have handed back 18000 against the 2000 taken');
    });

    it('and delivering it again charges it once more, not twice', async () => {
      const m = await makeMerchant({ model: 'prepaid', value: 500, wallet: 5000 });
      const o = await makeOrder(m, { model: 'prepaid', value: 500 });

      await deliver(o);
      await deliver(o, 'cancelled');
      await q('begin');
      await q("select set_config('app.server_mode','on',true)");
      await q("update orders set status = 'outForDelivery' where id=$1", [o]);
      await q('commit');
      await deliver(o);

      assert.equal((await merchantRow(m)).wallet_balance, 4500);
      assert.equal((await settlement(o)).reversed_at, null);
    });
  });

  // ------------------------------------------------------------------ the coupon debt

  describe('what the platform owes back', () => {
    // With cash, a discount is simply less money reaching the merchant — so a
    // platform-funded campaign is a debt from the moment the order is placed. It was
    // computed by `place_order`, frozen onto the order, and read by nothing.
    it('a platform-funded discount is recorded against the merchant', async () => {
      const m = await makeMerchant({ model: 'subscription' });
      const o = await makeOrder(m, { owes: 3000 });

      await deliver(o);

      assert.equal((await settlement(o)).platform_owes, 3000);
    });

    it('and the total is a sum over what has not been reversed', async () => {
      const m = await makeMerchant({ model: 'subscription' });
      const a = await makeOrder(m, { owes: 3000 });
      const b = await makeOrder(m, { owes: 1500 });
      await deliver(a);
      await deliver(b);
      await deliver(b, 'cancelled');

      const r = await q(
        'select coalesce(sum(platform_owes),0)::int as owed from order_settlements ' +
        'where merchant_id=$1 and reversed_at is null', [m]);
      assert.equal(r.rows[0].owed, 3000);
    });
  });

  // ------------------------------------------------------------------ the order itself

  describe('the order carries what was taken', () => {
    // `RevenueSnapshot.amount` has been documented since Phase 7 as "what was actually
    // taken, once the order was delivered" and has always been zero.
    it('the amount lands on the snapshot the phone reads', async () => {
      const m = await makeMerchant({ model: 'commission', value: 1250 });
      const o = await makeOrder(m, { model: 'commission', value: 1250, subtotal: 40000 });

      await deliver(o);

      assert.equal(await takenOnOrder(o), 5000);
    });

    it('and the terms frozen at order time are not disturbed', async () => {
      const m = await makeMerchant({ model: 'commission', value: 1250 });
      const o = await makeOrder(m, { model: 'commission', value: 1250 });
      await deliver(o);

      const r = await q("select revenue ->> 'model' as m, revenue ->> 'value' as v " +
                        'from orders where id=$1', [o]);
      assert.equal(r.rows[0].m, 'commission');
      assert.equal(r.rows[0].v, '1250');
    });
  });

  // ------------------------------------------------------------------ the real path

  describe('a courier in the street', () => {
    /**
     * The production path, and the only one that proves anything about privileges.
     *
     * Every other test here moves the order with `app.server_mode` on, which stands the
     * column guards down — and that is exactly how a real defect hid: the settlement
     * writes `merchants.wallet_balance`, which is behind `guard_columns`, and
     * `security definer` does not satisfy that guard. It asks whether a trusted server
     * function has *declared itself*, not who owns the function. So the settlement
     * worked in a suite that had already declared server mode and would have failed for
     * every courier on every delivery, with "column not yours to change on merchants".
     *
     * A courier standing at somebody's door, unable to mark an order delivered, holding
     * their cash.
     */
    const deliverAsCourier = async (orderId, courierUid) => {
      await q('begin');
      try {
        await q("select set_config('role','authenticated',true)");
        await q("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
          sub: courierUid, role: 'authenticated',
          app_metadata: { role: 'courier', scope: 'platform' },
        })]);
        await q('update orders set status = $2 where id = $1', [orderId, 'delivered']);
        await q('commit');
      } catch (e) { await q('rollback'); throw e; }
    };

    // The courier's name goes on at insert rather than by a later update, because
    // `enforce_courier_claim` does not consult `app.server_mode` — it asks only whether
    // the caller is an admin or is writing their own name. Correct for the case it was
    // written for, and it means a fixture cannot hand an order to somebody the way the
    // app does; the app has the courier claim it themselves, which `rls.test.js` covers.
    const platformOrder = (merchantId, opts) =>
      makeOrder(merchantId, { ...opts, courierUid: courier, deliveryBy: 'platform' });

    it('can mark an order delivered, and the wallet moves', async () => {
      const m = await makeMerchant({ model: 'prepaid', value: 500, wallet: 5000 });
      const o = await platformOrder(m, { model: 'prepaid', value: 500 });

      await deliverAsCourier(o, courier);

      assert.equal((await merchantRow(m)).wallet_balance, 4500);
      assert.equal((await settlement(o)).amount, 500);
    });

    // The settlement declares server mode to reach the wallet. That setting is
    // transaction-local and this runs inside the courier's transaction, so leaving it
    // standing would stand every guard down for whatever the same transaction did next.
    it('and server mode does not survive the delivery', async () => {
      const m = await makeMerchant({ model: 'prepaid', value: 500, wallet: 5000 });
      const o = await platformOrder(m, { model: 'prepaid', value: 500 });

      await q('begin');
      try {
        await q("select set_config('role','authenticated',true)");
        await q("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
          sub: courier, role: 'authenticated',
          app_metadata: { role: 'courier', scope: 'platform' },
        })]);
        await q('update orders set status = $2 where id = $1', [o, 'delivered']);

        // Read the setting rather than probing it with a write. A courier's UPDATE on
        // `merchants` is hidden by RLS whether or not server mode is on, so it comes
        // back as nought rows and no error either way — "a policy that allows less than
        // the query asks for returns nothing, not less". The write would have passed
        // this test with the leak wide open.
        const mode = (await q(
          "select coalesce(current_setting('app.server_mode', true),'') as m")).rows[0].m;
        assert.notEqual(mode, 'on',
          'the settlement left server mode standing in another transaction');

        // And nothing the settlement itself did was rolled back by putting it away.
        assert.equal((await merchantRow(m)).wallet_balance, 4500);
      } finally { await q('rollback'); }
    });
  });

  // ------------------------------------------------------------------ the boundary

  describe('who can reach the money', () => {
    // The courier does the update that triggers all of this and has no rights on
    // `merchants` at all. What moves the money is the definer function, and the only way
    // to reach it is by moving an order the transition trigger already allowed.
    it('an ordinary signed-in caller cannot settle an order by hand', async () => {
      const m = await makeMerchant({ model: 'prepaid', value: 500, wallet: 5000 });
      const o = await makeOrder(m, { model: 'prepaid', value: 500 });

      await q('begin');
      try {
        await q("select set_config('role','authenticated',true)");
        await q("select set_config('request.jwt.claims',$1,true)",
                [JSON.stringify({ sub: customer, role: 'authenticated', app_metadata: {} })]);
        await assert.rejects(
          q('select apply_order_settlement($1, true)', [o]),
          (e) => { assert.equal(e.code, '42501'); return true; },
        );
      } finally { await q('rollback'); }
    });

    it('nor can they write the ledger directly', async () => {
      const m = await makeMerchant({ model: 'prepaid', value: 500, wallet: 5000 });
      const o = await makeOrder(m, { model: 'prepaid', value: 500 });

      await q('begin');
      try {
        await q("select set_config('role','authenticated',true)");
        await q("select set_config('request.jwt.claims',$1,true)",
                [JSON.stringify({ sub: customer, role: 'authenticated', app_metadata: {} })]);
        await assert.rejects(
          q(`insert into order_settlements (order_id, merchant_id, model, basis, amount)
             values ($1,$2,'commission',0,0)`, [o, m]),
          (e) => { assert.ok(['42501'].includes(e.code), `got ${e.code}`); return true; },
        );
      } finally { await q('rollback'); }
    });
  });
});
