import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * Taking the money.
 *
 * The settlement charges; this is the half that collects. Every question below is about
 * a boundary — who may call it, whose name goes in the log, and what the guard on
 * `commission_owed` does when it is not an admin asking — so it runs against the real
 * stack rather than PGlite.
 *
 * The one that matters most is the log. The second pre-launch audit found
 * `record_subscription_payment` taking the actor as a parameter and believing it, so it
 * recorded whoever the caller named. Answering "who took this money" is the only reason
 * the log exists, and a log that can be lied to does not answer it.
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

const refusedAs = (code) => (error) => {
  assert.equal(error.code, code,
    `expected SQLSTATE ${code}, got ${error.code}: ${error.message}`);
  return true;
};

describe('collecting a commission', () => {
  let city, zone, merchant, admin, otherAdmin, owner, customer;

  const owed = async () => (await q(
    'select commission_owed from merchants where id=$1', [merchant])).rows[0].commission_owed;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = 'collect-' + Date.now();
    await q('insert into cities (id,name) values ($1,$2)', [city, 'مدينة التحصيل']);
    zone = (await q('insert into zones (city_id,name) values ($1,$2) returning id',
                    [city, 'منطقة'])).rows[0].id;
    merchant = (await q(
      `insert into merchants (city_id,type,name,zone_id,phone,status,revenue_model,
                              revenue_value,commission_owed)
       values ($1,'restaurant','مطعم',$2,'0100','approved','commission',1000,47500)
       returning id`, [city, zone])).rows[0].id;

    admin = await uid();
    await q("insert into staff (uid,scope,role) values ($1,'platform','admin')", [admin]);
    otherAdmin = await uid();
    await q("insert into staff (uid,scope,role) values ($1,'platform','admin')", [otherAdmin]);
    owner = await uid();
    await q("insert into staff (uid,scope,role,merchant_id) values ($1,'merchant','owner',$2)",
            [owner, merchant]);
    customer = await uid();
    await q('insert into users (id) values ($1) on conflict (id) do nothing', [customer]);
  });

  after(async () => {
    for (const sql of [
      'delete from commission_payments where merchant_id in (select id from merchants where city_id=$1)',
      'delete from audit_log where merchant_id in (select id from merchants where city_id=$1)',
      'delete from merchants where city_id = $1',
      'delete from zones where city_id = $1',
      'delete from cities where id = $1',
    ]) await q(sql, [city]).catch((e) => console.error('teardown:', e.message));
    await q('delete from staff where uid = any($1)', [[admin, otherAdmin, owner]])
      .catch(() => {});
    await q('delete from users where id = $1', [customer]).catch(() => {});
    await db.end();
  });

  const ADMIN = () => ({ uid: admin, claims: { admin: true, role: 'admin', scope: 'platform' } });
  const OWNER = () => ({ uid: owner,
                         claims: { role: 'owner', scope: 'merchant', merchant_id: merchant } });

  describe('who may take it', () => {
    // A merchant who can record their own payments has free service, for ever.
    it('a merchant owner cannot clear their own debt', async () => {
      await assert.rejects(
        as(OWNER(), () => q('select record_commission_payment($1,$2)', [merchant, 47500])),
        refusedAs('42501'),
      );
    });

    it('nor can an ordinary customer', async () => {
      await assert.rejects(
        as({ uid: customer }, () =>
          q('select record_commission_payment($1,$2)', [merchant, 100])),
        refusedAs('42501'),
      );
    });

    it('and nobody at all is refused before anything is written', async () => {
      await assert.rejects(
        as({ uid: customer }, () =>
          q('select record_commission_payment($1,$2)', [merchant, 100])),
        refusedAs('42501'),
      );
      assert.equal(await owed(), 47500, 'the balance did not move');
    });
  });

  describe('what it records', () => {
    it('an admin collects, and the debt falls by exactly that much', async () => {
      await as(ADMIN(), async () => {
        await q('select record_commission_payment($1,$2)', [merchant, 20000]);
        const r = await q('select commission_owed from merchants where id=$1', [merchant]);
        assert.equal(r.rows[0].commission_owed, 27500);
      });
      assert.equal(await owed(), 47500, 'and the transaction was rolled back');
    });

    it('the receipt carries the figure and the note', async () => {
      await as(ADMIN(), async () => {
        await q('select record_commission_payment($1,$2,$3)',
                [merchant, 20000, '  دفع كاش، الباقي الأسبوع الجاي  ']);
        const r = await q(
          'select amount, note, recorded_by from commission_payments where merchant_id=$1',
          [merchant]);
        assert.equal(r.rows[0].amount, 20000);
        // Trimmed: a note that is spaces is not a note, and it would render as an empty
        // line under the receipt rather than as nothing.
        assert.equal(r.rows[0].note, 'دفع كاش، الباقي الأسبوع الجاي');
        assert.equal(r.rows[0].recorded_by, admin);
      });
    });

    it('an empty note is stored as none at all', async () => {
      await as(ADMIN(), async () => {
        await q('select record_commission_payment($1,$2,$3)', [merchant, 100, '   ']);
        const r = await q('select note from commission_payments where merchant_id=$1',
                          [merchant]);
        assert.equal(r.rows[0].note, null);
      });
    });

    // Answering "who took this money" is the only reason the log exists.
    it('the log names the caller, not whoever was passed in', async () => {
      await as(ADMIN(), async () => {
        await q('select record_commission_payment($1,$2)', [merchant, 500]);
        const r = await q(
          "select actor, detail from audit_log where merchant_id=$1 and action='recordCommissionPayment'",
          [merchant]);
        assert.equal(r.rows[0].actor, admin);
        assert.notEqual(r.rows[0].actor, otherAdmin);
        assert.equal(r.rows[0].detail.amount, 500);
        assert.equal(r.rows[0].detail.remaining, 47000);
      });
    });

    it('and it hands back the new balance rather than making the screen ask again',
       async () => {
      await as(ADMIN(), async () => {
        const r = await q('select record_commission_payment($1,$2) as out',
                          [merchant, 7500]);
        assert.equal(r.rows[0].out.remaining, 40000);
        assert.equal(r.rows[0].out.payment.amount, 7500);
      });
    });
  });

  describe('the figures it refuses and the ones it does not', () => {
    it('zero is not a collection', async () => {
      await assert.rejects(
        as(ADMIN(), () => q('select record_commission_payment($1,$2)', [merchant, 0])),
        refusedAs('23514'),
      );
    });

    // A negative payment is a refund, which is a different act with a different
    // conversation behind it. One screen that can both collect and hand back without
    // saying which is a screen nobody can audit.
    it('and neither is a negative one', async () => {
      await assert.rejects(
        as(ADMIN(), () => q('select record_commission_payment($1,$2)', [merchant, -500])),
        refusedAs('23514'),
      );
    });

    // An admin standing in a shop takes what is handed over. A merchant who rounds up by
    // five pounds must not meet an error with the cash already on the counter.
    it('more than is owed is allowed, and leaves credit behind', async () => {
      await as(ADMIN(), async () => {
        const r = await q('select record_commission_payment($1,$2) as out',
                          [merchant, 50000]);
        assert.equal(r.rows[0].out.remaining, -2500,
          'the platform now holds credit, which the next delivery eats into');
      });
    });

    it('a merchant that does not exist is named as such', async () => {
      await assert.rejects(
        as(ADMIN(), () => q('select record_commission_payment($1,$2)',
                            ['00000000-0000-0000-0000-0000000000ff', 100])),
        refusedAs('P0002'),
      );
    });
  });

  describe('the guards afterwards', () => {
    // The function declares server mode to reach `commission_owed`, and puts it back.
    // Leaving it standing would open every column guard for whatever ran next in the
    // same transaction.
    it('server mode does not survive the collection', async () => {
      await as(ADMIN(), async () => {
        await q('select record_commission_payment($1,$2)', [merchant, 100]);
        const r = await q(
          "select coalesce(current_setting('app.server_mode', true),'') as m");
        assert.notEqual(r.rows[0].m, 'on');
      });
    });

    it('nobody writes the receipts table directly', async () => {
      await assert.rejects(
        as(OWNER(), () => q(
          'insert into commission_payments (merchant_id, amount, recorded_by) ' +
          'values ($1,$2,$3)', [merchant, 99999, owner])),
        refusedAs('42501'),
      );
    });

    it('but a merchant can read their own', async () => {
      // Written as the admin, read as the owner — the two halves of the policy, in the
      // one transaction so the row exists to be read.
      await q('begin');
      try {
        await q("select set_config('role','authenticated',true)");
        await q("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
          sub: admin, role: 'authenticated',
          app_metadata: { admin: true, role: 'admin', scope: 'platform' },
        })]);
        await q('select record_commission_payment($1,$2)', [merchant, 1500]);

        await q("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
          sub: owner, role: 'authenticated',
          app_metadata: { role: 'owner', scope: 'merchant', merchant_id: merchant },
        })]);
        const mine = await q('select amount from commission_payments where merchant_id=$1',
                             [merchant]);
        assert.equal(mine.rows.length, 1);
        assert.equal(mine.rows[0].amount, 1500);
      } finally { await q('rollback'); }
    });
  });
});
