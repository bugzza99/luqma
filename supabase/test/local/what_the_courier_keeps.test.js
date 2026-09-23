import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * What the courier keeps, what the shop gets, and what the platform is owed.
 *
 * The rule (the owner's, 2026-09-20): a platform courier keeps the delivery fee and pays
 * the platform a percentage of it; a shop's own courier hands the shop everything.
 *
 * The test that matters most here is the one for a courier who is *not* on the platform
 * roster. The parked version of this feature returned silently in that case — no charge,
 * no error, no row — so a courier dropped from the roster worked all week and accrued
 * nothing, and the first sign would have been a reminder that never came. There is a row
 * for every delivered order now, zeros included, and `ground` says which of the three
 * answers produced it.
 */
describe('what the courier keeps', () => {
  const RIDER = '00000000-0000-0000-0000-0000000000f1';
  const SHOP_RIDER = '00000000-0000-0000-0000-0000000000f2';
  const ADMIN = '00000000-0000-0000-0000-0000000000f3';
  const SECOND_RIDER = '00000000-0000-0000-0000-0000000000f4';

  let db, fish, zone;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const admin = () => as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });

  /** Places an order and leaves it at `placed`. */
  const place = async ({ fee = 2000, deliveryDiscount = 0, platform = true } = {}) =>
    (await db.query(
      `insert into orders (city_id,customer_uid,customer_name,customer_phone,
                           merchant_id,merchant_name,zone_id,type,items,pricing,status,
                           delivery_by)
       values ('edku',null,'عميل','01000000000',$1,
               (select name from merchants where id=$1),$2,'instant','[]',
               jsonb_build_object('subtotal',10000,'deliveryFee',$3::int,
                                  'deliveryDiscount',$4::int,
                                  'total',10000 + $3::int - $4::int),
               'placed',$5)
       returning id`,
      [fish, zone, fee, deliveryDiscount, platform ? 'platform' : 'merchant'])).rows[0].id;

  /** Moves an order to a status as the server would, with the courier stamped on it. */
  const move = (id, status, courier) => db.query(`do $$ begin
    perform set_config('app.server_mode','on',true);
    update public.orders
       set status = '${status}',
           courier_uid = ${courier ? `'${courier}'` : 'null'},
           delivered_at = ${status === 'delivered' ? 'now()' : 'null'}
     where id = '${id}';
  end $$;`);

  const settlement = async (id) =>
    (await db.query('select * from courier_settlements where order_id = $1', [id])).rows[0];

  const owed = async (uid) =>
    (await db.query('select commission_owed from staff where uid = $1', [uid]))
      .rows[0].commission_owed;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values
        ('${RIDER}'), ('${SHOP_RIDER}'), ('${ADMIN}'), ('${SECOND_RIDER}');
      grant usage on schema auth to authenticated;
      insert into cities (id,name) values ('edku','إدكو');`);

    zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee)
       values ('edku','الزغبي',2000) returning id`)).rows[0].id;
    fish = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ('edku','restaurant','السمك',$1,'0100','approved') returning id`,
      [zone])).rows[0].id;

    await db.query(
      `insert into staff (uid,scope,role,merchant_id,is_active) values
         ($1,'platform','courier',null,true),
         ($2,'merchant','courier',$3,true),
         ($4,'platform','admin',null,true),
         ($5,'platform','courier',null,true)`,
      [RIDER, SHOP_RIDER, fish, ADMIN, SECOND_RIDER]);

    // No inserts into `courier_merchants` here on purpose: `staff_attach_initial_courier`
    // already mints the initial grant from the staff row's own scope, so the platform
    // rider gets the platform row and the shop's rider gets the shop's. Adding them by
    // hand collides with that trigger — and a fixture that builds the roster itself is a
    // fixture that can disagree with the one authority the settlement reads.
  });

  after(async () => { await db?.close(); });

  beforeEach(async () => {
    await db.exec(`
      delete from courier_settlements;
      delete from order_settlements;
      delete from courier_commission_payments;
      delete from payment_receipts;
      delete from orders;
      update config set value = '10'::jsonb where key = 'courier_commission_percent';
      do $$ begin
        perform set_config('app.server_mode','on',true);
        update public.staff set commission_owed = 0;
      end $$;`);
    await admin();
  });

  describe('the three grounds', () => {
    it('charges a platform courier a tenth of the delivery they kept', async () => {
      const id = await place({ fee: 2000 });
      await move(id, 'delivered', RIDER);

      const row = await settlement(id);
      assert.equal(row.ground, 'platform');
      assert.equal(row.basis, 2000);
      assert.equal(row.bps, 1000);
      assert.equal(row.amount, 200);
      assert.equal(await owed(RIDER), 200);
    });

    it('charges nothing when the shop delivered, and says so in a row', async () => {
      const id = await place({ platform: false });
      await move(id, 'delivered', SHOP_RIDER);

      const row = await settlement(id);
      assert.equal(row.ground, 'merchantDelivery');
      assert.equal(row.amount, 0);
      assert.equal(await owed(SHOP_RIDER), 0);
    });

    it('writes a row for a courier who is not on the platform roster', async () => {
      // The regression this whole rewrite exists for. The parked version returned
      // silently here: no charge, no error, nothing written, and a rider dropped from the
      // roster kept working for free on the platform's behalf with nobody the wiser.
      const id = await place({ platform: true });
      await move(id, 'delivered', SHOP_RIDER);

      const row = await settlement(id);
      assert.ok(row, 'a delivered order must leave a row whatever the answer');
      assert.equal(row.ground, 'notPlatformCourier');
      assert.equal(row.amount, 0);
      assert.equal(row.courier_uid, SHOP_RIDER);
    });

    it('charges nothing on a free delivery', async () => {
      // Charging a percentage of a fee nobody received is charging for money nobody
      // received — the same sentence as «العمولة على الأكل مش على الفاتورة», from the
      // other side.
      const id = await place({ fee: 2000, deliveryDiscount: 2000 });
      await move(id, 'delivered', RIDER);

      const row = await settlement(id);
      assert.equal(row.ground, 'platform');
      assert.equal(row.basis, 0);
      assert.equal(row.amount, 0);
      assert.equal(await owed(RIDER), 0);
    });
  });

  describe('settling once', () => {
    it('does not charge twice when the status is written again', async () => {
      const id = await place();
      await move(id, 'delivered', RIDER);
      await move(id, 'delivered', RIDER);

      assert.equal(await owed(RIDER), 200);
    });

    it('gives it back when the order stops being delivered', async () => {
      const id = await place();
      await move(id, 'delivered', RIDER);
      assert.equal(await owed(RIDER), 200);

      await move(id, 'cancelled', RIDER);

      assert.equal(await owed(RIDER), 0);
      assert.notEqual((await settlement(id)).reversed_at, null);
    });

    // A15. A reopened order delivered again kept the first charge's row: the conflict
    // clause reset the timestamps and nothing else. The second courier was charged on
    // their balance while the row still named the first, so the next reversal refunded
    // the wrong person an amount they may not have been charged at all.
    it('charging again after a reversal follows whoever carried it this time', async () => {
      const id = await place({ fee: 2000 });
      await move(id, 'delivered', RIDER);
      await move(id, 'outForDelivery', SECOND_RIDER);
      assert.equal(await owed(RIDER), 0, 'the first charge was given back');

      await db.query(
        `update config set value = '20'::jsonb where key = 'courier_commission_percent'`);
      await move(id, 'delivered', SECOND_RIDER);

      const row = await settlement(id);
      assert.equal(row.courier_uid, SECOND_RIDER);
      assert.equal(row.bps, 2000);
      assert.equal(row.amount, 400);
      assert.equal(await owed(SECOND_RIDER), 400);

      await move(id, 'cancelled', SECOND_RIDER);
      assert.equal(await owed(SECOND_RIDER), 0, 'and a later reversal refunds them, exactly');
      assert.equal(await owed(RIDER), 0, 'not the first rider');
    });

    it('gives back what was taken, not what today would charge', async () => {
      const id = await place();
      await move(id, 'delivered', RIDER);

      await admin();
      await db.query(
        `update config set value = '40'::jsonb where key = 'courier_commission_percent'`);
      await move(id, 'cancelled', RIDER);

      // 200 was taken under the old rate; 800 would be today's answer. Handing back 800
      // would refund money nobody was ever charged.
      assert.equal(await owed(RIDER), 0);
    });
  });

  describe('the rate', () => {
    it('allows zero, which is how a courier runs at no commission', async () => {
      await db.query(
        `update config set value = '0'::jsonb where key = 'courier_commission_percent'`);
      const id = await place();
      await move(id, 'delivered', RIDER);

      assert.equal((await settlement(id)).amount, 0);
    });

    it('refuses a rate outside its range, whoever writes it', async () => {
      for (const bad of ['-1', '51', '"free"']) {
        await assert.rejects(
          () => db.query(
            `update config set value = $1::jsonb where key = 'courier_commission_percent'`,
            [bad]),
          /courier_commission_percent/,
          `expected ${bad} to be refused`);
      }
    });
  });

  describe('the balance is not theirs to move', () => {
    it('refuses a hand-written commission_owed', async () => {
      // There has to be a balance to wipe: the guard compares the two values, so writing
      // the number it already holds changes nothing and is nothing to refuse.
      const id = await place();
      await move(id, 'delivered', RIDER);
      assert.equal(await owed(RIDER), 200);

      await admin();
      await assert.rejects(
        () => db.query('update staff set commission_owed = 0 where uid = $1', [RIDER]),
        /not by hand/);

      assert.equal(await owed(RIDER), 200);
    });
  });

  describe('collecting the cash', () => {
    it('lowers the balance and leaves a receipt', async () => {
      const id = await place();
      await move(id, 'delivered', RIDER);

      await admin();
      const result = (await db.query(
        'select record_courier_payment($1, $2, $3) as r', [RIDER, 150, 'استلمت كاش'])).rows[0].r;

      assert.equal(result.remaining, 50);
      assert.equal(await owed(RIDER), 50);
      const payments = await db.query(
        'select amount, note from courier_commission_payments where courier_uid = $1', [RIDER]);
      assert.equal(payments.rows.length, 1);
      assert.equal(payments.rows[0].amount, 150);
    });

    it('records one payment however many times the button is pressed', async () => {
      const id = await place();
      await move(id, 'delivered', RIDER);
      await admin();
      const receipt = '11111111-2222-3333-4444-555555555555';

      const first = (await db.query(
        'select record_courier_payment($1, $2, null, $3) as r',
        [RIDER, 100, receipt])).rows[0].r;
      const again = (await db.query(
        'select record_courier_payment($1, $2, null, $3) as r',
        [RIDER, 100, receipt])).rows[0].r;

      // The money is identical; the reply is not. A replay says so, because «اتسجّل» and
      // «كان متسجّل» are two different sentences and only one is true of the tap that
      // produced this call.
      assert.equal(first.repeated, false);
      assert.equal(again.repeated, true);
      for (const field of ['receiptId', 'kind', 'courierUid', 'amount', 'remaining']) {
        assert.deepEqual(again[field], first[field], field);
      }
      assert.equal(await owed(RIDER), 100);
      const payments = await db.query(
        'select count(*)::int n from courier_commission_payments where courier_uid = $1', [RIDER]);
      assert.equal(payments.rows[0].n, 1);
    });

    it('rejects a new receipt after the balance changed but still reconciles a retry', async () => {
      const id = await place();
      await move(id, 'delivered', RIDER);
      await admin();
      const firstReceipt = '14111111-2222-3333-4444-555555555555';
      const staleReceipt = '15111111-2222-3333-4444-555555555555';

      const first = (await db.query(
        'select record_courier_payment($1, $2, null, $3, $4) as r',
        [RIDER, 100, firstReceipt, 200])).rows[0].r;

      assert.equal(first.remaining, 100);
      const repeated = (await db.query(
        'select record_courier_payment($1, $2, null, $3, $4) as r',
        [RIDER, 100, firstReceipt, 200])).rows[0].r;
      assert.equal(repeated.repeated, true,
        'a lost reply must reconcile before checking the now-stale opening balance');

      await assert.rejects(
        () => db.query(
          'select record_courier_payment($1, $2, null, $3, $4)',
          [RIDER, 100, staleReceipt, 200]),
        /courier balance changed/);
      assert.equal(await owed(RIDER), 100);
      const payments = await db.query(
        'select count(*)::int n from courier_commission_payments where courier_uid = $1', [RIDER]);
      assert.equal(payments.rows[0].n, 1);
    });

    it('refuses the same receipt for a different amount', async () => {
      const receipt = '12111111-2222-3333-4444-555555555555';
      await db.query(
        'select record_courier_payment($1, $2, null, $3)',
        [RIDER, 100, receipt]);

      await assert.rejects(
        () => db.query(
          'select record_courier_payment($1, $2, null, $3)',
          [RIDER, 150, receipt]),
        /another payment/);
      assert.equal(await owed(RIDER), -100);
      const payments = await db.query(
        'select count(*)::int n from courier_commission_payments where courier_uid = $1', [RIDER]);
      assert.equal(payments.rows[0].n, 1);
    });

    it('verifies a legacy receipt amount from its audit row', async () => {
      const receipt = '13111111-2222-3333-4444-555555555555';
      await db.query(
        `insert into payment_receipts
           (id, kind, merchant_id, courier_uid, result, recorded_by)
         values ($1, 'courierCommission', null, $2, '{"remaining":25}'::jsonb, $3)`,
        [receipt, RIDER, ADMIN]);
      await db.query(
        `insert into audit_log (action, actor, detail)
         values ('recordCourierPayment', $1,
                 jsonb_build_object('courier', $2::uuid, 'amount', 75, 'receipt', $3::uuid))`,
        [ADMIN, RIDER, receipt]);

      const repeated = (await db.query(
        'select record_courier_payment($1, $2, null, $3) as r',
        [RIDER, 75, receipt])).rows[0].r;
      // The balance as it stands now, and the receipt named so a screen can check the
      // reply belongs to the attempt it sent.
      assert.equal(repeated.remaining, await owed(RIDER));
      assert.equal(repeated.repeated, true);
      assert.equal(repeated.amount, 75);
      assert.equal(repeated.receiptId, receipt);
      const stored = (await db.query(
        'select result from payment_receipts where id = $1', [receipt])).rows[0].result;
      assert.equal(stored.amount, 75);

      await assert.rejects(
        () => db.query(
          'select record_courier_payment($1, $2, null, $3)',
          [RIDER, 50, receipt]),
        /another payment/);
    });

    it('refuses a receipt that belongs to a different courier', async () => {
      const receipt = '21111111-2222-3333-4444-555555555555';
      await db.query(
        'select record_courier_payment($1, $2, null, $3)',
        [RIDER, 100, receipt]);

      await assert.rejects(
        () => db.query(
          'select record_courier_payment($1, $2, null, $3)',
          [SHOP_RIDER, 100, receipt]),
        /another payment/);
      assert.equal(await owed(SHOP_RIDER), 0);
    });

    it('refuses a receipt created for a merchant payment', async () => {
      const receipt = '31111111-2222-3333-4444-555555555555';
      await db.query(
        `insert into payment_receipts
           (id, kind, merchant_id, courier_uid, result, recorded_by)
         values ($1, 'walletTopUp', $2, null, '{"walletBalance":100}'::jsonb, $3)`,
        [receipt, fish, ADMIN]);

      await assert.rejects(
        () => db.query(
          'select record_courier_payment($1, $2, null, $3)',
          [RIDER, 100, receipt]),
        /another payment/);
      assert.equal(await owed(RIDER), 0);
    });

    it('lets the balance go negative, because that is credit', async () => {
      const id = await place();
      await move(id, 'delivered', RIDER);
      await admin();

      await db.query('select record_courier_payment($1, $2)', [RIDER, 500]);

      assert.equal(await owed(RIDER), -300);
    });

    it('refuses anybody who is not an admin', async () => {
      await as(RIDER, { role: 'courier', scope: 'platform' });
      await assert.rejects(
        () => db.query('select record_courier_payment($1, $2)', [RIDER, 100]),
        /only an admin/);
    });

    it('refuses to record courier cash against a non-courier staff row', async () => {
      await admin();

      await assert.rejects(
        () => db.query('select record_courier_payment($1, $2)', [ADMIN, 100]),
        /no such courier/);
      const payments = await db.query(
        'select count(*)::int n from courier_commission_payments where courier_uid = $1',
        [ADMIN]);
      assert.equal(payments.rows[0].n, 0);
    });

    it('refuses a payment that is not a positive amount', async () => {
      await admin();
      await assert.rejects(
        () => db.query('select record_courier_payment($1, $2)', [RIDER, 0]),
        /positive amount/);
    });
  });

  describe('what a rider earned', () => {
    it('reports today, this week and this month in one call', async () => {
      const id = await place({ fee: 2000 });
      await move(id, 'delivered', RIDER);

      await as(RIDER, { role: 'courier', scope: 'platform' });
      const earnings = (await db.query('select courier_earnings() as e')).rows[0].e;

      for (const span of ['today', 'week', 'month']) {
        assert.ok(earnings[span], `${span} is missing`);
        assert.equal(earnings[span].delivered, 1, span);
        assert.equal(earnings[span].fees, 2000, span);
        assert.equal(earnings[span].commission, 200, span);
        // What is actually theirs, computed on the server so the figure a courier argues
        // from and the figure the owner collects against come from one statement.
        assert.equal(earnings[span].net, 1800, span);
      }
    });

    it('counts a trip that came back without counting its money', async () => {
      const id = await place();
      await db.query(`do $$ begin
        perform set_config('app.server_mode','on',true);
        update public.orders set status='cancelled', cancelled_by='courier',
               courier_uid='${RIDER}' where id='${id}';
      end $$;`);

      await as(RIDER, { role: 'courier', scope: 'platform' });
      const earnings = (await db.query('select courier_earnings() as e')).rows[0].e;

      assert.equal(earnings.today.returned, 1);
      assert.equal(earnings.today.delivered, 0);
      assert.equal(earnings.today.cash, 0);
      assert.equal(earnings.today.net, 0);
    });

    it('shows a rider their own work and nobody else\'s', async () => {
      const mine = await place();
      await move(mine, 'delivered', RIDER);
      const theirs = await place({ platform: false });
      await move(theirs, 'delivered', SHOP_RIDER);

      await as(RIDER, { role: 'courier', scope: 'platform' });
      const earnings = (await db.query('select courier_earnings() as e')).rows[0].e;

      assert.equal(earnings.today.delivered, 1);
    });

    it('answers with zeros rather than nothing for a rider with no work', async () => {
      // A screen that gets null for "this month" has to invent a number or draw an error,
      // and neither is "you have not delivered anything yet".
      await as(SHOP_RIDER, { role: 'courier', scope: 'merchant' });
      const earnings = (await db.query('select courier_earnings() as e')).rows[0].e;

      assert.equal(earnings.month.delivered, 0);
      assert.equal(earnings.month.net, 0);
    });
  });
});
