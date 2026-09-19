import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * One commission for every shop, collected weekly, and a warning when it runs high.
 *
 * The owner's rules: one rate (5% to start) set in «الإعدادات»; a shop can be given its own;
 * weekly cash collection with a reminder; above 500 ج owed, the shop and the owner are told.
 */
describe('one commission for every shop', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000ad'; // the harness's own admin
  const OWNER = '00000000-0000-0000-0000-0000000000e1';
  let db, zoneId;

  const shop = async (name, extra = {}) => (await db.query(
    `insert into merchants (city_id, type, name, zone_id, phone, status, revenue_model,
                            revenue_value, commission_custom)
     values ('edku', 'restaurant', $1, $2, '0100', 'approved', $3, $4, $5) returning id`,
    [name, zoneId, extra.model ?? 'commission', extra.value ?? 0, extra.custom ?? false],
  )).rows[0].id;

  const row = async (id) => (await db.query(
    'select revenue_model, revenue_value, commission_custom from merchants where id = $1',
    [id])).rows[0];

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;
      insert into auth.users (id) values ('${OWNER}');`);
    zoneId = (await db.query(
      `insert into zones (city_id, name, default_delivery_fee)
       values ('edku', 'الزغبي', 1000) returning id`)).rows[0].id;
  });

  after(async () => { await db?.close(); });

  it('a new shop starts on the one rate, 5%', async () => {
    const id = await shop('جديد');
    assert.deepEqual(await row(id),
      { revenue_model: 'commission', revenue_value: 500, commission_custom: false });
  });

  it('a new shop marked subscription starts on commission — a plan is what means monthly',
    async () => {
      const id = await shop('اشتراك', { model: 'subscription' });
      assert.equal((await row(id)).revenue_model, 'commission');
      assert.equal((await row(id)).revenue_value, 500);
    });

  it('changing the rate moves every shop that follows it, and none that has its own',
    async () => {
      const follows = await shop('بيتبع');
      const own = await shop('اتفاق خاص', { value: 300, custom: true });

      const r = (await db.query(
        'select public.admin_set_commission_policy(7.5, 500) as r')).rows[0].r;

      assert.equal((await row(follows)).revenue_value, 750);
      assert.equal((await row(own)).revenue_value, 300);
      assert.ok(r.shopsMoved >= 1);
      // And a shop made afterwards starts on the new rate.
      assert.equal((await row(await shop('بعدين'))).revenue_value, 750);
      await db.query('select public.admin_set_commission_policy(5, 500)');
    });

  it('a shop can be given its own rate, and put back on the one rate', async () => {
    const id = await shop('خاص');
    await db.query('select public.admin_set_shop_commission($1, 1200)', [id]);
    assert.deepEqual(await row(id),
      { revenue_model: 'commission', revenue_value: 1200, commission_custom: true });

    await db.query('select public.admin_set_shop_commission($1, null)', [id]);
    assert.deepEqual(await row(id),
      { revenue_model: 'commission', revenue_value: 500, commission_custom: false });
  });

  it('refuses a rate that is not a percentage, and anybody who is not an admin', async () => {
    await assert.rejects(() => db.query('select public.admin_set_commission_policy(80, 500)'),
      /0 to 50/);
    await db.exec(`
      create or replace function auth.uid() returns uuid language sql stable
        as $fn$ select '${OWNER}'::uuid $fn$;
      create or replace function auth.jwt() returns jsonb language sql stable
        as $fn$ select '{}'::jsonb $fn$;`);
    try {
      await assert.rejects(() => db.query('select public.admin_set_commission_policy(5, 500)'),
        /only an admin/);
    } finally {
      await db.exec(`
        create or replace function auth.uid() returns uuid language sql stable
          as $fn$ select '${ADMIN}'::uuid $fn$;
        create or replace function auth.jwt() returns jsonb language sql stable
          as $fn$ select '{"app_metadata":{"admin":true}}'::jsonb $fn$;`);
    }
  });

  // Every path, not only the two functions: an admin handset on an older APK writes the
  // columns and the config directly (Astra, 2026-09-19).
  describe('the rules hold for a direct write', () => {
    const direct = (sql, params) => db.query(
      `select set_config('app.server_mode', 'on', false)`).then(async () => {
      try { return await db.query(sql, params); } finally {
        await db.query(`select set_config('app.server_mode', '', false)`);
      }
    });

    it('writing the old subscription model puts the shop back on commission', async () => {
      const id = await shop('نسخة قديمة');
      await direct(`update merchants set revenue_model = 'subscription', revenue_value = 0
                     where id = $1`, [id]);
      assert.deepEqual(await row(id),
        { revenue_model: 'commission', revenue_value: 500, commission_custom: false });
    });

    it('a rate written directly is that shop own rate, and survives a change of the rate',
      async () => {
        const id = await shop('اتفق بالتليفون');
        await direct('update merchants set revenue_value = 300 where id = $1', [id]);
        assert.equal((await row(id)).commission_custom, true);

        await db.query('select public.admin_set_commission_policy(6, 500)');
        assert.equal((await row(id)).revenue_value, 300);
        await db.query('select public.admin_set_commission_policy(5, 500)');
      });

    it('a rate written straight into config moves the shops that follow it', async () => {
      const id = await shop('بيتبع التعديل المباشر');
      await db.query(`update config set value = '8'::jsonb
                       where key = 'default_commission_percent'`);
      assert.equal((await row(id)).revenue_value, 800);
      assert.equal((await row(id)).commission_custom, false);
      await db.query('select public.admin_set_commission_policy(5, 500)');
      assert.equal((await row(id)).revenue_value, 500);
    });

    it('a rate or an alert that is not a number is refused at the door', async () => {
      await assert.rejects(() => db.query(`update config set value = '"كتير"'::jsonb
                                            where key = 'commission_alert_pounds'`),
        /must be a number/);
      await assert.rejects(() => db.query(`update config set value = '90'::jsonb
                                            where key = 'default_commission_percent'`),
        /out of range/);
    });
  });

  describe('told when it runs high', () => {
    const owe = (id, piastres) => db.query(
      `begin;
       select set_config('app.server_mode', 'on', true);
       update merchants set commission_owed = ${piastres} where id = '${id}';
       commit;`);

    const alerts = async (id) => (await db.query(
      `select uid from push_outbox where data->>'kind' = 'commissionDue'
         and data->>'merchantId' = $1`, [id])).rows;

    it('crossing 500 ج tells the owner of the shop and every admin, once', async () => {
      const id = await shop('فاتت الحد');
      await db.query(
        `insert into staff (uid, scope, role, merchant_id, is_active)
         values ($1, 'merchant', 'owner', $2, true)`, [OWNER, id]);

      await db.exec(`begin; select set_config('app.server_mode','on',true);
        update merchants set commission_owed = 40000 where id = '${id}'; commit;`);
      assert.equal((await alerts(id)).length, 0, 'under the line: nothing');

      await db.exec(`begin; select set_config('app.server_mode','on',true);
        update merchants set commission_owed = 51000 where id = '${id}'; commit;`);
      const first = await alerts(id);
      assert.ok(first.some((r) => r.uid === OWNER));
      assert.ok(first.some((r) => r.uid === ADMIN));

      await db.exec(`begin; select set_config('app.server_mode','on',true);
        update merchants set commission_owed = 60000 where id = '${id}'; commit;`);
      assert.equal((await alerts(id)).length, first.length, 'already over: not again');
    });

    it('the weekly reminder names every shop that owes, and nobody who does not', async () => {
      const owes = await shop('عليه');
      const clear = await shop('خالص');
      await db.exec(`begin; select set_config('app.server_mode','on',true);
        update merchants set commission_owed = 12000 where id = '${owes}'; commit;`);

      const n = (await db.query('select public.remind_commission_due() as n')).rows[0].n;
      assert.ok(n >= 1);
      const toAdmin = (await db.query(
        `select body from push_outbox where uid = $1 and title = 'تحصيل العمولة'
          order by created_at desc limit 1`, [ADMIN])).rows[0];
      assert.match(toAdmin.body, /محل عليهم/);
      assert.equal((await alerts(clear)).length, 0);
    });
  });
});
