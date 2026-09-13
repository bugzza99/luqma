import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { freshDatabase } from './harness.mjs';

/**
 * What the platform takes from one order.
 *
 * `order_revenue_take` is the mirror of `Revenue.takeFrom` in
 * `packages/luqma_core/lib/src/models/revenue.dart`, and the two exist separately on
 * purpose: the phone *shows* the figure and the server *decides* it. Every number below
 * is asserted against the Dart side too, so a disagreement fails a test rather than
 * turning up in somebody's till.
 *
 * Here rather than in the stack suite because this is arithmetic, not a boundary: no
 * policy, no token, no trigger. It is the part that can be argued with directly.
 */
describe('what the platform takes from one order', () => {
  let db;

  before(async () => { db = await freshDatabase(); });
  after(async () => { await db.close(); });

  const take = async (revenue, basis) => Number(
    (await db.query('select public.order_revenue_take($1::jsonb, $2) as t',
                    [JSON.stringify(revenue), basis])).rows[0].t,
  );

  // The shared table. Every case here is asserted by `revenue_test.dart` too, against
  // the Dart engine — which is what makes "the phone shows it and the server decides it"
  // a guarantee rather than a hope. Before this, each side was tested against its own
  // figures, which proves each self-consistent and nothing about them agreeing.
  describe('the same numbers the phone shows', () => {
    const { cases } = JSON.parse(
      readFileSync(new URL('../../../data/revenue-cases.json', import.meta.url), 'utf8'));

    for (const c of cases) {
      it(c.why, async () => {
        assert.equal(await take({ model: c.model, value: c.value }, c.basis), c.take);
      });
    }
  });

  describe('subscription', () => {
    // The whole point of subscription-first: the money lands in the merchant's hand and
    // nothing about a single order is negotiable afterwards.
    it('takes nothing, whatever the order was worth', async () => {
      assert.equal(await take({ model: 'subscription', value: 0 }, 500000), 0);
      assert.equal(await take({ model: 'subscription', value: 9999 }, 500000), 0);
    });
  });

  describe('commission', () => {
    it('is basis points of the food', async () => {
      // 10% of 200 EGP.
      assert.equal(await take({ model: 'commission', value: 1000 }, 20000), 2000);
    });

    // Rounded down, always. Taking one piastre more than the stated rate is the sort of
    // thing that gets argued about in a shop, and it can only ever be argued downwards.
    it('rounds down rather than to nearest', async () => {
      // 12.34% of 99.99 EGP = 1233.8766 piastres.
      assert.equal(await take({ model: 'commission', value: 1234 }, 9999), 1233);
    });

    it('a rate somebody mistyped cannot exceed the order', async () => {
      // 200% is a typo for 2.00%, and it must not turn into a merchant owing double.
      assert.equal(await take({ model: 'commission', value: 20000 }, 15000), 15000);
    });

    it('a negative rate takes nothing rather than paying the merchant', async () => {
      assert.equal(await take({ model: 'commission', value: -500 }, 15000), 0);
    });
  });

  describe('prepaid', () => {
    it('is the flat fee, whatever the order was worth', async () => {
      assert.equal(await take({ model: 'prepaid', value: 500 }, 20000), 500);
      assert.equal(await take({ model: 'prepaid', value: 500 }, 400000), 500);
    });

    // The merchant made a sale. A fee that puts them in the red on it is a fee that
    // stops them taking small orders at all.
    it('never exceeds an order smaller than the fee', async () => {
      assert.equal(await take({ model: 'prepaid', value: 500 }, 300), 300);
    });
  });

  describe('the edges', () => {
    it('an order worth nothing owes nothing', async () => {
      assert.equal(await take({ model: 'commission', value: 1000 }, 0), 0);
      assert.equal(await take({ model: 'prepaid', value: 500 }, 0), 0);
    });

    it('and a negative basis is not a refund', async () => {
      assert.equal(await take({ model: 'prepaid', value: 500 }, -1000), 0);
    });

    // An order written before a field existed, or a snapshot an admin has been editing.
    // A settlement is not the place to discover a missing key by dividing by null.
    it('a snapshot missing its value takes nothing', async () => {
      assert.equal(await take({ model: 'commission' }, 20000), 0);
      assert.equal(await take({ model: 'prepaid' }, 20000), 0);
    });

    it('a snapshot naming a model that does not exist takes nothing', async () => {
      assert.equal(await take({ model: 'barter', value: 9999 }, 20000), 0);
      assert.equal(await take({}, 20000), 0);
    });
  });
});

describe('the whole settlement account', () => {
  let db, merchant;
  before(async () => {
    db = await freshDatabase();
    await db.exec("insert into cities (id,name) values ('summary','Summary')");
    const zone = (await db.query("insert into zones (city_id,name,default_delivery_fee) values ('summary','Zone',0) returning id")).rows[0].id;
    merchant = (await db.query("insert into merchants (city_id,type,name,zone_id,phone,status) values ('summary','restaurant','Shop',$1,'0100','approved') returning id", [zone])).rows[0].id;
    // 101 standing charges plus one reversal. The oldest charge falls off the page.
    await db.query(`with inserted as (
      insert into orders (city_id,customer_uid,customer_name,customer_phone,
        merchant_id,merchant_name,zone_id,type,items,pricing)
      select 'summary',auth.uid(),'Customer','0100',$1,'Shop',$2,'instant','[]','{}'
      from generate_series(1,102) returning id
    ) insert into order_settlements
      (order_id,merchant_id,model,basis,amount,platform_owes,settled_at,reversed_at)
      select id,$1,'commission',10000,200,300,
        '2026-01-01'::timestamptz + row_number() over () * interval '1 day',
        case when row_number() over () = 102 then now() end from inserted`, [merchant,zone]);
    await db.query(`insert into commission_payments (merchant_id,amount,recorded_by)
      select $1,100,auth.uid() from generate_series(1,101)`, [merchant]);
  });
  after(async () => { await db.close(); });
  const summary = async () => (await db.query(
    'select public.settlement_summary($1) as s', [merchant])).rows[0].s;

  it('totals all 101 standing charges, not the latest hundred rows', async () => {
    const page = (await db.query(`select * from order_settlements
      where merchant_id=$1 order by settled_at desc limit 100`, [merchant])).rows;
    assert.equal(page.length,100);
    assert.equal(page.filter(r => r.reversed_at === null).length,99);
    assert.deepEqual(await summary(), {orders:101,taken:20200,platform_owes:30300,paid:10100});
  });
  it('an active owner reads their account but no other merchant account', async () => {
    await db.exec('begin');
    try {
      const otherMerchant = (await db.query(`insert into merchants
        (city_id,type,name,zone_id,phone,status)
        select city_id,type,'Other shop',zone_id,phone,status from merchants
        where id=$1 returning id`, [merchant])).rows[0].id;
      const owners = (await db.query(`insert into auth.users (id)
        values (gen_random_uuid()),(gen_random_uuid()) returning id`)).rows;
      await db.query(`insert into staff (uid,scope,role,merchant_id)
        values ($1,'merchant','owner',$2),($3,'merchant','owner',$4)`,
        [owners[0].id,merchant,owners[1].id,otherMerchant]);
      // Run as the harness superuser so RLS cannot mask a missing identity guard.
      // Only the auth stubs change; the real active-staff and ownership helpers run.
      await db.query(`create or replace function auth.uid() returns uuid
        language sql stable as $uid$ select '${owners[0].id}'::uuid $uid$`);
      await db.query(`create or replace function auth.jwt() returns jsonb
        language sql stable as $jwt$ select '${JSON.stringify({app_metadata:{role:'owner',merchant_id:merchant}})}'::jsonb $jwt$`);
      assert.deepEqual(await summary(), {orders:101,taken:20200,platform_owes:30300,paid:10100});
      await db.query(`create or replace function auth.uid() returns uuid
        language sql stable as $uid$ select '${owners[1].id}'::uuid $uid$`);
      await db.query(`create or replace function auth.jwt() returns jsonb
        language sql stable as $jwt$ select '${JSON.stringify({app_metadata:{role:'owner',merchant_id:otherMerchant}})}'::jsonb $jwt$`);
      assert.equal(await summary(), null);
    } finally { await db.exec('rollback'); }
  });

  it('the service role can read totals and anonymous callers cannot execute', async () => {
    const privileges = (await db.query(`select
      has_function_privilege('anon', 'public.settlement_summary(uuid)', 'execute') as anon,
      has_function_privilege('authenticated', 'public.settlement_summary(uuid)', 'execute') as authenticated,
      exists (select 1 from pg_proc, lateral aclexplode(proacl)
        where oid = 'public.settlement_summary(uuid)'::regprocedure
        and grantee = 0 and privilege_type = 'EXECUTE') as public`)).rows[0];
    assert.deepEqual(privileges, {anon:false,authenticated:true,public:false});
    await db.exec('begin');
    try {
      // Supabase's real service_role has BYPASSRLS; the local harness only creates it.
      await db.exec('grant usage on schema auth to service_role; alter role service_role bypassrls; set local role service_role');
      assert.deepEqual(await summary(), {orders:101,taken:20200,platform_owes:30300,paid:10100});
    } finally { await db.exec('rollback'); }
  });
});
