import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * The two functions that move money, and who is allowed to call them.
 *
 * Both declare `app.server_mode`, which stands every column guard down — that is the
 * point of them, and it is why they need a guard of their own. The second pre-launch
 * audit found neither had one: a merchant owner's call reached the wallet update and was
 * stopped only by the audit_log policy on the last statement. Blocked by accident, in
 * other words, by a policy on a different table.
 *
 * And the log believed the caller: `p_recorded_by` was a parameter, so it recorded
 * whoever was named. A log that can be lied to is not evidence, and answering "who did
 * this" when money is disputed is the only reason it exists.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

const uid = async () => (await q(
  "insert into auth.users (id, instance_id, aud, role) values (gen_random_uuid(), " +
  "'00000000-0000-0000-0000-000000000000','authenticated','authenticated') returning id",
)).rows[0].id;

/** Runs `fn` as one identity, in a transaction that is always rolled back. */
async function as(identity, fn) {
  await q('begin');
  try {
    await q("select set_config('role','authenticated',true)");
    await q("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
      sub: identity.uid, role: 'authenticated', app_metadata: identity.claims ?? {},
    })]);
    return await fn();
  } finally {
    await q('rollback');
  }
}

/** `pg` carries SQLSTATE on `error.code`, never in the message. */
const refusedAs = (code) => (error) => {
  assert.equal(error.code, code,
    `expected SQLSTATE ${code}, got ${error.code}: ${error.message}`);
  return true;
};

describe('the functions that move money', () => {
  let city, zone, merchant, owner, customer, admin, someoneElse;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = 'money-' + Date.now();
    await q('insert into cities (id,name) values ($1,$2)', [city, 'مدينة الفلوس']);
    zone = (await q('insert into zones (city_id,name) values ($1,$2) returning id',
                    [city, 'منطقة'])).rows[0].id;
    merchant = (await q(
      `insert into merchants (city_id,type,name,zone_id,phone,status,revenue_model,
                              revenue_value,wallet_balance)
       values ($1,'restaurant','مطعم',$2,'0100','approved','prepaid',500,1000)
       returning id`, [city, zone])).rows[0].id;

    // Its own plan, not the seed's: a suite that leans on seeded data fails after a
    // `db reset` for a reason that has nothing to do with what it is testing.
    await q("insert into plans (id,name,price_monthly) values ($1,'أساسية',25000) " +
            'on conflict (id) do nothing', ['money-basic']);

    owner = await uid();
    await q("insert into staff (uid,scope,role,merchant_id) values ($1,'merchant','owner',$2)",
            [owner, merchant]);
    customer = await uid();
    await q('insert into users (id) values ($1) on conflict (id) do nothing', [customer]);
    admin = await uid();
    await q("insert into staff (uid,scope,role) values ($1,'platform','admin')", [admin]);
    someoneElse = await uid();
  });

  after(async () => {
    await q('delete from audit_log where merchant_id = $1', [merchant]).catch(() => {});
    await q("delete from plans where id = 'money-basic'").catch(() => {});
    await q('delete from subscriptions where merchant_id = $1', [merchant]).catch(() => {});
    await q('delete from staff where uid = any($1)', [[owner, admin]]).catch(() => {});
    await q('delete from users where id = $1', [customer]).catch(() => {});
    await q('delete from merchants where city_id = $1', [city]).catch(() => {});
    await q('delete from zones where city_id = $1', [city]).catch(() => {});
    await q('delete from cities where id = $1', [city]).catch(() => {});
    await db.end();
  });

  const ADMIN = () => ({ uid: admin, claims: { admin: true, role: 'admin', scope: 'platform' } });
  const OWNER = () => ({ uid: owner,
                         claims: { role: 'owner', scope: 'merchant', merchant_id: merchant } });

  describe('top_up_wallet', () => {
    // Under prepaid the wallet is what the platform deducts from. A merchant who can
    // fill their own has free service, for ever.
    it('a merchant owner cannot fill their own wallet', async () => {
      await assert.rejects(
        as(OWNER(), () => q('select top_up_wallet($1,$2,$3)', [merchant, 9999999, owner])),
        refusedAs('42501'),
      );
    });

    it('an ordinary customer cannot fill anybody\'s', async () => {
      await assert.rejects(
        as({ uid: customer }, () =>
          q('select top_up_wallet($1,$2,$3)', [merchant, 9999999, customer])),
        refusedAs('42501'),
      );
    });

    it('an admin can, and the balance moves', async () => {
      await as(ADMIN(), async () => {
        await q('select top_up_wallet($1,$2,$3)', [merchant, 2500, admin]);
        const r = await q('select wallet_balance from merchants where id=$1', [merchant]);
        assert.equal(r.rows[0].wallet_balance, 3500);
      });
    });

    // The one question the log exists to answer is "who did this", and it was answering
    // with whatever the caller typed.
    it('the log records who really called, not who they named', async () => {
      await as(ADMIN(), async () => {
        await q('select top_up_wallet($1,$2,$3)', [merchant, 100, someoneElse]);
        const r = await q(
          "select actor from audit_log where action='topUpWallet' and merchant_id=$1 " +
          'order by at desc limit 1', [merchant]);
        assert.equal(r.rows[0].actor, admin,
          'the audit log must not believe the caller');
      });
    });

    it('a top-up of nothing is refused', async () => {
      await assert.rejects(
        as(ADMIN(), () => q('select top_up_wallet($1,$2,$3)', [merchant, 0, admin])),
        refusedAs('23514'),
      );
    });

    it('a merchant that does not exist is named as not found', async () => {
      await assert.rejects(
        as(ADMIN(), () => q('select top_up_wallet($1,$2,$3)',
                            ['00000000-0000-0000-0000-000000000000', 100, admin])),
        refusedAs('P0002'),
      );
    });
  });

  describe('record_subscription_payment', () => {
    it('a merchant owner cannot give themselves a plan', async () => {
      await assert.rejects(
        as(OWNER(), () => q('select record_subscription_payment($1,$2,$3,$4,$5)',
                            [merchant, 'money-basic', 0, 12, owner])),
        refusedAs('42501'),
      );
    });

    it('an ordinary customer cannot either', async () => {
      await assert.rejects(
        as({ uid: customer }, () => q('select record_subscription_payment($1,$2,$3,$4,$5)',
                                      [merchant, 'money-basic', 0, 12, customer])),
        refusedAs('42501'),
      );
    });

    it('an admin can, and the plan lands on the merchant', async () => {
      await as(ADMIN(), async () => {
        await q('select record_subscription_payment($1,$2,$3,$4,$5)',
                [merchant, 'money-basic', 25000, 1, admin]);
        const r = await q('select plan_id from merchants where id=$1', [merchant]);
        assert.equal(r.rows[0].plan_id, 'money-basic');
      });
    });

    it('the receipt and the log both name the real caller', async () => {
      await as(ADMIN(), async () => {
        await q('select record_subscription_payment($1,$2,$3,$4,$5)',
                [merchant, 'money-basic', 25000, 1, someoneElse]);

        const term = await q(
          'select recorded_by from subscriptions where merchant_id=$1 ' +
          'order by started_at desc limit 1', [merchant]);
        assert.equal(term.rows[0].recorded_by, admin, 'the receipt names who recorded it');

        const log = await q(
          "select actor from audit_log where action='recordSubscriptionPayment' " +
          'and merchant_id=$1 order by at desc limit 1', [merchant]);
        assert.equal(log.rows[0].actor, admin);
      });
    });
  });

  // The door beside the door. Renaming the priced half carried its old grants with it,
  // and leaving those in place would have handed every signed-in customer a way past the
  // guard that was just added.
  describe('the priced half of place_order', () => {
    it('is not callable by anybody', async () => {
      await assert.rejects(
        as({ uid: customer }, () => q('select place_order_priced($1::jsonb)', ['{}'])),
        refusedAs('42501'),
      );
    });

    it('not even by a merchant owner', async () => {
      await assert.rejects(
        as(OWNER(), () => q('select place_order_priced($1::jsonb)', ['{}'])),
        refusedAs('42501'),
      );
    });
  });
});
