import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { freshDatabase } from './harness.mjs';

/**
 * The admin modules' server half: config and plans writes, argued with on PGlite.
 *
 * Both functions are SECURITY DEFINER and check `is_admin()` plus a non-null
 * `auth.uid()`. The harness stubs `auth.jwt()` to say admin, so the only thing that
 * stands in the way is `auth.uid()` returning null; we override it to a real account so
 * the happy path — the upsert and the audit row — is what gets tested. Whether a
 * non-admin is refused is a boundary question that belongs in test/stack.
 */

const actor = '00000000-0000-0000-0000-000000000001';

let db;

before(async () => {
  db = await freshDatabase();

  await db.exec(`
    create or replace function auth.uid() returns uuid
      language sql stable as $fn$ select '${actor}'::uuid $fn$;
  `);
  await db.query('insert into auth.users (id) values ($1) on conflict (id) do nothing', [
    actor,
  ]);
});

after(() => db?.close());

describe('admin_set_config', () => {
  it('upserts keys and stamps an audit row', async () => {
    const saved = await db.query(
      "select public.admin_set_config('{\"otp_enabled\": true, \"marketing_push_per_week\": 7}'::jsonb) as config",
    );

    const flag = await db.query("select value from config where key = 'otp_enabled'");
    assert.equal(flag.rows[0].value, true);

    const cap = await db.query(
      "select value from config where key = 'marketing_push_per_week'",
    );
    assert.equal(cap.rows[0].value, 7);
    assert.equal(saved.rows[0].config.otp_enabled, true);
    assert.equal(saved.rows[0].config.marketing_push_per_week, 7);

    const audit = await db.query(
      "select action, actor from audit_log where action = 'config.set'",
    );
    assert.equal(audit.rows.length, 1);
    assert.equal(audit.rows[0].actor, actor);
  });

  const save = (values) => db.query(
    'select public.admin_set_config($1::jsonb) as config',
    [JSON.stringify(values)],
  );

  it('rejects an out-of-range integer', async () => {
    await assert.rejects(save({ accept_timeout_minutes: 61 }), /accept_timeout_minutes/);
  });

  it('rejects a negative integer', async () => {
    await assert.rejects(save({ marketing_push_per_week: -1 }), /marketing_push_per_week/);
  });

  it('rejects contradictory delivery fees supplied together', async () => {
    await assert.rejects(
      save({ delivery_fee_min: 2000, delivery_fee_max: 1000 }),
      /delivery_fee_max/,
    );
  });

  it('compares one supplied delivery fee with the stored other half', async () => {
    await save({ delivery_fee_min: 500, delivery_fee_max: 2000 });

    await assert.rejects(save({ delivery_fee_max: 499 }), /delivery_fee_max/);
  });

  it('rejects malformed versions and non-boolean flags', async () => {
    await assert.rejects(
      save({ customer_min_supported_version: '1.2.3.4' }),
      /customer_min_supported_version/,
    );
    await assert.rejects(save({ otp_enabled: 1 }), /otp_enabled/);
  });

  it('passes unknown keys through and returns them', async () => {
    const result = await save({ future_config_key: { enabled: true } });

    assert.deepEqual(result.rows[0].config.future_config_key, { enabled: true });
  });

  it('writes nothing from a batch containing one invalid value', async () => {
    await db.query("delete from config where key = 'atomic_good_key'");

    await assert.rejects(
      save({ atomic_good_key: 'must not land', min_ratings_to_show: 1001 }),
      /min_ratings_to_show/,
    );

    const good = await db.query("select value from config where key = 'atomic_good_key'");
    assert.equal(good.rows.length, 0);
  });
});

describe('admin_set_plan', () => {
  it('creates a plan and stamps an audit row', async () => {
    await db.query(
      "select public.admin_set_plan('basic', 'أساسية', 30000, '{\"maxItems\": 100}'::jsonb, 1, true)",
    );

    const plan = await db.query(
      "select name, price_monthly, features, is_active from plans where id = 'basic'",
    );
    assert.equal(plan.rows[0].name, 'أساسية');
    assert.equal(plan.rows[0].price_monthly, 30000);
    assert.deepEqual(plan.rows[0].features, { maxItems: 100 });
    assert.equal(plan.rows[0].is_active, true);

    const audit = await db.query(
      "select action, detail from audit_log where action = 'plan.set'",
    );
    assert.equal(audit.rows.length, 1);
    assert.equal(audit.rows[0].detail.planId, 'basic');
  });

  it('replacing an existing id updates rather than colliding', async () => {
    await db.query(
      "select public.admin_set_plan('basic', 'أساسية', 45000, '{\"maxItems\": 250}'::jsonb, 1, true)",
    );

    const plan = await db.query(
      "select count(*)::int as n, min(price_monthly) as price from plans where id = 'basic'",
    );
    assert.equal(plan.rows[0].n, 1);
    assert.equal(plan.rows[0].price, 45000);
  });

  it('refuses a negative price', async () => {
    await assert.rejects(
      db.query("select public.admin_set_plan('free', 'مجاني', -1, '{}'::jsonb, 0, true)"),
      /non-negative/,
    );
  });
});
