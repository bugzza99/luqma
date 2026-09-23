import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * Food to be delivered names where it goes.
 *
 * `place_order_priced` took an instant order with no `addressId` down the pre-order's
 * collection branch: the shop's own zone, a delivery fee of zero and a null address. A
 * courier would have been sent out with nowhere to go, and the customer charged nothing
 * for the trip. The app never sends one; a hand-written request could. A reservation
 * without an address is still collected by the person who made it.
 */
describe('an instant order names its address', () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';
  let db, kitchen, item, addressId;

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
  });

  after(async () => { await db?.close(); });

  beforeEach(() => serverMode(() => db.query(
    `update merchants set paused_until = null,
       opening_hours = (select jsonb_agg(jsonb_build_object('weekday',d,'openMinute',0,'closeMinute',1439))
                          from generate_series(1,7) d)
     where id = $1`, [kitchen])));

  const place = (draft) => db.query('select place_order($1::jsonb) as o', [JSON.stringify({
    merchantId: kitchen,
    items: [{ itemId: item, name: 'كشري', unitPrice: 5000, quantity: 1 }],
    ...draft,
  })]);

  it('an instant order with no address is refused as a bad request', async () => {
    await assert.rejects(place({ type: 'instant' }),
      (e) => e.code === '22023' && /names its address/.test(e.message));
  });

  it('so is one that names no type', async () => {
    await assert.rejects(place({}), (e) => e.code === '22023');
  });

  it('with its address it goes through', async () => {
    await place({ type: 'instant', addressId });
  });
});
