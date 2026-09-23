import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A4. An order that is cancelled gives back what placing it took.
 *
 * `place_order` takes a home kitchen's portions (`daily_meals.remaining_qty`) and a
 * coupon's use (`coupons.used_count` plus a `coupon_redemptions` row) inside the
 * placement transaction. Nothing ever gave either back: one account could reserve the
 * last ten portions and cancel a second later, and the meal read «خلصت» for the rest of
 * the day with no way for the cook to correct it; a customer whose order the shop
 * refused found their one-use code already spent.
 */
describe('a cancelled order gives back what it took', () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';
  let db, merchant, item, addressId, meal, couponId;

  const one = async (sql, params) => (await db.query(sql, params)).rows[0];

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
    merchant = (await one(
      `insert into merchants (city_id,type,name,zone_id,phone,status,delivers_self,min_order,opening_hours)
       values ('p','homeKitchen','مطبخ',$1,'0100','approved',true,0,
         (select jsonb_agg(jsonb_build_object('weekday',d,'openMinute',0,'closeMinute',1439))
            from generate_series(1,7) d)) returning id`, [zone])).id;
    await db.query(`insert into merchant_served_zones (merchant_id,zone_id) values ($1,$2)`,
      [merchant, zone]);
    const cat = (await one(
      `insert into menu_categories (merchant_id,name) values ($1,'أطباق') returning id`,
      [merchant])).id;
    item = (await one(
      `insert into menu_items (merchant_id,category_id,name,price)
       values ($1,$2,'كشري',5000) returning id`, [merchant, cat])).id;
    addressId = (await one(
      `insert into addresses (user_id,zone_id,label) values ($1,$2,'البيت') returning id`,
      [CUSTOMER, zone])).id;
  });

  after(async () => { await db?.close(); });

  beforeEach(async () => {
    await db.query('delete from coupon_redemptions');
    await db.query(`select set_config('app.server_mode','on',false)`);
    await db.query('delete from orders');
    await db.query(`select set_config('app.server_mode','',false)`);
    await db.query('delete from daily_meals');
    await db.query('delete from coupons');
    meal = (await one(`insert into daily_meals
      (merchant_id, city_id, name, price, date, total_qty, remaining_qty,
       pickup_window_start, pickup_window_end, status)
      values ($1, 'p', 'محشي', 9000, (now() at time zone 'Africa/Cairo')::date,
              10, 10, 0, 1440, 'published') returning id`, [merchant])).id;
    couponId = (await one(`insert into coupons
      (code, city_id, type, value, merchant_id, per_user_limit, total_limit)
      values ('ONCE', 'p', 'fixedAmount', 1000, $1, 1, 5) returning id`, [merchant])).id;
  });

  const reserve = async (quantity) => (await one('select place_order($1::jsonb) as o', [
    JSON.stringify({
      merchantId: merchant, addressId, type: 'preorder', dailyMealId: meal,
      items: [{ itemId: meal, quantity }],
    })])).o;

  const orderWithCode = async () => (await one('select place_order($1::jsonb) as o', [
    JSON.stringify({
      merchantId: merchant, addressId, type: 'instant', couponCode: 'ONCE',
      items: [{ itemId: item, name: 'كشري', unitPrice: 5000, quantity: 2 }],
    })])).o;

  /** Cancelled the way the server does it; the rule is about the status, not who. */
  const cancel = async (id) => {
    await db.query(`select set_config('app.server_mode','on',false)`);
    try {
      await db.query(
        `update orders set status = 'cancelled', cancel_reason = 'اختبار' where id = $1`, [id]);
    } finally {
      await db.query(`select set_config('app.server_mode','',false)`);
    }
  };

  const remaining = async () =>
    (await one('select remaining_qty from daily_meals where id = $1', [meal])).remaining_qty;

  it('the portions a cancelled reservation took go back to the meal', async () => {
    const order = await reserve(10);
    assert.equal(await remaining(), 0, 'the reservation took all ten');

    await cancel(order.id);

    assert.equal(await remaining(), 10);
  });

  it('only once, however many times the row is written afterwards', async () => {
    const order = await reserve(4);
    await cancel(order.id);
    // A second write to a cancelled order — a note, a stamp — is not a second refund.
    await db.query(`select set_config('app.server_mode','on',false)`);
    await db.query(`update orders set cancel_reason = 'تاني' where id = $1`, [order.id]);
    await db.query(`select set_config('app.server_mode','',false)`);

    assert.equal(await remaining(), 10);
  });

  it('never above what the cook published', async () => {
    const order = await reserve(3);
    // The count moved in the meantime (only the server moves it, hence server mode).
    await db.query(`select set_config('app.server_mode','on',false)`);
    await db.query('update daily_meals set remaining_qty = 9 where id = $1', [meal]);
    await db.query(`select set_config('app.server_mode','',false)`);

    await cancel(order.id);

    assert.equal(await remaining(), 10, 'capped at total_qty');
  });

  it("a cancelled order's coupon can be used again", async () => {
    const order = await orderWithCode();
    assert.equal((await one('select used_count from coupons where id = $1', [couponId])).used_count, 1);

    await cancel(order.id);

    assert.equal((await one('select used_count from coupons where id = $1', [couponId])).used_count, 0);
    assert.equal(
      (await one('select count(*)::int n from coupon_redemptions where order_id = $1', [order.id])).n,
      0);
    // And the customer really can place with it again — per_user_limit is 1.
    const again = await orderWithCode();
    assert.equal(again.couponCode ?? again.coupon_code, 'ONCE');
  });

  it('a delivered order keeps what it took', async () => {
    const order = await reserve(2);
    await db.query(`select set_config('app.server_mode','on',false)`);
    await db.query(`update orders set status = 'delivered' where id = $1`, [order.id]);
    await db.query(`select set_config('app.server_mode','',false)`);

    assert.equal(await remaining(), 8);
  });
});
