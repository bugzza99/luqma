import { describe, it } from 'node:test';
import { strictEqual, ok } from 'node:assert';
import { freshDatabase } from './harness.mjs';

/**
 * Who decides what the extras cost.
 *
 * The whole reason `place_order` exists is that the phone's numbers are not trusted: it
 * reads the price out of `menu_items` rather than believing what the draft claims. That
 * held for the base price and **not** for the extras — `optionsTotal` arrived as a number
 * and was added to the price verbatim, with no check beyond `>= 0`.
 *
 * So a crafted request could order every extra on the menu and send `optionsTotal: 0`.
 * The merchant hands over the food, collects the base price in cash, and nothing anywhere
 * records that the difference existed. The anon key is public and sits inside every APK,
 * so nothing about that is hard.
 *
 * The client always had the option ids — the cart holds the chosen `MenuOption` objects
 * and flattened them to a number on the way out. Now it sends them, and the server prices
 * them the same way it prices everything else.
 */
describe('what the extras cost', () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';
  let db, merchant, item, addressId;

  const setup = async () => {
    db = await freshDatabase();
    await db.query('insert into auth.users (id) values ($1)', [CUSTOMER]);
    await db.query(`create or replace function auth.uid() returns uuid
      language sql stable as $fn$ select '${CUSTOMER}'::uuid $fn$`);
    await db.query(`update users set name='عميل', phone='01000000000' where id=$1`, [CUSTOMER]);

    await db.query(`insert into cities (id,name) values ('p','مدينة')`);
    const zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee) values ('p','منطقة',1000) returning id`
    )).rows[0].id;
    merchant = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status,delivers_self,min_order,opening_hours)
       values ('p','restaurant','مطعم',$1,'0100','approved',true,0,
         (select jsonb_agg(jsonb_build_object('weekday',d,'openMinute',0,'closeMinute',1439))
            from generate_series(0,6) d)) returning id`, [zone])).rows[0].id;
    await db.query(`insert into merchant_served_zones (merchant_id,zone_id) values ($1,$2)`,
      [merchant, zone]);
    const cat = (await db.query(
      `insert into menu_categories (merchant_id,name) values ($1,'أطباق') returning id`,
      [merchant])).rows[0].id;
    // One dish at 100.00, with two extras priced 5.00 and 7.50.
    item = (await db.query(
      `insert into menu_items (merchant_id,category_id,name,price,options)
       values ($1,$2,'سمك',10000,
         '[{"id":"o1","name":"صلصة","price":500},{"id":"o2","name":"أرز","price":750}]'::jsonb)
       returning id`, [merchant, cat])).rows[0].id;
    addressId = (await db.query(
      `insert into addresses (user_id,zone_id,label) values ($1,$2,'البيت') returning id`,
      [CUSTOMER, zone])).rows[0].id;
  };

  const place = (line) =>
    db.query('select place_order($1::jsonb) as o', [JSON.stringify({
      merchantId: merchant, addressId, type: 'instant',
      items: [{ itemId: item, name: 'سمك', unitPrice: 10000, quantity: 1, ...line }],
    })]).then((r) => r.rows[0].o.pricing);

  it('no extras is the dish alone', async () => {
    await setup();
    strictEqual((await place({})).subtotal, 10000);
    await db.close();
  });

  it('an extra is priced from the menu', async () => {
    await setup();
    strictEqual((await place({ optionIds: ['o1'] })).subtotal, 10500);
    await db.close();
  });

  it('two extras are both counted', async () => {
    await setup();
    strictEqual((await place({ optionIds: ['o1', 'o2'] })).subtotal, 11250);
    await db.close();
  });

  // The hole this file exists for. A client that asks for the extras and claims they are
  // free used to be believed.
  it('a claim of zero does not make an extra free', async () => {
    await setup();
    strictEqual(
      (await place({ optionIds: ['o1'], optionsTotal: 0 })).subtotal, 10500,
      'the menu decides, not the draft');
    await db.close();
  });

  it('and a claim of thousands does not inflate the bill either', async () => {
    await setup();
    strictEqual(
      (await place({ optionsTotal: 2000000000 })).subtotal, 10000,
      'a number nobody can verify is a number nobody should read');
    await db.close();
  });

  it('an extra this dish does not have is refused, not ignored', async () => {
    await setup();
    let refused = false;
    try {
      await place({ optionIds: ['o1', 'nope'] });
    } catch (e) {
      refused = e.code === 'P0001';
    }
    ok(refused, 'silently dropping it would charge for less than was ordered');
    await db.close();
  });

  it('the same extra twice is counted once', async () => {
    await setup();
    strictEqual((await place({ optionIds: ['o1', 'o1'] })).subtotal, 10500);
    await db.close();
  });

  it('extras multiply with the quantity, like the dish does', async () => {
    await setup();
    strictEqual((await place({ optionIds: ['o1'], quantity: 3 })).subtotal, 31500);
    await db.close();
  });
});

/**
 * Drafts no app would send.
 *
 * Probing the boundary turned up three refusals that were not refusals: 22003 twice and
 * 22P02 once, none of them classified, all arriving at a customer as "something went
 * wrong". The order was never going to succeed — what was wrong is that nothing could
 * say why.
 */
describe('the bounds on a draft', () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c2';
  let db, merchant, item, addressId;

  const setup = async () => {
    db = await freshDatabase();
    await db.query('insert into auth.users (id) values ($1)', [CUSTOMER]);
    await db.query(`create or replace function auth.uid() returns uuid
      language sql stable as $fn$ select '${CUSTOMER}'::uuid $fn$`);
    await db.query(`update users set name='ع', phone='01' where id=$1`, [CUSTOMER]);
    await db.query(`insert into cities (id,name) values ('b','مدينة')`);
    const zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee) values ('b','منطقة',1000) returning id`
    )).rows[0].id;
    merchant = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status,delivers_self,min_order,opening_hours)
       values ('b','restaurant','مطعم',$1,'0100','approved',true,0,
         (select jsonb_agg(jsonb_build_object('weekday',d,'openMinute',0,'closeMinute',1439))
            from generate_series(0,6) d)) returning id`, [zone])).rows[0].id;
    await db.query(`insert into merchant_served_zones (merchant_id,zone_id) values ($1,$2)`,
      [merchant, zone]);
    const cat = (await db.query(
      `insert into menu_categories (merchant_id,name) values ($1,'أ') returning id`,
      [merchant])).rows[0].id;
    item = (await db.query(
      `insert into menu_items (merchant_id,category_id,name,price) values ($1,$2,'سمك',12000) returning id`,
      [merchant, cat])).rows[0].id;
    addressId = (await db.query(
      `insert into addresses (user_id,zone_id,label) values ($1,$2,'ب') returning id`,
      [CUSTOMER, zone])).rows[0].id;
  };

  /** The SQLSTATE a refusal came back with, or null if it was accepted. */
  const refusal = async (draft) => {
    try {
      await db.query('select place_order($1::jsonb) as o', [JSON.stringify({
        merchantId: merchant, addressId, type: 'instant', ...draft,
      })]);
      return null;
    } catch (e) { return e.code; }
  };

  const line = (over = {}) => ({ itemId: item, name: 'سمك', unitPrice: 12000, quantity: 1, ...over });

  // 12000 * 200000 overflows an int4 subtotal. It used to come back as 22003.
  it('a quantity that would overflow the subtotal is a sentence, not a stack trace', async () => {
    await setup();
    strictEqual(await refusal({ items: [line({ quantity: 200000 })] }), 'P0001');
    await db.close();
  });

  it('and so is the largest integer there is', async () => {
    await setup();
    strictEqual(await refusal({ items: [line({ quantity: 2147483647 })] }), 'P0001');
    await db.close();
  });

  it('an itemId that is not a uuid is named as such', async () => {
    await setup();
    strictEqual(await refusal({ items: [line({ itemId: 'not-a-uuid' })] }), 'P0001');
    await db.close();
  });

  it('a thousand lines is a script, not a basket', async () => {
    await setup();
    strictEqual(await refusal({ items: Array(1000).fill(line()) }), 'P0001');
    await db.close();
  });

  // The note is read on a phone in the street. A hundred thousand characters of it is a
  // screen nobody can scroll past to reach the address.
  it('a note longer than a note is refused', async () => {
    await setup();
    strictEqual(await refusal({ items: [line()], note: 'ا'.repeat(100000) }), 'P0001');
    await db.close();
  });

  it('an ordinary order still goes through', async () => {
    await setup();
    strictEqual(await refusal({ items: [line({ quantity: 3 })], note: 'الجرس عطلان' }), null);
    await db.close();
  });
});
