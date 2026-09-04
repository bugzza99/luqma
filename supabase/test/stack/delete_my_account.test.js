import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * Self-service account deletion, against the real Auth schema and transaction boundary.
 *
 * PGlite can prove the foreign key shape but not that `auth.uid()` is the only identity
 * the function accepts. This suite calls through an authenticated Postgres role and
 * checks the cascades, retained ledger and post-delete audit row in the same transaction.
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

/**
 * Runs as one real JWT identity, then rolls back so deleting an account leaves no cloud
 * residue. Assertions on cascades and triggers belong inside the callback: after the
 * rollback they would be reading the fixture from before the operation.
 */
async function as(userId, fn) {
  await q('begin');
  try {
    await q('set local role authenticated');
    await q("select set_config('request.jwt.claims', $1, true)", [
      JSON.stringify({ sub: userId, role: 'authenticated' }),
    ]);
    await fn();
    await q('rollback');
  } catch (error) {
    await q('rollback');
    throw error;
  }
}

describe('delete_my_account', () => {
  let city, zone, merchant, customer, staffAccount, address, order, activeOrder, promotion;
  let pricingBefore, settlementBefore;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = `delete-account-${Date.now()}`;
    await q('insert into cities (id, name) values ($1, $2)', [city, 'مدينة الحذف']);
    zone = (await q(
      'insert into zones (city_id, name) values ($1, $2) returning id',
      [city, 'منطقة'],
    )).rows[0].id;
    // The owner rides in on the insert. `merchants_guard_columns` fires on update only,
    // and `owner_uid` is not one of the columns it lets through — an update here would
    // fail the fixture rather than the thing under test.
    staffAccount = await makeAccount();
    merchant = (await q(
      `insert into merchants
         (city_id, type, name, zone_id, phone, status, revenue_model, revenue_value,
          owner_uid)
       values ($1, 'restaurant', 'مطعم', $2, '01000000000', 'approved',
               'commission', 1000, $3)
       returning id`,
      [city, zone, staffAccount],
    )).rows[0].id;
    await q(
      `insert into staff (uid, scope, role, merchant_id)
       values ($1, 'merchant', 'owner', $2)`,
      [staffAccount, merchant],
    );

    customer = await makeAccount();
    await q("update users set name = 'محمد', phone = '01012345678' where id = $1", [
      customer,
    ]);
    address = (await q(
      `insert into addresses (user_id, zone_id, street, label)
       values ($1, $2, 'شارع البحر', 'البيت') returning id`,
      [customer, zone],
    )).rows[0].id;
    await q('insert into device_tokens (token, uid) values ($1, $2)', [
      `delete-token-${Date.now()}`,
      customer,
    ]);

    order = (await q(
      `insert into orders
         (city_id, customer_uid, customer_name, customer_phone, merchant_id,
          merchant_name, zone_id, type, items, pricing, revenue, status)
       values
         ($1, $2, 'محمد', '01012345678', $3, 'مطعم', $4, 'instant',
          '[{"itemId":"dish-1","name":"كشري","unitPrice":15000,"quantity":1}]'::jsonb,
          '{"subtotal":15000,"deliveryFee":1000,"total":16000}'::jsonb,
          '{"model":"commission","value":1000,"amount":0}'::jsonb,
          'outForDelivery')
       returning id`,
      [city, customer, merchant, zone],
    )).rows[0].id;
    activeOrder = (await q(
      `insert into orders
         (city_id, customer_uid, customer_name, customer_phone, merchant_id,
          merchant_name, zone_id, type, items, pricing, revenue, status)
       values
         ($1, $2, 'محمد', '01012345678', $3, 'مطعم', $4, 'instant',
          '[]'::jsonb, '{"subtotal":0,"deliveryFee":0,"total":0}'::jsonb,
          '{"model":"subscription","value":0,"amount":0}'::jsonb, 'placed')
       returning id`,
      [city, customer, merchant, zone],
    )).rows[0].id;
    await q(
      'insert into ratings (order_id, merchant_id, customer_uid, stars) values ($1, $2, $3, 5)',
      [order, merchant, customer],
    );

    // Delivery creates the charge evidence before account deletion is attempted. The
    // test is about preserving a real settlement, not a hand-written imitation of one.
    await q('begin');
    await q("select set_config('app.server_mode', 'on', true)");
    await q("update orders set status = 'delivered' where id = $1", [order]);
    await q('commit');

    pricingBefore = (await q('select pricing from orders where id = $1', [order])).rows[0]
      .pricing;
    settlementBefore = (await q(
      'select * from order_settlements where order_id = $1',
      [order],
    )).rows[0];

    promotion = (await q(
      `insert into promotions
         (city_id, merchant_id, channel, title, start_at, end_at, requested_by)
       values ($1, $2, 'homeBanner', 'عرض', now(), now() + interval '1 day', $3)
       returning id`,
      [city, merchant, staffAccount],
    )).rows[0].id;
  });

  after(async () => {
    await q('delete from order_settlements where order_id = $1', [order]).catch(() => {});
    await q('delete from orders where city_id = $1', [city]).catch(() => {});
    await q('delete from merchants where id = $1', [merchant]).catch(() => {});
    await q('delete from auth.users where id = any($1::uuid[])', [
      [customer, staffAccount],
    ]).catch(() => {});
    await q('delete from zones where id = $1', [zone]).catch(() => {});
    await q('delete from cities where id = $1', [city]).catch(() => {});
    await db.end();
  });

  it('deletes the customer while retaining anonymised financial history', async () => {
    await as(customer, async () => {
      const auditBefore = Number((await q(
        "select count(*) from audit_log where action = 'customer.account_deleted'",
      )).rows[0].count);
      await q('select public.delete_my_account()');

      // Everything below is read as the owner, not as the customer, and still inside the
      // transaction `as()` rolls back. The scrubbed order is deliberately no longer
      // visible to that identity — every read policy on `orders` matches
      // `customer_uid = auth.uid()`, and a null customer matches nobody — so asserting
      // through the customer's own role would read an empty set and prove nothing.
      await q('set local role postgres');

      const retained = (await q(
        `select customer_uid, customer_name, customer_phone, pricing
           from orders where id = $1`,
        [order],
      )).rows[0];
      assert.equal(retained.customer_uid, null);
      assert.equal(retained.customer_name, 'حساب محذوف');
      assert.equal(retained.customer_phone, 'حساب محذوف');
      assert.deepEqual(retained.pricing, pricingBefore);

      assert.equal((await q('select count(*) from auth.users where id = $1', [customer]))
        .rows[0].count, '0');
      assert.equal((await q('select count(*) from addresses where id = $1', [address]))
        .rows[0].count, '0');
      assert.equal((await q('select count(*) from ratings where order_id = $1', [order]))
        .rows[0].count, '0');
      assert.equal((await q('select count(*) from device_tokens where uid = $1', [customer]))
        .rows[0].count, '0');

      const settlementAfter = (await q(
        'select * from order_settlements where order_id = $1',
        [order],
      )).rows[0];
      assert.deepEqual(settlementAfter, settlementBefore);

      // The retained row is still an order the business may have to finish. A status
      // change must not try to insert a push addressed to the now-null customer uid.
      await q("select set_config('app.server_mode', 'on', true)");
      await q("update orders set status = 'accepted' where id = $1", [activeOrder]);
      assert.equal((await q('select status from orders where id = $1', [activeOrder]))
        .rows[0].status, 'accepted');

      const audit = (await q(
        `select actor, detail from audit_log
          where action = 'customer.account_deleted'
          order by at desc limit 1`,
      )).rows[0];
      assert.equal(audit.actor, null);
      assert.deepEqual(audit.detail, {
        source: 'customer_app',
        ordersScrubbed: 2,
        authUserDeleted: true,
      });

      // The response to the first call may be lost after commit. Repeating the same
      // irreversible request must confirm the already-completed state, not invent an
      // error or duplicate its audit evidence.
      await q('select public.delete_my_account()');
      assert.equal(Number((await q(
        "select count(*) from audit_log where action = 'customer.account_deleted'",
      )).rows[0].count), auditBefore + 1);
    });
  });

  it('refuses every staff account before anything is deleted', async () => {
    await assert.rejects(
      as(staffAccount, () => q('select public.delete_my_account()')),
      (error) => error.code === '42501'
        && error.message === 'staff accounts require administrative deletion',
    );

    assert.equal((await q('select count(*) from auth.users where id = $1', [staffAccount]))
      .rows[0].count, '1');
    assert.equal((await q('select count(*) from staff where uid = $1', [staffAccount]))
      .rows[0].count, '1');
    assert.equal((await q('select requested_by from promotions where id = $1', [promotion]))
      .rows[0].requested_by, staffAccount);
  });
});
