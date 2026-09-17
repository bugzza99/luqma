import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A shop's own address.
 *
 * It had a zone and a telephone number and nothing else, which was enough while a courier
 * belonged to one merchant they knew by heart. A rider carrying for three shops is handed
 * a card naming a kitchen they may never have been to.
 */
describe("a shop's address", () => {
  const OWNER = '00000000-0000-0000-0000-0000000000c9';
  let db, shop, landmark;

  const as = (uid, claims) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${OWNER}');
      grant usage on schema auth to authenticated;
      insert into cities (id,name) values ('edku','إدكو');`);
    const zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee)
       values ('edku','الزغبي',1000) returning id`)).rows[0].id;
    landmark = (await db.query(
      `insert into landmarks (city_id,zone_id,name,lat,lng)
       values ('edku',$1,'صيدلية النور',31.3084,30.2939) returning id`,
      [zone])).rows[0].id;
    shop = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ('edku','restaurant','مطعم',$1,'0100','approved') returning id`,
      [zone])).rows[0].id;
    await db.query(
      `insert into staff (uid,scope,role,merchant_id,is_active)
       values ($1,'merchant','owner',$2,true)`, [OWNER, shop]);
  });

  after(async () => { await db?.close(); });

  const asOwner = async (fn) => {
    await as(OWNER, { role: 'owner', scope: 'merchant', merchant_id: shop });
    await db.exec('set role authenticated');
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  // The reason the column guard was widened: a shop that cannot say where it is, is a
  // shop the owner has to telephone about, six hundred times.
  it('is the owner’s to write', async () => {
    await asOwner(() => db.query(
      `update merchants
          set street = 'شارع البحر', landmark_id = $1, landmark_name = 'صيدلية النور',
              lat = 31.3084, lng = 30.2939
        where id = $2`, [landmark, shop]));

    const r = await db.query(
      'select street, landmark_name, lat from merchants where id = $1', [shop]);
    assert.equal(r.rows[0].street, 'شارع البحر');
    assert.equal(Number(r.rows[0].lat), 31.3084);
  });

  // The guard is what stops the same statement rewriting the things it must not.
  it('and the same write cannot move the shop to another zone', async () => {
    const other = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee)
       values ('edku','منطقة تانية',1000) returning id`)).rows[0].id;

    await assert.rejects(
      () => asOwner(() => db.query(
        'update merchants set street = $1, zone_id = $2 where id = $3',
        ['شارع تاني', other, shop])),
      /not yours to change|insufficient/i);
  });

  it('refuses half a pin', async () => {
    await assert.rejects(
      () => asOwner(() => db.query(
        'update merchants set lat = 31.3, lng = null where id = $1', [shop])),
      /merchants_pin_is_on_earth/);
  });

  it('and a pin that is not on Earth', async () => {
    await assert.rejects(
      () => asOwner(() => db.query(
        'update merchants set lat = 913, lng = 30.29 where id = $1', [shop])),
      /merchants_pin_is_on_earth/);
  });

  // A shop with no address is still a shop. Every merchant that exists today has none.
  it('stays optional', async () => {
    const bare = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ('edku','restaurant','بدون عنوان',
               (select zone_id from merchants where id=$1),'0100','approved')
       returning street, lat`, [shop])).rows[0];
    assert.equal(bare.street, null);
    assert.equal(bare.lat, null);
  });
});
