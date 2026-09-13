import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * What a shop sold this week.
 *
 * Sales are the **food** — `pricing.subtotal`, the figure commission is charged on —
 * because when the platform delivers, the delivery fee was never the merchant's to see,
 * and a headline that includes it on some orders and not others is a number the owner
 * cannot check against their own till.
 *
 * A cancelled order is not a sale and is counted anyway, on its own, split by who
 * cancelled it: a customer changing their mind and a courier coming back from the door
 * are different problems.
 */
describe('what a shop sold', () => {
  const OWNER = '00000000-0000-0000-0000-0000000000aa';
  let db, shop, other, zone;

  const as = (uid, claims) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const order = async ({ merchant, subtotal, status = 'delivered',
                         cancelledBy = null, daysAgo = 0, items = [] }) => {
    const id = (await db.query(
      `insert into orders (city_id,customer_uid,customer_name,customer_phone,
                           merchant_id,merchant_name,zone_id,type,items,pricing,status)
       values ('edku',null,'عميل','01000000000',$1,'مطعم',$2,'instant',$3::jsonb,
               jsonb_build_object('subtotal',$4::int,'total',$4::int + 1000),'placed')
       returning id`,
      [merchant, zone, JSON.stringify(items), subtotal])).rows[0].id;

    await db.query(`do $$ begin
      perform set_config('app.server_mode','on',true);
      update public.orders
         set status = '${status}',
             cancelled_by = ${cancelledBy ? `'${cancelledBy}'` : 'null'},
             placed_at = (now() at time zone 'Africa/Cairo')::date
                         - interval '${daysAgo} days' + interval '13 hours'
       where id = '${id}';
    end $$;`);
    return id;
  };

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${OWNER}');
      grant usage on schema auth to authenticated;
      insert into cities (id,name) values ('edku','إدكو');`);
    zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee)
       values ('edku','الزغبي',1000) returning id`)).rows[0].id;
    const make = async (n) => (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ('edku','restaurant',$1,$2,'0100','approved') returning id`,
      [n, zone])).rows[0].id;
    shop = await make('مطعم');
    other = await make('مطعم تاني');
    await db.query(
      `insert into staff (uid,scope,role,merchant_id,is_active)
       values ($1,'merchant','owner',$2,true)`, [OWNER, shop]);

    const fish = [{ itemId: 'i1', name: 'سمك', quantity: 2 }];
    const rice = [{ itemId: 'i2', name: 'رز', quantity: 1 }];

    await order({ merchant: shop, subtotal: 10000, items: fish });
    await order({ merchant: shop, subtotal: 20000, daysAgo: 1, items: fish });
    await order({ merchant: shop, subtotal: 6000, daysAgo: 2, items: rice });
    await order({ merchant: shop, subtotal: 9000, status: 'cancelled',
                  cancelledBy: 'customer' });
    await order({ merchant: shop, subtotal: 9000, status: 'cancelled',
                  cancelledBy: 'courier' });
    // Outside the window, and somebody else's.
    await order({ merchant: shop, subtotal: 99000, daysAgo: 30 });
    await order({ merchant: other, subtotal: 77000 });
  });

  after(async () => { await db?.close(); });

  const sales = async (days = 7) => {
    await as(OWNER, { role: 'owner', scope: 'merchant', merchant_id: shop });
    await db.exec('set role authenticated');
    try {
      return (await db.query(
        'select public.merchant_sales($1,$2) as s', [shop, days])).rows[0].s;
    } finally {
      await db.exec('reset role');
    }
  };

  it('counts the food it delivered, and only that', async () => {
    const s = await sales();
    assert.equal(s.orders, 3);
    assert.equal(Number(s.sales), 36000, '10000 + 20000 + 6000, no delivery fee in it');
  });

  it('never another shop’s', async () => {
    const s = await sales();
    assert.equal(Number(s.sales), 36000);
  });

  it('and nothing older than the window asked for', async () => {
    const s = await sales();
    assert.equal(s.orders, 3, 'the order thirty days back is a different month');
  });

  it('counts what was cancelled, apart, and by whom', async () => {
    const s = await sales();
    assert.equal(s.cancelledByCustomer, 1);
    assert.equal(s.returned, 1, 'a courier coming back from the door is its own problem');
    assert.equal(Number(s.sales), 36000, 'and neither is a sale');
  });

  it('averages in whole piastres', async () => {
    const s = await sales();
    assert.equal(Number(s.average), 12000);
  });

  it('gives every day in the window, including the empty ones', async () => {
    const s = await sales();
    assert.equal(s.byDay.length, 7, 'a bar chart with holes in it is a broken chart');
    assert.equal(s.byDay.filter((d) => d.orders > 0).length, 3);
  });

  it('and the dishes that sold, most first', async () => {
    const s = await sales();
    assert.equal(s.topItems[0].name, 'سمك');
    assert.equal(Number(s.topItems[0].quantity), 4, 'two orders of two');
    assert.equal(s.topItems.length, 2);
  });

  it('says nothing rather than failing for a shop with no week', async () => {
    await as(OWNER, { role: 'owner', scope: 'merchant', merchant_id: shop });
    await db.exec('set role authenticated');
    const s = (await db.query(
      'select public.merchant_sales($1,7) as s', [other])).rows[0].s;
    await db.exec('reset role');

    // `read_orders` shows this owner nothing of the other shop, so the count is zero
    // rather than an error — RLS filters, it does not refuse.
    assert.equal(s.orders, 0);
    assert.equal(Number(s.sales), 0);
    assert.deepEqual(s.topItems, []);
  });
});
