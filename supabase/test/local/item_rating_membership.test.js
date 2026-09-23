import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A delivered order buys a vote on its own food, not on the rest of the shop's menu.
 *
 * The policies on `item_ratings` checked the customer, the order, that it was delivered,
 * and that it belonged to the same merchant — and never that the dish being rated was on
 * it. So one real order from a shop let a customer put one star on every other item that
 * shop sells, and `refresh_item_rating` wrote each of those into `menu_items.rating_avg`,
 * which is what every dish card and «الأكتر طلباً» are built from.
 *
 * Two things about how this is tested, both of which the codebase has learned the hard
 * way. **PGlite's owner is a superuser, and FORCE does not constrain one** — an insert
 * that succeeds as the harness owner says nothing at all about a policy, so everything
 * below runs after `set role authenticated`. And **the order is placed by `place_order`
 * rather than assembled by hand**: the policy matches on the `itemId` key inside the
 * frozen `items` jsonb, and a fixture that writes that array itself is a fixture agreeing
 * with the policy about a shape neither of them got from the function that produces it.
 */
describe('ratings belong to the food delivered', () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';
  let db, merchant, ordered, other, delivered, undelivered, addressId;

  const place = async (itemId) => {
    const order = await db.query('select place_order($1::jsonb) as o', [JSON.stringify({
      merchantId: merchant, type: 'instant', addressId,
      items: [{ itemId, name: 'طبق', unitPrice: 1000, quantity: 1 }],
    })]).then((r) => r.rows[0].o);
    return order.id;
  };

  // The guards fire on an ordinary update, so a status move needs server mode declared
  // and it is transaction-local — one `do` block per statement.
  const step = (id, status) => db.query(`do $$ begin
      perform set_config('app.server_mode','on',true);
      update public.orders set status='${status}' where id='${id}';
    end $$;`);

  before(async () => {
    db = await freshDatabase();
    await db.exec(`insert into auth.users (id) values ('${CUSTOMER}');
      create or replace function auth.uid() returns uuid language sql stable
        as $fn$ select '${CUSTOMER}'::uuid $fn$;
      create or replace function auth.jwt() returns jsonb language sql stable
        as $fn$ select '{}'::jsonb $fn$;
      grant usage on schema auth to authenticated;
      insert into cities (id,name) values ('rating','مدينة');`);
    await db.query(
      `update users set name='عميل', phone='01000000000' where id=$1`, [CUSTOMER]);

    const zone = (await db.query(`insert into zones (city_id,name,default_delivery_fee)
      values ('rating','منطقة',0) returning id`)).rows[0].id;

    // 1..7, never 0..6: `merchant_open_at` counts Monday=1 to Sunday=7, and a 0..6 series
    // leaves the shop shut on Sundays — six runs in seven pass and the seventh reads as a
    // flake rather than as the fixture it is.
    merchant = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status,delivers_self,
                              opening_hours)
       values ('rating','restaurant','مطعم',$1,'0100','approved',true,
         (select jsonb_agg(jsonb_build_object('weekday',d,'openMinute',0,'closeMinute',1439))
            from generate_series(1,7) d)) returning id`, [zone])).rows[0].id;
    const cat = (await db.query(
      `insert into menu_categories (merchant_id,name) values ($1,'أطباق') returning id`,
      [merchant])).rows[0].id;
    const items = (await db.query(
      `insert into menu_items (merchant_id,category_id,name,price,is_available)
       values ($1,$2,'طبق',1000,true),($1,$2,'طبق آخر',1000,true) returning id`,
      [merchant, cat])).rows;
    [ordered, other] = items.map((r) => r.id);
    // Food to be delivered names where it goes (20261101190000).
    addressId = (await db.query(
      `insert into addresses (user_id,zone_id,label) values ($1,$2,'البيت') returning id`,
      [CUSTOMER, zone])).rows[0].id;

    delivered = await place(ordered);
    for (const s of ['accepted', 'preparing', 'outForDelivery', 'delivered']) {
      await step(delivered, s);
    }
    // A second order for the same dish that never arrived, so the delivered condition is
    // proven by a row that differs in nothing else.
    undelivered = await place(ordered);

    await db.exec('set role authenticated');
    assert.equal(
      (await db.query('select current_user as role')).rows[0].role, 'authenticated',
      'the policies are only being exercised if this is not the owner');
  });

  after(async () => { await db?.close(); });

  const rate = (order, item, stars) => db.query(
    `insert into item_ratings (order_id,item_id,merchant_id,customer_uid,stars)
     values ($1,$2,$3,$4,$5)`, [order, item, merchant, CUSTOMER, stars]);

  it('accepts the dish that was actually on the order', async () => {
    await rate(delivered, ordered, 4);

    const saved = await db.query(
      'select stars from item_ratings where order_id = $1', [delivered]);
    assert.deepEqual(saved.rows, [{ stars: 4 }]);
  });

  // Changing one's mind is the whole reason the update policy exists.
  it('and lets the customer correct it', async () => {
    const corrected = await db.query(
      `update item_ratings set stars = 5 where order_id = $1 and item_id = $2
       returning stars`, [delivered, ordered]);

    assert.deepEqual(corrected.rows, [{ stars: 5 }]);
  });

  // The finding.
  it('refuses a dish from the same shop that was never ordered', async () => {
    await assert.rejects(() => rate(delivered, other, 1), { code: '42501' });
  });

  // The other way in: rate what you ate, then move the stars onto what you did not.
  // `using` judges the row as it is and `with check` the row as it will be, so an update
  // that borrows a legitimate rating's ownership has to be refused by the second.
  it('and refuses moving a legitimate rating onto another dish', async () => {
    await assert.rejects(
      () => db.query(`update item_ratings set item_id = $1
        where order_id = $2 and item_id = $3`, [other, delivered, ordered]),
      { code: '42501' });
  });

  // Food that has not arrived has not been eaten. This was already true of the insert and
  // is now true of a correction as well.
  it('refuses the right dish on an order that has not been delivered', async () => {
    await assert.rejects(() => rate(undelivered, ordered, 5), { code: '42501' });
  });
});
