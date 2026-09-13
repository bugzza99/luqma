import { describe, it } from 'node:test';
import { strictEqual, ok, rejects } from 'node:assert';
import { freshDatabase } from './harness.mjs';

/**
 * The optional pin on an address and on a landmark.
 *
 * `Landmark` and `Address` in Dart have carried `lat`/`lng` since Phase 1 and
 * `docs/09-geography-and-maps.md` specifies both, but no column existed for either — so
 * `SupabaseAddressRepository` listed the fields it may write and left the two out,
 * because sending a key no column has fails the write outright. The map layer was never
 * a missing screen over working data; there was nowhere to put a coordinate.
 *
 * What these pin is that a coordinate can be stored, that an address without one is still
 * perfectly valid — Edku is addressed by zone and words, and the map is the supporting
 * layer — and that half a pin is refused, because a latitude with no longitude draws a
 * marker in the Gulf of Guinea rather than no marker at all.
 */
describe('an address pin', () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';

  const db = async () => {
    const d = await freshDatabase();
    await d.query(`insert into auth.users (id) values ($1)`, [CUSTOMER]);
    await d.query(`insert into cities (id, name) values ('edku', 'إدكو')`);
    const zone = await d.query(
      `insert into zones (city_id, name, default_delivery_fee)
       values ('edku', 'الزغبي', 1500) returning id`,
    );
    return { d, zone: zone.rows[0].id };
  };

  const address = (zone, pin) => [
    `insert into addresses (user_id, zone_id, street, label, lat, lng)
     values ($1, $2, 'شارع البحر', 'البيت', $3, $4) returning id, lat, lng`,
    [CUSTOMER, zone, pin?.[0] ?? null, pin?.[1] ?? null],
  ];

  it('is saved when the customer drops one', async () => {
    const { d, zone } = await db();
    const saved = await d.query(...address(zone, [31.3084, 30.2939]));

    strictEqual(Number(saved.rows[0].lat), 31.3084);
    strictEqual(Number(saved.rows[0].lng), 30.2939);
  });

  it('is null when they do not, and the address is no less valid', async () => {
    const { d, zone } = await db();
    const saved = await d.query(...address(zone, null));

    strictEqual(saved.rows[0].lat, null);
    strictEqual(saved.rows[0].lng, null);
    ok(saved.rows[0].id, 'an address without a pin still saves');
  });

  it('is refused as half a pin', async () => {
    const { d, zone } = await db();

    await rejects(
      () => d.query(...address(zone, [31.3084, null])),
      /addresses_pin_is_on_earth/,
      'a latitude with no longitude is not a partial pin, it is undrawable',
    );
  });

  it('is refused when it is not a place on Earth', async () => {
    const { d, zone } = await db();

    await rejects(
      () => d.query(...address(zone, [913, 30.2939])),
      /addresses_pin_is_on_earth/,
    );
  });

  it('is the same story for a landmark', async () => {
    const { d, zone } = await db();

    const placed = await d.query(
      `insert into landmarks (city_id, zone_id, name, lat, lng)
       values ('edku', $1, 'صيدلية النور', 31.3101, 30.2922) returning lat, lng`,
      [zone],
    );
    strictEqual(Number(placed.rows[0].lat), 31.3101);

    // The thirty landmarks already entered have no pin, and must keep working while
    // somebody places them one at a time.
    const unplaced = await d.query(
      `insert into landmarks (city_id, zone_id, name) values ('edku', $1, 'الجامع')
       returning lat`,
      [zone],
    );
    strictEqual(unplaced.rows[0].lat, null);

    await rejects(
      () => d.query(
        `insert into landmarks (city_id, zone_id, name, lat) values ('edku', $1, 'x', 5)`,
        [zone],
      ),
      /landmarks_pin_is_on_earth/,
    );
  });
});

/**
 * And the pin has to survive the handoff.
 *
 * Storing a coordinate is the first half; the courier is the reason for it. An order
 * freezes a **copy** of the address — a courier cannot read another person's address row,
 * so a reference would render as nothing in the street — and that copy was built field by
 * field in `place_order_priced` from a list written before the columns existed. It named
 * ten fields and not these two, so the pin stopped at the customer's own account: saved,
 * drawn on their map, and absent from every screen that had to drive to it.
 */
describe('the pin the courier gets', () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';
  let db, merchant, item, zone;

  const setup = async () => {
    db = await freshDatabase();
    await db.query('insert into auth.users (id) values ($1)', [CUSTOMER]);
    await db.query(`create or replace function auth.uid() returns uuid
      language sql stable as $fn$ select '${CUSTOMER}'::uuid $fn$`);
    await db.query(`update users set name='عميل', phone='01000000000' where id=$1`,
      [CUSTOMER]);

    await db.query(`insert into cities (id,name) values ('edku','إدكو')`);
    zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee)
       values ('edku','الزغبي',1000) returning id`)).rows[0].id;
    merchant = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status,delivers_self,
                              opening_hours)
       values ('edku','restaurant','مطعم',$1,'0100','approved',true,
         (select jsonb_agg(jsonb_build_object('weekday',d,'openMinute',0,'closeMinute',1439))
            from generate_series(1,7) d)) returning id`, [zone])).rows[0].id;
    const cat = (await db.query(
      `insert into menu_categories (merchant_id,name) values ($1,'أطباق') returning id`,
      [merchant])).rows[0].id;
    item = (await db.query(
      `insert into menu_items (merchant_id,category_id,name,price,is_available)
       values ($1,$2,'سمك',10000,true) returning id`, [merchant, cat])).rows[0].id;
  };

  const placeTo = async (pin) => {
    const addressId = (await db.query(
      `insert into addresses (user_id,zone_id,street,lat,lng)
       values ($1,$2,'شارع البحر',$3,$4) returning id`,
      [CUSTOMER, zone, pin?.[0] ?? null, pin?.[1] ?? null])).rows[0].id;
    return db.query('select place_order($1::jsonb) as o', [JSON.stringify({
      merchantId: merchant, addressId, type: 'instant',
      items: [{ itemId: item, name: 'سمك', unitPrice: 10000, quantity: 1 }],
    })]).then((r) => r.rows[0].o);
  };

  // The finding.
  it('is frozen onto the order with the rest of the address', async () => {
    await setup();
    const order = await placeTo([31.3084, 30.2939]);

    strictEqual(Number(order.address.lat), 31.3084);
    strictEqual(Number(order.address.lng), 30.2939);
  });

  // An address with no pin is ordinary here and must stay so: null, not absent-and-broken.
  it('is null on an order placed to an address that has none', async () => {
    await setup();
    const order = await placeTo(null);

    strictEqual(order.address.lat, null);
    strictEqual(order.address.lng, null);
    ok(order.address.street, 'and the words that actually address it are still there');
  });

  // A copy, not a reference — the whole reason the snapshot exists. Moving the pin next
  // month must not move where last week's order went.
  it('does not move when the customer moves theirs afterwards', async () => {
    await setup();
    const order = await placeTo([31.3084, 30.2939]);

    await db.query('update addresses set lat = 31.4, lng = 30.4 where user_id = $1',
      [CUSTOMER]);
    const frozen = (await db.query(
      'select address from orders where id = $1', [order.id])).rows[0].address;

    strictEqual(Number(frozen.lat), 31.3084);
  });
});
