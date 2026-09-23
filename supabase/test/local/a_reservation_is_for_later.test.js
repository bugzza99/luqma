import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * B9. A reservation is for later, so the kitchen's "not right now" does not refuse it.
 *
 * `place_order_priced` refused every order — pre-orders included — while the shop was
 * paused or outside its posted hours. A home kitchen that tapped the busy toggle at lunch,
 * or published a meal outside the hours on its shop, had every reservation refused, and
 * the customer was told the meal had sold out beside a counter still showing portions.
 * The owner decided (2026-09-23) that a pre-order stays open whatever the kitchen's
 * "now" is: the meal's own window and status are what decide it. An instant order is
 * unchanged — it is food cooked now, and a kitchen that is not cooking now refuses it.
 */
describe('a reservation is for later', () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';
  let db, kitchen, item, addressId, meal;

  const one = async (sql, params) => (await db.query(sql, params)).rows[0];
  const serverMode = async (fn) => {
    await db.query(`select set_config('app.server_mode','on',false)`);
    try { return await fn(); } finally {
      await db.query(`select set_config('app.server_mode','',false)`);
    }
  };

  before(async () => {
    db = await freshDatabase();
    await db.query('insert into auth.users (id) values ($1)', [CUSTOMER]);
    await db.query(`create or replace function auth.uid() returns uuid
      language sql stable as $fn$ select '${CUSTOMER}'::uuid $fn$`);
    await db.query(`update users set name='عميل', phone='01000000000' where id=$1`, [CUSTOMER]);
    await db.query(`insert into cities (id,name) values ('p','مدينة')`);
    const zone = (await one(
      `insert into zones (city_id,name,default_delivery_fee) values ('p','منطقة',1000) returning id`
    )).id;
    kitchen = (await one(
      `insert into merchants (city_id,type,name,zone_id,phone,status,delivers_self,min_order,opening_hours)
       values ('p','homeKitchen','مطبخ',$1,'0100','approved',true,0,
         (select jsonb_agg(jsonb_build_object('weekday',d,'openMinute',0,'closeMinute',1439))
            from generate_series(1,7) d)) returning id`, [zone])).id;
    await db.query(`insert into merchant_served_zones (merchant_id,zone_id) values ($1,$2)`,
      [kitchen, zone]);
    const cat = (await one(
      `insert into menu_categories (merchant_id,name) values ($1,'أطباق') returning id`,
      [kitchen])).id;
    item = (await one(
      `insert into menu_items (merchant_id,category_id,name,price)
       values ($1,$2,'كشري',5000) returning id`, [kitchen, cat])).id;
    addressId = (await one(
      `insert into addresses (user_id,zone_id,label) values ($1,$2,'البيت') returning id`,
      [CUSTOMER, zone])).id;
    meal = (await one(`insert into daily_meals
      (merchant_id, city_id, name, price, date, total_qty, remaining_qty,
       pickup_window_start, pickup_window_end, status)
      values ($1, 'p', 'محشي', 9000, (now() at time zone 'Africa/Cairo')::date,
              50, 50, 0, 1440, 'published') returning id`, [kitchen])).id;
  });

  after(async () => { await db?.close(); });

  beforeEach(() => serverMode(() => db.query(
    `update merchants set paused_until = null,
       opening_hours = (select jsonb_agg(jsonb_build_object('weekday',d,'openMinute',0,'closeMinute',1439))
                          from generate_series(1,7) d)
     where id = $1`, [kitchen])));

  const reserve = () => db.query('select place_order($1::jsonb) as o', [JSON.stringify({
    merchantId: kitchen, addressId, type: 'preorder', dailyMealId: meal,
    items: [{ itemId: meal, quantity: 1 }],
  })]);

  const orderNow = () => db.query('select place_order($1::jsonb) as o', [JSON.stringify({
    merchantId: kitchen, addressId, type: 'instant',
    items: [{ itemId: item, name: 'كشري', unitPrice: 5000, quantity: 1 }],
  })]);

  const pause = () => serverMode(() => db.query(
    `update merchants set paused_until = now() + interval '1 hour' where id = $1`, [kitchen]));
  const shut = () => serverMode(() => db.query(
    `update merchants set opening_hours = '[]'::jsonb where id = $1`, [kitchen]));

  it('a paused kitchen still takes a reservation', async () => {
    await pause();
    await reserve();
  });

  it('a kitchen outside its posted hours still takes a reservation', async () => {
    await shut();
    await reserve();
  });

  it('a paused kitchen still refuses food to be cooked now', async () => {
    await pause();
    await assert.rejects(orderNow(), /merchant not accepting orders/);
  });

  it('a shut kitchen still refuses food to be cooked now', async () => {
    await shut();
    await assert.rejects(orderNow(), /merchant not accepting orders/);
  });

  it('a kitchen that is not approved refuses a reservation too', async () => {
    await serverMode(() => db.query(
      `update merchants set status = 'suspended' where id = $1`, [kitchen]));
    try {
      await assert.rejects(reserve(), /merchant not accepting orders/);
    } finally {
      await serverMode(() => db.query(
        `update merchants set status = 'approved' where id = $1`, [kitchen]));
    }
  });
});
