import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A platform order is never delivered without a courier on it.
 *
 * MerchantApp's live board offered the owner «خرج للتوصيل» from `preparing` on every order,
 * and the transitions allowed it. On a platform order that move writes only the status —
 * and `markOnTheWay`, the one path that puts a rider's name on the order, starts from
 * `preparing`, so once the shop had tapped it no rider could take the order any more. Any
 * platform courier could still deliver an order with nobody on it, `markDelivered` never
 * writes `courier_uid`, and the settlement read the null as "the shop delivered": a zero
 * row, nothing on any rider's statement, and nobody on record holding the cash.
 *
 * Everything below runs as `authenticated`, the role a phone speaks as, because PGlite's
 * owner is a superuser and the guards ask which role is writing.
 */
describe('a platform order is carried by somebody', () => {
  const OWNER = '00000000-0000-0000-0000-0000000000c1';
  const RIDER = '00000000-0000-0000-0000-0000000000c2';
  const ADMIN = '00000000-0000-0000-0000-0000000000c3';

  let db, zone, shop;

  const as = (uid, claims) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  // The claims the hook actually mints for each.
  const admin = () => as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
  const owner = () => as(OWNER, { role: 'owner', scope: 'merchant', merchant_id: shop });
  const rider = () => as(RIDER, { role: 'courier', scope: 'platform' });

  const rows = async (sql, params) => (await db.query(sql, params)).rows;

  /** Statements as the role a phone speaks as, rolled back afterwards. */
  async function asPhone(fn) {
    await db.exec('begin; set local role authenticated;');
    try {
      return await fn();
    } finally {
      await db.exec('rollback');
    }
  }

  /** The state machine's own refusal, which is a check violation rather than a grant. */
  const refused = (message) => (error) => {
    assert.equal(error.code, '23514',
      `expected the transition refused, got ${error.code}: ${error.message}`);
    if (message) assert.match(error.message, new RegExp(message));
    return true;
  };

  /** An order at `status`, put there the way the server would. */
  const orderAt = async (status, { deliveryBy = 'platform', courier = null } = {}) => {
    const id = (await rows(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                           merchant_id, merchant_name, zone_id, type, items, pricing,
                           status, delivery_by)
       values ('edku', null, 'عميل', '01000000000', $1, 'مطعم التوصيل', $2, 'instant',
               '[]', '{"subtotal":10000,"deliveryFee":2000,"total":12000}', 'placed', $3)
       returning id`, [shop, zone, deliveryBy]))[0].id;
    await db.exec(`do $$ begin
      perform set_config('app.server_mode','on',true);
      update public.orders
         set status = '${status}',
             courier_uid = ${courier ? `'${courier}'` : 'null'}
       where id = '${id}';
    end $$;`);
    return id;
  };

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${OWNER}'), ('${RIDER}'), ('${ADMIN}');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;`);
    zone = (await rows(
      `insert into zones (city_id, name, default_delivery_fee)
       values ('edku', 'الزغبي', 2000) returning id`))[0].id;
    shop = (await rows(
      `insert into merchants (city_id, type, name, zone_id, phone, status)
       values ('edku', 'restaurant', 'مطعم التوصيل', $1, '0100', 'approved')
       returning id`, [zone]))[0].id;
    // `staff_attach_initial_courier` gives the platform rider the platform row.
    await db.query(
      `insert into staff (uid, scope, role, merchant_id, is_active) values
         ($1, 'merchant', 'owner', $2, true),
         ($3, 'platform', 'courier', null, true),
         ($4, 'platform', 'admin', null, true)`,
      [OWNER, shop, RIDER, ADMIN]);
  });

  after(async () => { await db?.close(); });

  beforeEach(async () => {
    await db.exec(`
      delete from courier_settlements;
      delete from order_settlements;
      delete from orders;
      update config set value = '10'::jsonb where key = 'courier_commission_percent';`);
    await admin();
  });

  describe('the shop', () => {
    it('may not send a platform order out', async () => {
      const id = await orderAt('preparing');
      await owner();

      await assert.rejects(
        () => asPhone(() => db.query(
          `update orders set status = 'outForDelivery' where id = $1`, [id])),
        refused('courier'));
    });

    it('still sends out an order its own rider carries', async () => {
      const id = await orderAt('preparing', { deliveryBy: 'merchant' });
      await owner();

      const status = await asPhone(async () => (await rows(
        `update orders set status = 'outForDelivery' where id = $1 returning status`,
        [id]))[0].status);

      assert.equal(status, 'outForDelivery');
    });
  });

  describe('delivering it', () => {
    it('refuses a courier delivering a platform order nobody took', async () => {
      // Out with nobody on it: the state an order was left in by the shop's tap before
      // this migration, and the one a rider could then deliver anonymously.
      const id = await orderAt('outForDelivery');
      await rider();

      await assert.rejects(
        () => asPhone(() => db.query(
          `update orders set status = 'delivered', delivered_at = now() where id = $1`,
          [id])),
        refused('courier'));
    });

    it('refuses a courier taking their own name off in the same breath', async () => {
      const id = await orderAt('outForDelivery', { courier: RIDER });
      await rider();

      await assert.rejects(
        () => asPhone(() => db.query(
          `update orders set status = 'delivered', delivered_at = now(), courier_uid = null
            where id = $1`, [id])),
        refused('courier'));
    });

    // Not excepted: nothing in AdminApp moves an order to `delivered`, and an admin who
    // wanted to would be settling a delivery nobody is on record as having made.
    it('refuses a platform admin delivering one nobody took', async () => {
      const id = await orderAt('outForDelivery');
      await admin();

      await assert.rejects(
        () => asPhone(() => db.query(
          `update orders set status = 'delivered', delivered_at = now() where id = $1`,
          [id])),
        refused('courier'));
    });

    // The rule is about the row as it will be. Judged on the row as it was, an admin could
    // turn a shop's order into a platform one and deliver it in one statement: the check
    // saw a merchant order, the admin's exit let it through, and the settlement recorded
    // `merchantDelivery` at zero on a platform order nobody carried.
    it('refuses an admin making it a platform order and delivering it at once', async () => {
      const id = await orderAt('outForDelivery', { deliveryBy: 'merchant' });
      await admin();

      await assert.rejects(
        () => asPhone(() => db.query(
          `update orders set delivery_by = 'platform', status = 'delivered',
                             delivered_at = now()
            where id = $1`, [id])),
        refused('courier'));
    });

    it('carries the normal path through, and charges the rider who carried it', async () => {
      const id = await orderAt('preparing');
      await rider();

      const settled = await asPhone(async () => {
        // `markOnTheWay`: the status and the name in one update.
        await db.query(
          `update orders set status = 'outForDelivery', courier_uid = $2 where id = $1`,
          [id, RIDER]);
        // `markDelivered`: the status alone, the name already there.
        await db.query(
          `update orders set status = 'delivered', delivered_at = now() where id = $1`,
          [id]);
        return (await rows(
          `select s.courier_uid, s.ground, s.amount
             from courier_settlements s where s.order_id = $1`, [id]))[0];
      });

      assert.deepEqual(settled, { courier_uid: RIDER, ground: 'platform', amount: 200 });
    });
  });
});
