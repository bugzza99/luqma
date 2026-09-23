import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * Every line of a draft is a whole number of a dish, with a bounded note and a bounded
 * list of extras — refused as a bad request (22023) when it is not.
 *
 * `check_draft_bounds` cast `quantity` with `::int`, so «1.5» escaped as 22P02, an error
 * the phone has no sentence for; and the per-line `note` and `optionIds` were copied onto
 * the order at whatever length arrived. The order's own note and the complaint are
 * bounded; a line was the one free text left that a hand-written request could fill with
 * a megabyte, on a row every admin, merchant and courier screen then reads.
 */
describe('the lines of a draft are bounded', () => {
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

  const line = (extra = {}) =>
    ({ itemId: item, name: 'كشري', unitPrice: 5000, quantity: 1, ...extra });
  const place = (items) => db.query('select place_order($1::jsonb) as o', [JSON.stringify({
    merchantId: kitchen, addressId, type: 'instant', items,
  })]);
  const refused = (items) => assert.rejects(place(items), (e) => e.code === '22023');

  it('half a dish is a bad request, not a crash', () => refused([line({ quantity: 1.5 })]));
  it('a quantity written as words is too', () => refused([line({ quantity: 'two' })]));
  it('a thousand of one dish keeps the sentence it always had', () =>
    assert.rejects(place([line({ quantity: 1000 })]), /more of one dish/));
  it('a line note past 500 characters is refused', () =>
    refused([line({ note: 'ا'.repeat(501) })]));
  it('extras that are not a list are refused', () => refused([line({ optionIds: 'x' })]));
  it('more than 30 extras on one line are refused', () =>
    refused([line({ optionIds: Array.from({ length: 31 }, (_, i) => `o${i}`) })]));
  it('more than 50 lines keep the sentence the phone maps', () =>
    assert.rejects(place(Array.from({ length: 51 }, () => line())), /too many different items/));
  it('items that are not a list are refused', () => refused({ a: 1 }));

  it('an ordinary basket goes through', async () => {
    await place([line({ quantity: 2, note: 'من غير بصل', optionIds: [] }), line()]);
  });

  it('a quantity sent as a string of digits is still read', async () => {
    await place([line({ quantity: '3' })]);
  });
});
