import { describe, it } from 'node:test';
import { deepStrictEqual, strictEqual } from 'node:assert';
import { freshDatabase } from './harness.mjs';

/**
 * merchants.plan_expires_at — the one current truth for a merchant's plan.
 *
 * The nightly pass used to reread every receipt every night to answer "who stopped
 * paying". With the end date on the merchant itself, the pass is a range query and the
 * answer cannot drift from the payment that wrote it. These tests prove both halves:
 * recording a payment moves the date, and the pass clears exactly the rows it should.
 */
describe('plan_expires_at', () => {
  /** @returns {Promise<import('@electric-sql/pglite').PGlite>} */
  const db = async () => {
    const d = await freshDatabase();
    // The admin identity the payment is recorded under: auth.jwt() already says admin
    // (the harness stub), so auth.uid() only needs a real account to name.
    await d.query(
      `insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000aa')`,
    );
    await d.query(`
      create or replace function auth.uid() returns uuid
        language sql stable as $fn$ select '00000000-0000-0000-0000-0000000000aa'::uuid $fn$
    `);
    await d.query(`insert into cities (id, name) values ('edku', 'إدكو')`);
    await d.query(`
      insert into zones (id, city_id, name, default_delivery_fee)
      values ('00000000-0000-0000-0000-000000000001', 'edku', 'وسط', 1000)
    `);
    await d.query(`
      insert into plans (id, name, price_monthly)
      values ('free', 'مجانية', 0), ('basic', 'أساسية', 25000),
             ('premium', 'مميزة', 60000)
    `);
    return d;
  };

  const merchant = (d) =>
    d.query(
      `insert into merchants (id, city_id, zone_id, type, name, phone, status)
       values (gen_random_uuid(), 'edku',
               '00000000-0000-0000-0000-000000000001',
               'restaurant', 'مطعم', '01000000000', 'approved')
       returning id`,
    ).then((r) => r.rows[0].id);

  it('recording a payment writes the term end onto the merchant', async () => {
    const d = await db();
    const m = await merchant(d);

    await d.query(
      "select record_subscription_payment($1, 'basic', 25000, 3)", [m],
    );

    const row = (await d.query(
      'select plan_id, plan_expires_at from merchants where id = $1', [m],
    )).rows[0];
    strictEqual(row.plan_id, 'basic');
    strictEqual(row.plan_expires_at instanceof Date, true);
  });

  it('a renewal extends the same field rather than leaving two truths', async () => {
    const d = await db();
    const m = await merchant(d);

    await d.query("select record_subscription_payment($1, 'basic', 25000, 1)", [m]);
    const first = (await d.query(
      'select plan_expires_at from merchants where id = $1', [m],
    )).rows[0].plan_expires_at;

    await d.query("select record_subscription_payment($1, 'premium', 60000, 2)", [m]);
    const second = (await d.query(
      'select plan_id, plan_expires_at from merchants where id = $1', [m],
    )).rows[0];

    strictEqual(second.plan_id, 'premium');
    strictEqual(second.plan_expires_at > first, true);
  });

  it('the nightly pass clears an expired merchant and their date together', async () => {
    const d = await db();
    const m = await merchant(d);

    // Expired on paper: the pass must catch it.
    await d.query(
      `update merchants set plan_id = 'basic',
                           plan_expires_at = now() - interval '1 day'
        where id = $1`, [m],
    );

    const moved = (await d.query('select downgrade_expired_subscriptions()'))
      .rows[0].downgrade_expired_subscriptions;
    strictEqual(moved, 1);

    const row = (await d.query(
      'select plan_id, plan_expires_at from merchants where id = $1', [m],
    )).rows[0];
    strictEqual(row.plan_id, null);
    strictEqual(row.plan_expires_at, null);
  });

  it('the pass leaves a paid-up merchant entirely alone', async () => {
    const d = await db();
    const m = await merchant(d);

    await d.query(
      `update merchants set plan_id = 'premium',
                           plan_expires_at = now() + interval '20 days'
        where id = $1`, [m],
    );

    const moved = (await d.query('select downgrade_expired_subscriptions()'))
      .rows[0].downgrade_expired_subscriptions;
    strictEqual(moved, 0);

    const row = (await d.query(
      'select plan_id, plan_expires_at from merchants where id = $1', [m],
    )).rows[0];
    strictEqual(row.plan_id, 'premium');
  });

  it('the pass never touches a merchant with no date at all', async () => {
    const d = await db();
    const m = await merchant(d);

    await d.query(`update merchants set plan_id = 'free' where id = $1`, [m]);

    const moved = (await d.query('select downgrade_expired_subscriptions()'))
      .rows[0].downgrade_expired_subscriptions;
    strictEqual(moved, 0);

    const row = (await d.query(
      'select plan_id, plan_expires_at from merchants where id = $1', [m],
    )).rows[0];
    strictEqual(row.plan_id, 'free');
    strictEqual(row.plan_expires_at, null);
  });
});
