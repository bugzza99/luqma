import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A draft that names no type is an instant order, and is judged as one.
 *
 * `place_order_priced` stored a missing `type` as `instant` but asked every question
 * about it as `p_draft ->> 'type' = 'preorder'` — which is NULL, not false, when the key
 * is absent. `not NULL` is NULL, so the pause check, the hours check and the minimum order
 * were each skipped, and `<> 'preorder'` skipped the accept deadline: an order a paused
 * shop could not refuse and that no timer would ever escalate. The app always sends a
 * type; a hand-written request did not have to.
 */
describe('a draft without a type is an instant order', () => {
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

  const untyped = () => db.query('select place_order($1::jsonb) as o', [JSON.stringify({
    merchantId: kitchen, addressId,
    items: [{ itemId: item, name: 'كشري', unitPrice: 5000, quantity: 1 }],
  })]);

  it('a paused shop refuses it', async () => {
    await serverMode(() => db.query(
      `update merchants set paused_until = now() + interval '1 hour' where id = $1`, [kitchen]));
    await assert.rejects(untyped(), /merchant not accepting orders/);
  });

  it('a shop outside its hours refuses it', async () => {
    await serverMode(() => db.query(
      `update merchants set opening_hours = '[]'::jsonb where id = $1`, [kitchen]));
    await assert.rejects(untyped(), /merchant not accepting orders/);
  });

  it('it is an instant order with a deadline to answer by', async () => {
    await untyped();
    const row = await one(
      `select type, accept_deadline_at is not null as has_deadline from orders
        where customer_uid = $1 order by created_at desc limit 1`, [CUSTOMER]);
    assert.equal(row.type, 'instant');
    assert.equal(row.has_deadline, true);
  });
});
