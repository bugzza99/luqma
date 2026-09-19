import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A payment is recorded once, however many times the button is pressed.
 *
 * The QA review found both money paths in AdminApp could be applied twice: a retry after a
 * lost reply credited the wallet again, and a subscription payment made a second term.
 */
describe('a payment is recorded once', () => {
  let db, zoneId;

  const shop = async (name) => (await db.query(
    `insert into merchants (city_id, type, name, zone_id, phone, status)
     values ('edku', 'restaurant', $1, $2, '01000000000', 'approved') returning id`,
    [name, zoneId])).rows[0].id;

  const wallet = async (id) => (await db.query(
    'select wallet_balance from merchants where id = $1', [id])).rows[0].wallet_balance;

  const terms = async (id) => (await db.query(
    'select started_at, expires_at from subscriptions where merchant_id = $1 order by started_at',
    [id])).rows;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;
      insert into plans (id, name, price_monthly) values ('premium', 'مميزة', 30000)
        on conflict (id) do nothing;`);
    zoneId = (await db.query(
      `insert into zones (city_id, name, default_delivery_fee)
       values ('edku', 'الزغبي', 1000) returning id`)).rows[0].id;
  });

  after(async () => { await db?.close(); });

  // Owner-run tests passed while a real admin token failed on every receipt: the table
  // grants no insert, and the functions ran with the caller's rights (Astra, 2026-09-19).
  // So these two go through `authenticated`, as a phone does.
  const asAdmin = async (fn) => {
    await db.exec('grant usage on schema auth to anon, authenticated');
    await db.exec('set role authenticated');
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  it('an admin token records a top-up with a receipt', async () => {
    const id = await shop('بتوكن أدمن');
    const r = await asAdmin(() => db.query(
      'select public.top_up_wallet($1, 700, null, gen_random_uuid()) as r', [id]));
    assert.equal(r.rows[0].r.walletBalance, 700);
  });

  it('an admin token records a subscription payment with a receipt', async () => {
    const id = await shop('اشتراك بتوكن');
    await asAdmin(() => db.query(
      `select public.record_subscription_payment($1, 'premium', 30000, 1, null,
                                                 gen_random_uuid())`, [id]));
    assert.equal((await terms(id)).length, 1);
  });

  describe('the wallet', () => {
    it('the same receipt twice credits once, and says it was a repeat', async () => {
      const id = await shop('محفظة');
      const receipt = '11111111-1111-1111-1111-111111111111';

      const first = (await db.query(
        'select public.top_up_wallet($1, 5000, null, $2) as r', [id, receipt])).rows[0].r;
      const second = (await db.query(
        'select public.top_up_wallet($1, 5000, null, $2) as r', [id, receipt])).rows[0].r;

      assert.equal(await wallet(id), 5000);
      assert.equal(first.repeated, false);
      assert.equal(second.repeated, true);
      assert.equal(second.walletBalance, 5000);
    });

    it('two different receipts are two payments', async () => {
      const id = await shop('محفظتين');
      await db.query('select public.top_up_wallet($1, 1000, null, gen_random_uuid())', [id]);
      await db.query('select public.top_up_wallet($1, 1000, null, gen_random_uuid())', [id]);
      assert.equal(await wallet(id), 2000);
    });

    it('a receipt cannot be replayed against another shop', async () => {
      const a = await shop('أ');
      const b = await shop('ب');
      const receipt = '22222222-2222-2222-2222-222222222222';
      await db.query('select public.top_up_wallet($1, 1000, null, $2)', [a, receipt]);
      await assert.rejects(
        () => db.query('select public.top_up_wallet($1, 1000, null, $2)', [b, receipt]),
        /another payment/);
      assert.equal(await wallet(b), 0);
    });

    it('an older phone with no receipt still records', async () => {
      const id = await shop('نسخة قديمة');
      await db.query('select public.top_up_wallet($1, 700)', [id]);
      assert.equal(await wallet(id), 700);
    });
  });

  describe('a subscription term', () => {
    it('the same receipt twice makes one term', async () => {
      const id = await shop('اشتراك');
      const receipt = '33333333-3333-3333-3333-333333333333';
      await db.query(
        `select public.record_subscription_payment($1, 'premium', 30000, 1, null, $2)`,
        [id, receipt]);
      await db.query(
        `select public.record_subscription_payment($1, 'premium', 30000, 1, null, $2)`,
        [id, receipt]);
      assert.equal((await terms(id)).length, 1);
    });

    it('two payments follow each other instead of overlapping', async () => {
      const id = await shop('شهرين');
      await db.query(`select public.record_subscription_payment($1, 'premium', 30000, 1)`, [id]);
      await db.query(`select public.record_subscription_payment($1, 'premium', 30000, 1)`, [id]);
      const t = await terms(id);
      assert.equal(t.length, 2);
      assert.equal(t[1].started_at.getTime(), t[0].expires_at.getTime());
    });

    it('puts server mode back the way it found it', async () => {
      const id = await shop('وضع السيرفر');
      await db.exec('begin');
      try {
        await db.query("select set_config('app.server_mode', 'custom', true)");
        await db.query(
          `select public.record_subscription_payment($1, 'premium', 1, 1, null, gen_random_uuid())`,
          [id]);
        await db.query('select public.top_up_wallet($1, 1, null, gen_random_uuid())', [id]);
        const mode = (await db.query(
          "select current_setting('app.server_mode', true) as m")).rows[0].m;
        assert.equal(mode, 'custom');
      } finally {
        await db.exec('rollback');
      }
    });
  });
});
