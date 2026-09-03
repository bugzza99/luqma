import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

async function as(identity, fn) {
  await q('begin');
  try {
    const claims = JSON.stringify({
      sub: identity.uid,
      role: 'authenticated',
      app_metadata: identity.claims ?? {},
    });
    await q("select set_config('role', 'authenticated', true)");
    await q("select set_config('request.jwt.claims', $1, true)", [claims]);
    return await fn();
  } finally {
    await q('rollback');
  }
}

const uid = async () => (await q(
  `insert into auth.users (id, instance_id, aud, role)
   values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000',
           'authenticated', 'authenticated')
   returning id`,
)).rows[0].id;

const refusedAs = (code) => (error) => {
  assert.equal(
    error.code,
    code,
    `expected SQLSTATE ${code}, got ${error.code}: ${error.message}`,
  );
  return true;
};

const ADMIN_CLAIMS = { role: 'admin', scope: 'platform', admin: true };

describe('admin_set_config validation', () => {
  let adminUid;
  let customerUid;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();
    adminUid = await uid();
    customerUid = await uid();
    await q("insert into staff (uid, scope, role) values ($1, 'platform', 'admin')", [
      adminUid,
    ]);
  });

  after(async () => {
    await q('delete from staff where uid = $1', [adminUid]);
    await q('delete from users where id = any($1::uuid[])', [[adminUid, customerUid]]);
    await q('delete from auth.users where id = any($1::uuid[])', [[adminUid, customerUid]]);
    await db.end();
  });

  const save = (identity, values) => as(identity, () => q(
    'select public.admin_set_config($1::jsonb) as config',
    [JSON.stringify(values)],
  ));

  const admin = () => ({ uid: adminUid, claims: ADMIN_CLAIMS });

  it('saves valid values and returns the full stored config', async () => {
    // Two writes in one transaction: the second call's return must still carry the
    // key the first one wrote, proving the response is the whole config table rather
    // than an echo of the current payload. Nothing here assumes a pre-seeded row.
    const result = await as(admin(), async () => {
      await q(
        'select public.admin_set_config($1::jsonb)',
        [JSON.stringify({ support_whatsapp: '0192' })],
      );
      return q('select public.admin_set_config($1::jsonb) as config', [
        JSON.stringify({
          accept_timeout_minutes: 12,
          customer_update_url: 'https://updates.example/customer.apk',
        }),
      ]);
    });

    assert.equal(result.rows[0].config.accept_timeout_minutes, 12);
    assert.equal(
      result.rows[0].config.customer_update_url,
      'https://updates.example/customer.apk',
    );
    assert.equal(
      result.rows[0].config.support_whatsapp,
      '0192',
      'the return is the whole config, including keys written earlier',
    );
  });

  it('rejects out-of-range and negative integers', async () => {
    await assert.rejects(
      save(admin(), { accept_timeout_minutes: 61 }),
      refusedAs('23514'),
    );
    await assert.rejects(
      save(admin(), { marketing_push_per_week: -1 }),
      refusedAs('23514'),
    );
  });

  it('rejects contradictory delivery fees in one call', async () => {
    await assert.rejects(
      save(admin(), { delivery_fee_min: 2000, delivery_fee_max: 1000 }),
      refusedAs('23514'),
    );
  });

  it('compares one fee in the call with the other fee in the table', async () => {
    await as(admin(), async () => {
      await q(
        "select public.admin_set_config('{\"delivery_fee_min\":500,\"delivery_fee_max\":2000}'::jsonb)",
      );
      await assert.rejects(
        q("select public.admin_set_config('{\"delivery_fee_max\":499}'::jsonb)"),
        refusedAs('23514'),
      );
    });
  });

  it('rejects malformed versions and non-boolean flags', async () => {
    await assert.rejects(
      save(admin(), { admin_min_supported_version: 'v2' }),
      refusedAs('23514'),
    );
    await assert.rejects(
      save(admin(), { online_payment_enabled: 1 }),
      refusedAs('23514'),
    );
  });

  it('allows unknown keys', async () => {
    const result = await save(admin(), { future_stack_key: ['kept'] });
    assert.deepEqual(result.rows[0].config.future_stack_key, ['kept']);
  });

  it('rejects non-admin callers', async () => {
    await assert.rejects(
      save({ uid: customerUid }, { update_message: 'no' }),
      refusedAs('42501'),
    );
  });

  it('writes none of a mixed valid-invalid batch', async () => {
    await as(admin(), async () => {
      await q('savepoint before_invalid_batch');
      await assert.rejects(
        q(
          'select public.admin_set_config($1::jsonb)',
          [JSON.stringify({ stack_atomic_good: 'no', splash_min_millis: 5001 })],
        ),
        refusedAs('23514'),
      );
      await q('rollback to savepoint before_invalid_batch');

      const row = await q("select value from config where key = 'stack_atomic_good'");
      assert.equal(row.rowCount, 0);
    });
  });
});
