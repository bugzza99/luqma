import { describe, it } from 'node:test';
import { strictEqual, ok, rejects } from 'node:assert';
import { freshDatabase } from './harness.mjs';

/**
 * Four rules the phone enforced and the server did not.
 *
 * Every one of these was reachable by an ordinary customer — a basket left open while the
 * kitchen changed its mind, a shop created through AdminApp, a delivery override the admin
 * moved — and none of them needed a crafted request. The suite stayed green throughout,
 * because the fakes are more permissive than Postgres and no widget test leaves the phone.
 *
 * The money one is the reason this file exists: `Delivery.quotedOverride` clamps a
 * merchant's override into the admin's range and this function read the column raw, so the
 * screen said one number and the courier collected another.
 */
describe('rules the server had never been told', () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';
  let db, merchant, item, homeZone, farZone, addressHome, addressFar;

  // `servedRow` defaults on so that every test below proves its *own* rule. Without it
  // they all fail at the first gate — «المطعم مبيوصلش المنطقة دي» — which is true and
  // useless: one broken rule masks the other three. The zone tests turn it off, because
  // the absence of that row is the thing they are about.
  const setup = async ({ deliveryOverride = null, minOrder = 0, servedRow = true } = {}) => {
    db = await freshDatabase();
    await db.query('insert into auth.users (id) values ($1)', [CUSTOMER]);
    await db.query(`create or replace function auth.uid() returns uuid
      language sql stable as $fn$ select '${CUSTOMER}'::uuid $fn$`);
    await db.query(`update users set name='عميل', phone='01000000000' where id=$1`, [CUSTOMER]);

    await db.query(`insert into cities (id,name) values ('p','مدينة')`);
    homeZone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee) values ('p','منطقة المحل',1000) returning id`
    )).rows[0].id;
    farZone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee) values ('p','منطقة بعيدة',1000) returning id`
    )).rows[0].id;

    // 1..7, not 0..6 — `merchant_open_at` counts Monday=1 to Sunday=7, so a 0..6 series
    // leaves the shop shut on Sundays and the file passes six days in seven.
    merchant = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status,delivers_self,
                              min_order,delivery_fee_override,opening_hours)
       values ('p','restaurant','مطعم',$1,'0100','approved',true,$2,$3,
         (select jsonb_agg(jsonb_build_object('weekday',d,'openMinute',0,'closeMinute',1439))
            from generate_series(1,7) d)) returning id`,
      [homeZone, minOrder, deliveryOverride])).rows[0].id;

    // `servedRow: false` is the state every shop created through AdminApp is in, because
    // nothing in the product writes this table.
    if (servedRow) {
      await db.query(
        'insert into merchant_served_zones (merchant_id,zone_id) values ($1,$2)',
        [merchant, homeZone]);
    }

    const cat = (await db.query(
      `insert into menu_categories (merchant_id,name) values ($1,'أطباق') returning id`,
      [merchant])).rows[0].id;
    item = (await db.query(
      `insert into menu_items (merchant_id,category_id,name,price,is_available)
       values ($1,$2,'سمك',10000,true) returning id`, [merchant, cat])).rows[0].id;

    addressHome = (await db.query(
      `insert into addresses (user_id,zone_id,label) values ($1,$2,'البيت') returning id`,
      [CUSTOMER, homeZone])).rows[0].id;
    addressFar = (await db.query(
      `insert into addresses (user_id,zone_id,label) values ($1,$2,'بعيد') returning id`,
      [CUSTOMER, farZone])).rows[0].id;
  };

  const place = (addressId, quantity = 1) =>
    db.query('select place_order($1::jsonb) as o', [JSON.stringify({
      merchantId: merchant, addressId, type: 'instant',
      items: [{ itemId: item, name: 'سمك', unitPrice: 10000, quantity }],
    })]).then((r) => r.rows[0].o);

  // A shop serves the street it stands on. `Delivery.serves` says so and the server did
  // not know it, so every merchant the owner created was one the phone offered and the
  // server refused — «المطعم مبيوصلش المنطقة دي» on an address across the road.
  it('delivers to the zone it stands in, with no junction row', async () => {
    await setup({ servedRow: false });
    const order = await place(addressHome);
    strictEqual(order.pricing.deliveryFee, 1000);
  });

  it('still refuses a zone it has not said it reaches', async () => {
    await setup({ servedRow: false });
    await rejects(() => place(addressFar), /does not deliver/);
  });

  it('and accepts that zone once it does', async () => {
    await setup({ servedRow: false });
    await db.query(
      'insert into merchant_served_zones (merchant_id,zone_id) values ($1,$2)',
      [merchant, farZone]);
    const order = await place(addressFar);
    strictEqual(order.pricing.deliveryFee, 1000);
  });

  // The one that moves money. Quoted 110 on the screen, collected 125 at the door.
  describe('the delivery fee is clamped where the phone clamps it', () => {
    // Within the column's own 500..2000 check, and outside the admin's configured range —
    // which is the reachable gap, and the one the phone and the door disagreed across.
    it('raises an override below the configured minimum', async () => {
      await setup({ deliveryOverride: 600 });
      await db.query(
        `insert into config (key,value) values ('delivery_fee_min','800'::jsonb),
                                               ('delivery_fee_max','1500'::jsonb)
         on conflict (key) do update set value = excluded.value`);
      const order = await place(addressHome);
      strictEqual(order.pricing.deliveryFee, 800);
    });

    it('lowers one above the configured maximum', async () => {
      await setup({ deliveryOverride: 1900 });
      await db.query(
        `insert into config (key,value) values ('delivery_fee_min','500'::jsonb),
                                               ('delivery_fee_max','1500'::jsonb)
         on conflict (key) do update set value = excluded.value`);
      const order = await place(addressHome);
      strictEqual(order.pricing.deliveryFee, 1500);
    });

    // Zero is an offer a merchant makes, not a value out of range — the same exception
    // `Delivery.quotedOverride` carries.
    it('leaves a deliberate zero alone', async () => {
      await setup({ deliveryOverride: 0 });
      await db.query(
        `insert into config (key,value) values ('delivery_fee_min','800'::jsonb)
         on conflict (key) do update set value = excluded.value`);
      const order = await place(addressHome);
      strictEqual(order.pricing.deliveryFee, 0);
    });
  });

  // A basket sits open for hours while a kitchen runs out. The phone greys the row the
  // moment it hears; nothing stopped the order that was already in the basket.
  it('refuses a dish the kitchen has run out of', async () => {
    await setup();
    await db.query('update menu_items set is_available = false where id = $1', [item]);
    await rejects(() => place(addressHome), /not available/);
  });

  // The only `min_order` this function checked was the coupon's.
  it('refuses a basket under the shop minimum', async () => {
    await setup({ minOrder: 20000 });
    await rejects(() => place(addressHome), /minimum/);
  });

  it('and accepts one that clears it', async () => {
    await setup({ minOrder: 20000 });
    const order = await place(addressHome, 2);
    strictEqual(order.pricing.subtotal, 20000);
  });

  // Measured against the food alone, matching `Cart.shortfallFrom`: a delivery fee is not
  // part of what a kitchen means by a small order, and counting it would let a distant
  // customer clear a minimum an adjacent one could not.
  it('measures the minimum against the food, not the bill', async () => {
    await setup({ minOrder: 10500 });
    await rejects(() => place(addressHome), /minimum/);
  });
});
