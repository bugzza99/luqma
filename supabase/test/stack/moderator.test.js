import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { Client } from 'pg';

/**
 * A moderator is an admin except money, deletion, and who anybody is.
 *
 * `moderator` has been in the schema, in `StaffRole` and on the admin's own staff form
 * since Phase 2, and the access gate only ever asked `is_admin()` — which a moderator did
 * not satisfy. Creating one produced an account that opened nothing and said nothing
 * about it.
 *
 * The fix grants first and excepts afterwards: `is_admin()` widens to cover both roles,
 * so all 47 policies and 44 functions that ask it keep working unchanged, and the money,
 * the deletions and the roster are taken back by triggers and by a narrower
 * `is_platform_admin()`.
 *
 * That shape is only provable here. PGlite has no RLS, so it can show the triggers firing
 * and cannot show whether a moderator can *reach* anything at all — and "the policy
 * filtered every row away" and "the moderator may edit this" look identical from a
 * client: an empty list either way.
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

describe('a moderator is an admin except', () => {
  let city, zone, merchant, admin, moderator, media;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = 'mod-' + Date.now();
    await q('insert into cities (id,name) values ($1,$2)', [city, 'مدينة المشرف']);
    zone = (await q('insert into zones (city_id,name) values ($1,$2) returning id',
                    [city, 'منطقة'])).rows[0].id;
    // Owing, so that a write of zero to `commission_owed` is a change. Against a shop that
    // owes nothing the same write changes nothing, and a test refusing it would pass or fail
    // for reasons unrelated to the guard.
    merchant = (await q(
      `insert into merchants (city_id,type,name,zone_id,phone,status,commission_owed)
       values ($1,'restaurant','مطعم',$2,'0100','approved',12000) returning id`,
      [city, zone])).rows[0].id;

    admin = await uid();
    await q("insert into staff (uid,scope,role) values ($1,'platform','admin')", [admin]);
    moderator = await uid();
    await q("insert into staff (uid,scope,role) values ($1,'platform','moderator')",
            [moderator]);

    media = (await q(
      `insert into media (kind,url,status,uploaded_by) values ('menuItem',$1,'pending',$2)
       returning id`, [`https://example.test/${city}.jpg`, admin])).rows[0].id;
  });

  after(async () => {
    await q('delete from audit_log where actor = any($1)', [[admin, moderator]]).catch(() => {});
    // Orders before their shop: `orders.merchant_id` is `on delete restrict`.
    await q(`delete from orders where merchant_id in (
               select id from merchants where city_id = $1)`, [city]).catch(() => {});
    await q('delete from media where id = $1', [media]).catch(() => {});
    await q('delete from staff where uid = any($1)', [[admin, moderator]]).catch(() => {});
    await q('delete from merchants where city_id = $1', [city]).catch(() => {});
    await q('delete from zones where city_id = $1', [city]).catch(() => {});
    await q('delete from cities where id = $1', [city]).catch(() => {});
    await db.end();
  });

  const ADMIN = () => ({ uid: admin,
                         claims: { admin: true, role: 'admin', scope: 'platform' } });
  // The claims the hook really mints for a moderator, asserted below before anything
  // leans on them.
  const MOD = () => ({ uid: moderator,
                       claims: { admin: true, role: 'moderator', scope: 'platform' } });

  describe('the token', () => {
    it('carries the admin claim, which is what lets them in at all', async () => {
      const meta = (await q(
        `select custom_access_token_hook(jsonb_build_object(
           'user_id', $1::uuid,
           'claims', jsonb_build_object('app_metadata','{}'::jsonb)
         )) -> 'claims' -> 'app_metadata' as m`, [moderator])).rows[0].m;

      assert.equal(meta.admin, true, 'without this they sign in and land on «مالكش صلاحية»');
      assert.equal(meta.role, 'moderator', 'and the screens still know which they are');
    });

    it('answers the wide question yes and the narrow one no', async () => {
      await as(MOD(), async () => {
        const r = (await q('select is_admin() as wide, is_platform_admin() as narrow')).rows[0];
        assert.equal(r.wide, true);
        assert.equal(r.narrow, false);
      });
      await as(ADMIN(), async () => {
        const r = (await q('select is_admin() as wide, is_platform_admin() as narrow')).rows[0];
        assert.equal(r.wide, true);
        assert.equal(r.narrow, true);
      });
    });

    // The reverse of a promotion is what matters: an admin demoted an hour ago carries a
    // token that still says admin, and the till has to close now rather than when the JWT
    // expires. Same lesson as a dismissal being a boundary change, not a claim change.
    it('reads the role from the row, not from the claim', async () => {
      await as({ uid: moderator, claims: { admin: true, role: 'admin', scope: 'platform' } },
        async () => {
          assert.equal((await q('select is_platform_admin() as a')).rows[0].a, false,
            'a claim that says admin does not make one');
        });
    });
  });

  describe('the work a moderator is for', () => {
    // The reach, not a trigger. A policy that allows less than the query asks for returns
    // nothing rather than refusing, so "may edit" and "sees an empty screen" are only
    // distinguishable by counting what came back.
    it('sees the shops', async () => {
      await as(MOD(), async () => {
        const r = await q('select count(*)::int as n from merchants where id = $1', [merchant]);
        assert.equal(r.rows[0].n, 1, 'an empty list reads as «مفيش مطاعم», which is a lie');
      });
    });

    it('corrects a shop, and the row really changes', async () => {
      await as(MOD(), async () => {
        const r = await q(
          "update merchants set name = 'الاسم بعد التصحيح' where id = $1 returning name",
          [merchant]);
        assert.equal(r.rowCount, 1, 'a write filtered to zero rows is a silent no');
        assert.equal(r.rows[0].name, 'الاسم بعد التصحيح');
      });
    });

    it('reviews an image, and the decision is signed with their own uid', async () => {
      await as(MOD(), async () => {
        await q("select admin_review_media($1,'rejected','مش واضحة')", [media]);
        const r = await q('select status, reviewed_by from media where id = $1', [media]);
        assert.equal(r.rows[0].status, 'rejected');
        assert.equal(r.rows[0].reviewed_by, moderator);
      });
    });
  });

  describe('the till', () => {
    it('refuses a moderator recording a collection', async () => {
      await assert.rejects(
        as(MOD(), () => q('select record_commission_payment($1,$2)', [merchant, 500])),
        refusedAs('42501'));
    });

    it('refuses a moderator filling a wallet', async () => {
      await assert.rejects(
        as(MOD(), () => q('select top_up_wallet($1,$2,$3)', [merchant, 500, moderator])),
        refusedAs('42501'));
    });

    it('refuses a moderator moving the commission rate for the whole city', async () => {
      await assert.rejects(
        as(MOD(), () => q('select admin_set_commission_policy(40, 500)')),
        refusedAs('42501'));
    });

    // The other direction, and not a formality: a change that shut the till to everybody
    // would pass all three tests above.
    it('and an admin is untouched', async () => {
      await as(ADMIN(), async () => {
        await q('select top_up_wallet($1,$2,$3)', [merchant, 500, admin]);
        const r = await q('select wallet_balance from merchants where id = $1', [merchant]);
        assert.equal(r.rows[0].wallet_balance, 500);
      });
    });
  });

  // `20261101010000_a_moderator_cannot_move_money.sql`. Three doors the first pass did not
  // reach: a function missing from its list, and two column guards that step aside for
  // `is_admin()` — which answers for a moderator too.
  describe('the till, through the doors the first pass missed', () => {
    it('refuses a moderator setting the revenue model', async () => {
      // Prepaid at one piastre an order is a shop that pays nothing; a fee larger than the
      // wallet is a shop that stops taking orders.
      await assert.rejects(
        as(MOD(), () => q("select admin_set_revenue_model($1,'prepaid',1)", [merchant])),
        refusedAs('42501'));
    });

    it('and an admin still sets it, with the row and the audit entry together', async () => {
      await as(ADMIN(), async () => {
        await q("select admin_set_revenue_model($1,'prepaid',700)", [merchant]);
        const m = await q('select revenue_model, revenue_value from merchants where id = $1',
                          [merchant]);
        assert.deepEqual(m.rows[0], { revenue_model: 'prepaid', revenue_value: 700 });
        const a = await q(
          `select count(*)::int as n from audit_log
            where action = 'merchant.revenue_model_changed' and actor = $1
              and merchant_id = $2`, [admin, merchant]);
        assert.equal(a.rows[0].n, 1);
      });
    });

    // Refused, not filtered: `admin_merchants` lets a moderator reach the row, so the
    // refusal comes from the column guard and is loud. Every value below differs from the
    // fixture's, so the write would change something. The row is read back inside the same
    // transaction, past a savepoint — `as()` rolls back, so a read after it proves nothing.
    const refusedAndUnmoved = (identity, column, value) => as(identity, async () => {
      const read = async () => (await q(`select ${column} as v from merchants where id = $1`,
                                        [merchant])).rows[0].v;
      const before = await read();
      await q('savepoint attempt');
      await assert.rejects(
        q(`update merchants set ${column} = ${value} where id = $1 returning id`, [merchant]),
        refusedAs('42501'));
      await q('rollback to savepoint attempt');
      assert.deepEqual(await read(), before);
    });

    for (const [column, value] of [
      ['commission_owed', '0'],
      ['wallet_balance', '999999'],
      ['plan_expires_at', "now() + interval '10 years'"],
    ]) {
      it(`refuses a moderator writing merchants.${column} directly`, () =>
        refusedAndUnmoved(MOD(), column, value));
    }

    // H-09: a sensitive admin write goes through a function that writes its evidence.
    // A balance PATCHed through PostgREST has no receipt and no audit row behind it.
    it('refuses a platform admin writing the balance directly too', () =>
      refusedAndUnmoved(ADMIN(), 'commission_owed', '0'));

    it('and the admin paths still move it', async () => {
      await as(ADMIN(), async () => {
        await q('select top_up_wallet($1,$2,$3)', [merchant, 500, admin]);
        const r = await q('select record_commission_payment($1,$2)', [merchant, 100]);
        assert.ok(r.rows[0].record_commission_payment.payment, 'a receipt came back');
      });
    });
  });

  describe('an order', () => {
    let order;

    before(async () => {
      order = (await q(
        `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                             merchant_id, merchant_name, zone_id, type, items, pricing,
                             status, delivery_by)
         values ($1, null, 'عميل', '01000000000', $2, 'مطعم', $3, 'instant', '[]',
                 '{"subtotal":10000,"total":12000}', 'needsAttention', 'merchant')
         returning id`, [city, merchant, zone])).rows[0].id;
    });

    it('refuses a moderator rewriting the pricing', async () => {
      await assert.rejects(
        as(MOD(), () => q(
          `update orders set pricing = '{"subtotal":1,"total":1}' where id = $1`, [order])),
        refusedAs('42501'));
    });

    it('refuses a moderator moving it to delivered', async () => {
      // The transition that fires settlement.
      await assert.rejects(
        as(MOD(), () => q("update orders set status = 'delivered' where id = $1", [order])),
        refusedAs('42501'));
    });

    // The one order write AdminApp's «اليوم» sheet makes, and the reason a moderator has
    // the queue at all: an order nobody answered, cancelled so the customer is not left
    // waiting.
    it('lets a moderator cancel an unanswered order', async () => {
      await as(MOD(), async () => {
        const r = await q(
          `update orders set status = 'cancelled',
                  cancel_reason = 'المحل مردّش على الأوردر', cancelled_by = 'customer'
            where id = $1 returning status`, [order]);
        assert.equal(r.rowCount, 1, 'a write filtered to zero rows is a silent no');
        assert.equal(r.rows[0].status, 'cancelled');
      });
    });
  });

  // Astra's review of the first pass: every guard above is an UPDATE trigger, and the same
  // `for all` policies hand out INSERT.
  describe('writing money from nothing', () => {
    let plan;

    before(async () => {
      plan = 'mod-plan-' + Date.now();
      await q("insert into plans (id,name,price_monthly) values ($1,'باقة المشرف',25000)",
              [plan]);
    });

    after(async () => {
      await q('delete from plans where id = $1', [plan]).catch(() => {});
    });

    // Prepaid terms that say a fortune an order: `hold_prepaid_credit` holds that against
    // the wallet on insert, and the shop stops taking orders.
    const forgedOrder = (status) => q(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                           merchant_id, merchant_name, zone_id, type, items, pricing,
                           revenue, status, delivery_by)
       values ($1, null, 'عميل', '01000000000', $2, 'مطعم', $3, 'instant', '[]',
               '{"subtotal":1,"total":1}', '{"model":"prepaid","value":999999}', $4,
               'merchant') returning id`, [city, merchant, zone, status]);

    // By message as well as by code: a refusal from the order-number sequence is also
    // 42501, and would pass this test without the guard ever being asked.
    const byTheGuard = (error) => {
      assert.equal(error.code, '42501', error.message);
      assert.match(error.message, /place_order/);
      return true;
    };

    it('refuses a moderator inserting an order, and nothing is held', async () => {
      await as(MOD(), async () => {
        const held = async () => (await q('select wallet_held from merchants where id = $1',
                                          [merchant])).rows[0].wallet_held;
        const before = await held();
        await q('savepoint attempt');
        await assert.rejects(forgedOrder('placed'), byTheGuard);
        await q('rollback to savepoint attempt');
        assert.equal(await held(), before);
      });
    });

    // Settlement is an UPDATE trigger, so an order born finished never settles.
    it('refuses a moderator inserting one already delivered', async () => {
      await assert.rejects(as(MOD(), () => forgedOrder('delivered')), byTheGuard);
    });

    // Preserved rather than endorsed: the policy has always let a platform admin, and this
    // round narrows the moderator only. If this ever fails on the sequence, the finding it
    // sits beside was never reachable on this stack either — say so rather than fix it here.
    it('leaves a platform admin as they were', async () => {
      await as(ADMIN(), async () => {
        const r = await forgedOrder('placed');
        assert.equal(r.rowCount, 1);
      });
    });

    // The exact row AdminApp sends — `rowFor`, pinned by
    // `apps/admin_app/test/a_new_shop_payload_test.dart` — with this file's city and zone.
    const shopRow = (extra = {}) => ({
      ...JSON.parse(readFileSync(new URL('../fixtures/admin_app_creates_a_shop.json',
                                         import.meta.url), 'utf8')),
      id: randomUUID(), city_id: city, zone_id: zone, ...extra,
    });
    const insertShop = (row) => {
      const columns = Object.keys(row).join(', ');
      return q(`insert into merchants (${columns})
                select ${columns} from jsonb_populate_record(null::merchants, $1::jsonb)
                returning revenue_model, commission_custom`, [JSON.stringify(row)]);
    };

    it('lets a moderator add a shop exactly as AdminApp does', async () => {
      await as(MOD(), async () => {
        const r = await insertShop(shopRow());
        assert.equal(r.rows[0].revenue_model, 'commission', 'on the one rate');
        assert.equal(r.rows[0].commission_custom, false);
      });
    });

    for (const [column, value] of [
      ['wallet_balance', 999999],
      ['commission_owed', -999999],
      ['plan_expires_at', '2036-01-01T00:00:00Z'],
      ['revenue_model', 'prepaid'],
    ]) {
      it(`refuses a moderator adding a shop with ${column} already set`, async () => {
        await assert.rejects(
          as(MOD(), () => insertShop(shopRow({ [column]: value }))),
          refusedAs('42501'));
      });
    }

    // A term is a receipt, and the next real payment extends from the latest one — so a
    // fabricated expiry becomes the shop's plan. Refused by privilege, to the admin too.
    for (const [who, identity] of [['a moderator', MOD], ['an admin', ADMIN]]) {
      it(`refuses ${who} writing a subscription term directly`, async () => {
        await assert.rejects(
          as(identity(), () => q(
            `insert into subscriptions (merchant_id, plan_id, amount, started_at, expires_at)
             values ($1, $2, 0, now(), now() + interval '10 years')`, [merchant, plan])),
          refusedAs('42501'));
      });

      it(`refuses ${who} moving a term's expiry directly`, async () => {
        await assert.rejects(
          as(identity(), () => q(
            `update subscriptions set expires_at = now() + interval '10 years'
              where merchant_id = $1`, [merchant])),
          refusedAs('42501'));
      });
    }

    it('and an admin still records a payment', async () => {
      await as(ADMIN(), async () => {
        const r = await q('select record_subscription_payment($1,$2,25000,1) as t',
                          [merchant, plan]);
        assert.equal(r.rows[0].t.plan_id, plan);
      });
    });
  });

  // The one order write a moderator is meant to keep, which never worked: the «اليوم»
  // sheet went through the customer's path, which only matches `placed`.
  describe('cancelling an order nobody answered', () => {
    let waiting, cooking, customer;

    before(async () => {
      const make = async (status) => (await q(
        `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                             merchant_id, merchant_name, zone_id, type, items, pricing,
                             status, delivery_by)
         values ($1, null, 'عميل', '01000000000', $2, 'مطعم', $3, 'instant', '[]',
                 '{"subtotal":10000,"total":12000}', $4, 'merchant')
         returning id`, [city, merchant, zone, status])).rows[0].id;
      waiting = await make('needsAttention');
      cooking = await make('preparing');
      customer = await uid();
    });

    for (const [who, identity, actor] of [['a moderator', MOD, () => moderator],
                                          ['an admin', ADMIN, () => admin]]) {
      it(`lets ${who} cancel it, signed as staff and written down`, async () => {
        await as(identity(), async () => {
          await q("select admin_cancel_order($1, 'المحل مردّش على الأوردر')", [waiting]);
          const o = await q('select status, cancelled_by from orders where id = $1',
                            [waiting]);
          assert.deepEqual(o.rows[0], { status: 'cancelled', cancelled_by: 'admin' });
          const a = await q(
            `select count(*)::int as n from audit_log
              where action = 'order.cancelled_by_staff' and actor = $1
                and detail ->> 'orderId' = $2::text`, [actor(), waiting]);
          assert.equal(a.rows[0].n, 1);
        });
      });
    }

    it('refuses once the kitchen has started, as a conflict', async () => {
      await assert.rejects(
        as(MOD(), () => q("select admin_cancel_order($1, 'متأخر')", [cooking])),
        refusedAs('23505'));
    });

    it('refuses a customer', async () => {
      await assert.rejects(
        as({ uid: customer, claims: {} },
           () => q("select admin_cancel_order($1, 'مش عايزه')", [waiting])),
        refusedAs('42501'));
    });
  });

  describe('deletion', () => {
    // Twenty-five tables carry a `for all` policy gated on `is_admin()`, so widening that
    // function opened the delete on every one of them at once.
    it('refuses a moderator deleting a shop', async () => {
      await assert.rejects(
        as(MOD(), () => q('delete from merchants where id = $1', [merchant])),
        refusedAs('42501'));
    });

    it('refuses a moderator deleting a place', async () => {
      await assert.rejects(
        as(MOD(), () => q('delete from zones where id = $1', [zone])),
        refusedAs('42501'));
    });

    it('refuses a moderator deleting an account', async () => {
      await assert.rejects(
        as(MOD(), () => q('delete from staff where uid = $1', [admin])),
        refusedAs('42501'));
    });

    it('and an admin still deletes', async () => {
      await as(ADMIN(), async () => {
        const r = await q('delete from media where id = $1', [media]);
        assert.equal(r.rowCount, 1);
      });
    });
  });

  describe('who mints an account', () => {
    // The trigger above already refused these — from inside the write, after the function
    // had agreed to do it and written its audit row. A door that is going to be shut is
    // shut at the door (`20261024010000_and_who_mints_an_account.sql`).
    let application;

    before(async () => {
      application = (await q(
        `insert into staff_applications (kind, name, phone, note, status)
         values ('courier', 'مندوب', $1, 'أهلاً', 'pending') returning id`,
        [`0100${Date.now() % 10000000}`])).rows[0].id;
    });

    after(async () => {
      await q('delete from staff_applications where id = $1', [application]).catch(() => {});
    });

    it('refuses a moderator approving an application', async () => {
      await assert.rejects(
        as(MOD(), () => q('select approve_staff_application($1)', [application])),
        refusedAs('42501'));
    });

    it('refuses a moderator writing the control plane through the function', async () => {
      await assert.rejects(
        as(MOD(), () => q(`select admin_set_config('{"support_whatsapp":"0100"}'::jsonb)`)),
        refusedAs('42501'));
    });

    it('refuses a moderator attaching a courier to a shop', async () => {
      // `courier_merchants` is how a rider reaches a shop's customers' addresses and
      // telephone numbers. Granting that is identity, not moderation.
      await assert.rejects(
        as(MOD(), () => q('select attach_courier_by_phone($1, $2)',
                          [merchant, '01000000000'])),
        refusedAs('42501'));
    });

    // The half that stays theirs, and the reason the whole module is still shown to them:
    // rejecting mints nothing, and a queue somebody may read and not work is not a job.
    it('but lets a moderator reject one', async () => {
      await as(MOD(), async () => {
        await q(`select review_staff_application($1, 'rejected', 'مش دلوقتي')`,
                [application]);
        const r = await q('select status from staff_applications where id = $1',
                          [application]);
        assert.equal(r.rows[0].status, 'rejected');
      });
    });
  });

  describe('who anybody is', () => {
    // The one permission that hands out every other one. `staff` carries a `for all`
    // policy, so without this a moderator with an admin's reach writes `role = 'admin'`
    // onto their own row and the rest of this file is decoration.
    it('refuses a moderator promoting themselves', async () => {
      await assert.rejects(
        as(MOD(), () => q("update staff set role='admin' where uid=$1", [moderator])),
        refusedAs('42501'));
    });

    it('refuses a moderator promoting anybody else either', async () => {
      const other = await uid();
      await q("insert into staff (uid,scope,role) values ($1,'platform','moderator')", [other]);
      try {
        await assert.rejects(
          as(MOD(), () => q("update staff set role='admin' where uid=$1", [other])),
          refusedAs('42501'));
      } finally {
        await q('delete from staff where uid = $1', [other]);
      }
    });

    // `default_commission_percent` is money by another name, and `min_supported_version`
    // walls every customer out of the product with no back door.
    it('refuses a moderator writing the control plane', async () => {
      await assert.rejects(
        as(MOD(), () => q(
          "update config set value='40'::jsonb where key='default_commission_percent'")),
        refusedAs('42501'));
    });

    it('and an admin writes it', async () => {
      await as(ADMIN(), async () => {
        const r = await q(
          "update config set value='7'::jsonb where key='default_commission_percent' " +
          'returning key');
        assert.equal(r.rowCount, 1);
      });
    });
  });
});
