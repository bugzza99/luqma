import { describe, it } from 'node:test';
import assert, { strictEqual } from 'node:assert';
import { freshDatabase } from './harness.mjs';

/**
 * Collecting the same cash twice.
 *
 * `record_commission_payment` subtracted the amount and wrote a fresh receipt on every
 * call. If the transaction committed and its reply never arrived — a phone in a shop, an
 * ordinary thing — AdminApp said the collection had *not* been recorded and offered a
 * retry. Taking that advice turned a 100 debt into zero and then into 100 of credit:
 * money the platform now owes for cash it collected once.
 */
describe('a collection recorded twice', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000a1';
  const ATTEMPT = '11111111-1111-1111-1111-111111111111';
  let db, merchant;

  const setup = async (owed) => {
    db = await freshDatabase();
    await db.query('insert into auth.users (id) values ($1)', [ADMIN]);
    // A real staff row rather than a stubbed `is_admin()`. Collecting cash asks
    // `is_platform_admin()` now — which reads the row, not the claim, so an admin demoted
    // an hour ago loses the till at once — and a fixture that fakes the predicate proves
    // only that the fake returns what it was told to. Written while the harness's own
    // admin is still signed in, which is who creates staff in production too.
    await db.query(
      `insert into staff (uid, scope, role) values ($1, 'platform', 'admin')`, [ADMIN]);
    await db.query(`create or replace function auth.uid() returns uuid
      language sql stable as $fn$ select '${ADMIN}'::uuid $fn$`);

    await db.query(`insert into cities (id,name) values ('p','مدينة')`);
    const zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee) values ('p','منطقة',0) returning id`
    )).rows[0].id;
    merchant = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status,commission_owed)
       values ('p','restaurant','مطعم',$1,'0100','approved',$2) returning id`,
      [zone, owed])).rows[0].id;
  };

  const collect = (id) => db.query(
    'select record_commission_payment($1,$2,$3,$4) as r',
    [merchant, 10000, null, id]).then((r) => r.rows[0].r);

  const owed = async () => (await db.query(
    'select commission_owed from merchants where id = $1', [merchant])).rows[0].commission_owed;

  const receipts = async () => (await db.query(
    'select count(*)::int c from commission_payments where merchant_id = $1',
    [merchant])).rows[0].c;

  // The finding itself.
  it('the same attempt twice takes the money once', async () => {
    await setup(10000);
    const first = await collect(ATTEMPT);
    const again = await collect(ATTEMPT);

    strictEqual(await owed(), 0, 'not minus the amount a second time');
    strictEqual(await receipts(), 1, 'and one receipt, not two');
    // The retry answers with the original, so a screen showing it shows the truth.
    strictEqual(again.payment.id, first.payment.id);
    strictEqual(again.remaining, 0);
  });

  // Two genuinely separate collections are still two collections.
  it('two different attempts take the money twice', async () => {
    await setup(20000);
    await collect(ATTEMPT);
    await collect('22222222-2222-2222-2222-222222222222');

    strictEqual(await owed(), 0);
    strictEqual(await receipts(), 2);
  });

  // An APK already on a phone sends no id, and must keep working exactly as before.
  it('an unnamed collection behaves as it always did', async () => {
    await setup(20000);
    await collect(null);
    await collect(null);

    strictEqual(await owed(), 0);
    strictEqual(await receipts(), 2);
  });

  // Credit is a real state — an admin may over-collect deliberately — so the guard is
  // against repeating one collection, not against a negative balance.
  it('and a deliberate over-collection still goes into credit', async () => {
    await setup(5000);
    await collect(ATTEMPT);
    strictEqual(await owed(), -5000);
  });

  // D8. The courier's collection checks the balance the admin acted on (M-10); the shop's
  // did not. Two admins — or one admin on two devices — both read «المستحق 200», minted
  // different receipts, and both recorded 200: the shop went 200 into credit that neither
  // of them meant. The five-argument call carries the balance the dialog opened on.
  const collectExpecting = (id, expected, amount = 10000) => db.query(
    'select record_commission_payment($1,$2,$3,$4,$5) as r',
    [merchant, amount, null, id, expected]).then((r) => r.rows[0].r);

  it('a collection against a balance that has since moved is refused', async () => {
    await setup(20000);
    await collect('33333333-3333-3333-3333-333333333333');

    await assert.rejects(
      () => collectExpecting('44444444-4444-4444-4444-444444444444', 20000),
      /shop balance changed/);
    strictEqual(await owed(), 10000, 'nothing moved on the refusal');
  });

  it('one against the balance as it stands goes through', async () => {
    await setup(20000);
    await collectExpecting('55555555-5555-5555-5555-555555555555', 20000);
    strictEqual(await owed(), 10000);
  });

  // A retry after a lost reply must reconcile the first payment, not be refused because
  // that very payment moved the balance.
  it('a retry of a collection that landed returns its receipt, balance or not', async () => {
    await setup(20000);
    const first = await collectExpecting('66666666-6666-6666-6666-666666666666', 20000);
    const again = await collectExpecting('66666666-6666-6666-6666-666666666666', 20000);
    strictEqual(again.payment.id, first.payment.id);
    strictEqual(await owed(), 10000);
  });
});
