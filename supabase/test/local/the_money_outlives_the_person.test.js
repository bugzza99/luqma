import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A financial record outlives the person or the shop it is about.
 *
 * The owner's rule: «الدين يفضل، والشخص هو اللي يروح». Before this, the money tables gave
 * three different answers to one question — RESTRICT, CASCADE, and a SET NULL into a CHECK
 * that refused null — so deleting a courier who had ever paid was impossible, and deleting
 * a shop silently took its idempotency receipts and its paid subscription terms with it.
 *
 * Both halves are tested here: that the delete now succeeds, and that what it leaves
 * behind is still readable by somebody settling an argument about money.
 */
describe('the money outlives the person', () => {
  const ADMIN = '00000000-0000-0000-0000-00000000e001';
  const RIDER = '00000000-0000-0000-0000-00000000e002';

  let db, zone, shop;

  const rows = async (sql, params) => (await db.query(sql, params)).rows;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${ADMIN}'), ('${RIDER}');
      grant usage on schema auth to authenticated;
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;
      insert into staff (uid, scope, role, is_active)
        values ('${ADMIN}', 'platform', 'admin', true);
    `);
    zone = (await rows(
      `insert into zones (city_id, name, default_delivery_fee)
       values ('edku', 'الزغبي', 2000) returning id`))[0].id;
  });

  after(async () => { await db?.close(); });

  beforeEach(async () => {
    await db.exec(`
      delete from payment_receipts;
      delete from courier_commission_payments;
      delete from commission_payments;
      delete from subscriptions;
      delete from merchants;
      delete from staff where uid <> '${ADMIN}';
    `);
    shop = (await rows(
      `insert into merchants (city_id, type, name, zone_id, phone, status)
       values ('edku', 'restaurant', 'مطعم السمك', $1, '0100', 'approved') returning id`,
      [zone]))[0].id;
    await db.query(
      `insert into staff (uid, scope, role, name, is_active)
       values ($1, 'platform', 'courier', 'كابتن سعيد', true)`, [RIDER]);
  });

  describe('a courier with a financial history', () => {
    const payCourier = async () => {
      await db.query(
        `insert into courier_commission_payments (courier_uid, amount, recorded_by)
         values ($1, 500, $2)`, [RIDER, ADMIN]);
      await db.query(
        `insert into payment_receipts (id, kind, merchant_id, courier_uid, result, recorded_by)
         values (gen_random_uuid(), 'courierCommission', null, $1, '{}'::jsonb, $2)`,
        [RIDER, ADMIN]);
    };

    it('can be deleted, which used to be impossible', async () => {
      // Two constraints refused it between them: the payment's FK was RESTRICT, and the
      // receipt's was SET NULL into a CHECK that demanded NOT NULL. A whole class of
      // account could not be removed at all, while the product documented that it could.
      await payCourier();

      await db.query('delete from staff where uid = $1', [RIDER]);

      assert.equal((await rows('select 1 from staff where uid = $1', [RIDER])).length, 0);
    });

    it('leaves the money behind, still readable', async () => {
      await payCourier();

      await db.query('delete from staff where uid = $1', [RIDER]);

      const payment = (await rows('select * from courier_commission_payments'))[0];
      assert.ok(payment, 'the payment survives the payer');
      assert.equal(payment.amount, 500);
      assert.equal(payment.courier_uid, null, 'the person is gone');
      // The point of the frozen name: a statement whose payer is a null uuid is one
      // nobody can act on, and a name is what the owner asks for on the telephone.
      assert.equal(payment.courier_name, 'كابتن سعيد');

      const receipt = (await rows('select * from payment_receipts'))[0];
      assert.ok(receipt, 'the idempotency key survives too');
      assert.equal(receipt.courier_uid, null);
      assert.equal(receipt.subject_name, 'كابتن سعيد');
    });
  });

  describe('a shop with a financial history', () => {
    const payShop = async () => {
      await db.query(
        `insert into commission_payments (merchant_id, amount, recorded_by)
         values ($1, 900, $2)`, [shop, ADMIN]);
      await db.query(
        `insert into payment_receipts (id, kind, merchant_id, result, recorded_by)
         values (gen_random_uuid(), 'walletTopUp', $1, '{}'::jsonb, $2)`, [shop, ADMIN]);
      await db.query(
        `insert into plans (id, name, price_monthly) values ('basic', 'أساسية', 10000)
         on conflict (id) do nothing`);
      await db.query(
        `insert into subscriptions (merchant_id, plan_id, amount, started_at, expires_at, recorded_by)
         values ($1, 'basic', 10000, now(), now() + interval '30 days', $2)`, [shop, ADMIN]);
    };

    it('keeps its receipts and its paid term instead of cascading them away', async () => {
      // A receipt exists precisely so one payment cannot be recorded twice. Deleting it
      // with the shop threw away the evidence and the protection together.
      await payShop();

      await db.query('delete from merchants where id = $1', [shop]);

      const receipt = (await rows('select * from payment_receipts'))[0];
      assert.ok(receipt, 'the idempotency key survives the shop');
      assert.equal(receipt.merchant_id, null);
      assert.equal(receipt.subject_name, 'مطعم السمك');

      const term = (await rows('select * from subscriptions'))[0];
      assert.ok(term, 'a paid term is not erased by deleting the shop');
      assert.equal(term.amount, 10000);
      assert.equal(term.merchant_name, 'مطعم السمك');

      const collected = (await rows('select * from commission_payments'))[0];
      assert.equal(collected.amount, 900);
      assert.equal(collected.merchant_name, 'مطعم السمك');
    });
  });

  describe('the receipt still names exactly one subject', () => {
    it('refuses a courier receipt that also names a shop', async () => {
      // What the CHECK was always for. Relaxing the not-null part must not relax this.
      await assert.rejects(
        () => db.query(
          `insert into payment_receipts (id, kind, merchant_id, courier_uid, result, recorded_by)
           values (gen_random_uuid(), 'courierCommission', $1, $2, '{}'::jsonb, $3)`,
          [shop, RIDER, ADMIN]),
        /payment_receipts_subject_check/);
    });

    it('refuses a shop receipt that names nobody at all', async () => {
      await assert.rejects(
        () => db.query(
          `insert into payment_receipts (id, kind, merchant_id, courier_uid, subject_name, result, recorded_by)
           values (gen_random_uuid(), 'walletTopUp', null, null, null, '{}'::jsonb, $1)`,
          [ADMIN]),
        /payment_receipts_subject_check/);
    });

    it('accepts one whose subject is gone but named', async () => {
      // The state every surviving row ends up in. If the CHECK refused this, deletion
      // would still be impossible — just one constraint further along.
      await db.query(
        `insert into payment_receipts (id, kind, merchant_id, courier_uid, subject_name, result, recorded_by)
         values (gen_random_uuid(), 'walletTopUp', null, null, 'محل اتقفل', '{}'::jsonb, $1)`,
        [ADMIN]);

      assert.equal((await rows('select 1 from payment_receipts')).length, 1);
    });
  });

  describe('the name is stamped for every writer', () => {
    it('fills itself in when the caller did not', async () => {
      // Four functions across six migrations write these tables. A rule each of them has
      // to remember is a rule the next one forgets, so the trigger owns it.
      await db.query(
        `insert into courier_commission_payments (courier_uid, amount, recorded_by)
         values ($1, 100, $2)`, [RIDER, ADMIN]);

      assert.equal(
        (await rows('select courier_name from courier_commission_payments'))[0].courier_name,
        'كابتن سعيد');
    });

    it('leaves a name the caller supplied alone', async () => {
      await db.query(
        `insert into commission_payments (merchant_id, amount, merchant_name, recorded_by)
         values ($1, 100, 'الاسم وقت الدفع', $2)`, [shop, ADMIN]);

      assert.equal(
        (await rows('select merchant_name from commission_payments'))[0].merchant_name,
        'الاسم وقت الدفع');
    });
  });
});
