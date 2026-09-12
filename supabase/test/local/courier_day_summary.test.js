import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * What a rider did today, per shop.
 *
 * No wage is modelled and none is being built — the courier is paid outside the app. What
 * this settles is the argument at the end of a shift: how many deliveries, how much cash
 * is in their hand, and which shop each belongs to.
 *
 * A delivery that came back is a trip made and no money collected. It is counted on its
 * own and adds nothing to the cash; whether it is paid for is between the rider and the
 * shop.
 */
describe('what a rider did today', () => {
  const RIDER = '00000000-0000-0000-0000-0000000000e1';
  const OTHER = '00000000-0000-0000-0000-0000000000e2';
  let db, fish, koshari, zone;

  const as = (uid) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({
        app_metadata: { role: 'courier', scope: 'merchant' },
      })}'::jsonb $fn$;`);

  // Server mode, because `courier_uid`, `status` and `cancelled_by` are all guarded
  // columns and this is building history rather than acting as a courier.
  const order = async ({ merchant, status, total, courier, cancelledBy = null,
                         platform = false, at = null }) => {
    const id = (await db.query(
      `insert into orders (city_id,customer_uid,customer_name,customer_phone,
                           merchant_id,merchant_name,zone_id,type,items,pricing,status,
                           delivery_by)
       values ('edku',null,'عميل','01000000000',$1,
               (select name from merchants where id=$1),$2,'instant','[]',
               jsonb_build_object('total',$3::int),'placed',$4)
       returning id`,
      [merchant, zone, total, platform ? 'platform' : 'merchant'])).rows[0].id;

    await db.query(`do $$ begin
      perform set_config('app.server_mode','on',true);
      update public.orders
         set status = '${status}', courier_uid = ${courier ? `'${courier}'` : 'null'},
             cancelled_by = ${cancelledBy ? `'${cancelledBy}'` : 'null'},
             delivered_at = ${at ? `'${at}'::timestamptz`
                                 : (status === 'delivered' ? 'now()' : 'null')}
       where id = '${id}';
    end $$;`);
    return id;
  };

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${RIDER}'), ('${OTHER}');
      grant usage on schema auth to authenticated;
      insert into cities (id,name) values ('edku','إدكو');`);
    zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee)
       values ('edku','الزغبي',1000) returning id`)).rows[0].id;
    const shop = async (n) => (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ('edku','restaurant',$1,$2,'0100','approved') returning id`,
      [n, zone])).rows[0].id;
    fish = await shop('السمك');
    koshari = await shop('الكشري');

    for (const uid of [RIDER, OTHER]) {
      await db.query(
        `insert into staff (uid,scope,role,merchant_id,is_active)
         values ($1,'merchant','courier',$2,true)`, [uid, fish]);
    }

    await order({ merchant: fish, status: 'delivered', total: 12000, courier: RIDER });
    await order({ merchant: fish, status: 'delivered', total: 8000, courier: RIDER });
    await order({ merchant: koshari, status: 'delivered', total: 5000, courier: RIDER });
    // A trip made and nothing collected.
    await order({ merchant: fish, status: 'cancelled', total: 9000, courier: RIDER,
                  cancelledBy: 'courier' });
    // The customer killed this one before it ever left the kitchen. Not the rider's trip.
    await order({ merchant: fish, status: 'cancelled', total: 7000, courier: RIDER,
                  cancelledBy: 'customer' });
    // Somebody else's work.
    await order({ merchant: fish, status: 'delivered', total: 30000, courier: OTHER });
    // A shift long past. `delivered_at` is the moment the work happened; `updated_at`
    // is not, and a trigger rewrites it on every touch.
    await order({ merchant: fish, status: 'delivered', total: 40000, courier: RIDER,
                  at: '2020-01-01T10:00:00Z' });
  });

  after(async () => { await db?.close(); });

  const summary = async () => {
    await as(RIDER);
    await db.exec('set role authenticated');
    try {
      return (await db.query('select public.courier_day_summary() as s')).rows[0].s;
    } finally {
      await db.exec('reset role');
    }
  };

  it('counts the deliveries and the cash in hand', async () => {
    const s = await summary();
    assert.equal(s.delivered, 3);
    assert.equal(Number(s.cash), 25000, '12000 + 8000 + 5000, and nothing else');
  });

  it('counts a delivery that came back, and adds no money for it', async () => {
    const s = await summary();
    assert.equal(s.returned, 1);
    assert.equal(Number(s.cash), 25000);
  });

  // An order the customer cancelled is not a trip the rider made.
  it('does not count an order the customer cancelled as a return', async () => {
    const s = await summary();
    assert.equal(s.returned, 1);
  });

  it('never counts another rider work', async () => {
    const s = await summary();
    assert.equal(Number(s.cash), 25000, "30000 belongs to somebody else's shift");
  });

  it('and only today', async () => {
    const s = await summary();
    assert.equal(s.delivered, 3, 'yesterday is a different shift');
  });

  it('splits it by shop, biggest first', async () => {
    const s = await summary();
    assert.equal(s.shops.length, 2);
    assert.equal(s.shops[0].merchantName, 'السمك');
    assert.equal(Number(s.shops[0].cash), 20000);
    assert.equal(s.shops[0].delivered, 2);
    assert.equal(s.shops[0].returned, 1);
    assert.equal(Number(s.shops[1].cash), 5000);
  });

  it('and a rider who did nothing today is told nothing, not an error', async () => {
    await as(OTHER);
    await db.exec('set role authenticated');
    const s = (await db.query(
      "select public.courier_day_summary('2020-06-01'::date) as s")).rows[0].s;
    await db.exec('reset role');

    assert.equal(s.delivered, 0);
    assert.equal(Number(s.cash), 0);
    assert.deepEqual(s.shops, []);
  });
});
