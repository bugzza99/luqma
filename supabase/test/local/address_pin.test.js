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
