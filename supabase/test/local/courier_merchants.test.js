import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A courier who carries for more than one shop.
 *
 * `staff.merchant_id` is a scalar and the token carries one `merchant_id` claim, so a
 * rider who delivers for two shops needed two accounts. `courier_merchants` is the
 * authority now, and the claim speaks only for owners.
 *
 * Everything below runs after `set role authenticated`, because PGlite's owner is a
 * superuser and FORCE does not constrain one — an insert that succeeds as the harness
 * owner says nothing at all about a policy.
 */
describe('a courier carries for more than one shop', () => {
  const COURIER = '00000000-0000-0000-0000-0000000000d1';
  const OWNER_A = '00000000-0000-0000-0000-0000000000a1';
  let db, fish, koshari;

  // The claims a signed-in account would carry. `merchant_id` is deliberately absent for
  // the courier: that is the whole point — one field cannot hold two shops.
  const as = (uid, claims) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${COURIER}'), ('${OWNER_A}');
      grant usage on schema auth to authenticated;
      insert into cities (id,name) values ('edku','إدكو');`);

    const zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee)
       values ('edku','الزغبي',1000) returning id`)).rows[0].id;
    const shop = async (name) => (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ('edku','restaurant',$1,$2,'0100','approved') returning id`,
      [name, zone])).rows[0].id;
    fish = await shop('مطعم السمك');
    koshari = await shop('الكشري');

    await db.query(
      `insert into staff (uid,scope,role,merchant_id,is_active)
       values ($1,'merchant','courier',$2,true)`, [COURIER, fish]);
    await db.query(
      `insert into staff (uid,scope,role,merchant_id,is_active)
       values ($1,'merchant','owner',$2,true)`, [OWNER_A, fish]);

    // Attached explicitly, because these rows are created after the migration ran and its
    // backfill only sees what was already there. The backfill itself is a one-shot over
    // production data and is verified by the run, not here — a PGlite database has no
    // staff until this fixture makes some.
    await db.query(
      'insert into courier_merchants (courier_uid, merchant_id) values ($1,$2)',
      [COURIER, fish]);
  });

  after(async () => { await db?.close(); });

  const carries = async (uid, claims, merchant) => {
    await as(uid, claims);
    await db.exec('set role authenticated');
    const r = await db.query('select public.courier_carries($1) as yes', [merchant]);
    await db.exec('reset role');
    return r.rows[0].yes;
  };

  const courierClaims = { role: 'courier', scope: 'merchant', merchant_id: null };

  it('carries the shop it is attached to', async () => {
    assert.equal(await carries(COURIER, courierClaims, fish), true);
  });

  it('and does not invent one it was never given', async () => {
    assert.equal(await carries(COURIER, courierClaims, koshari), false);
  });

  // The finding this exists for.
  it('carries for a second shop once attached, with no new account and no new token',
    async () => {
      await db.query(
        'insert into courier_merchants (courier_uid, merchant_id) values ($1,$2)',
        [COURIER, koshari]);

      assert.equal(await carries(COURIER, courierClaims, fish), true);
      assert.equal(await carries(COURIER, courierClaims, koshari), true,
        'the claim still says nothing, and the table is the authority');
    });

  // The merchant's menu, hours and orders all read this. A courier attached to a shop has
  // to be able to see what they are carrying.
  it('reads the shop it carries for through belongs_to_merchant', async () => {
    await as(COURIER, courierClaims);
    await db.exec('set role authenticated');
    const r = await db.query(
      'select public.belongs_to_merchant($1) as fish, public.belongs_to_merchant($2) as koshari',
      [fish, koshari]);
    await db.exec('reset role');
    assert.deepEqual(r.rows[0], { fish: true, koshari: true });
  });

  // The one that guards the money does not move. An owner is one shop's owner, and no
  // amount of attaching makes a courier one.
  it('never makes a courier an owner of anything', async () => {
    await as(COURIER, courierClaims);
    await db.exec('set role authenticated');
    const r = await db.query(
      'select public.is_merchant_owner($1) as fish, public.is_merchant_owner($2) as koshari',
      [fish, koshari]);
    await db.exec('reset role');
    assert.deepEqual(r.rows[0], { fish: false, koshari: false });
  });

  // A dismissal is a boundary change, not a claim change — and it has to reach through
  // the join as well as the staff row.
  it('stops carrying when the attachment is switched off', async () => {
    await db.query(
      'update courier_merchants set is_active = false where courier_uid = $1 and merchant_id = $2',
      [COURIER, koshari]);

    assert.equal(await carries(COURIER, courierClaims, koshari), false);
    assert.equal(await carries(COURIER, courierClaims, fish), true);
  });

  it('and stops carrying anything at all when the account is deactivated', async () => {
    // Deactivation goes through the server boundary — a guard refuses it otherwise, which
    // is the point of the guard.
    const active = (v) => db.query(`do $$ begin
      perform set_config('app.server_mode','on',true);
      update public.staff set is_active = ${v} where uid = '${COURIER}';
    end $$;`);

    await active(false);
    assert.equal(await carries(COURIER, courierClaims, fish), false);
    await active(true);
  });

  // Platform coverage is a row now rather than an exclusive scope, so a rider can carry
  // the home kitchens and two shops at once — which the old `scope` could not say.
  it('carries the platform and a shop at the same time', async () => {
    await db.query(
      'insert into courier_merchants (courier_uid, merchant_id) values ($1, null)',
      [COURIER]);

    await as(COURIER, courierClaims);
    await db.exec('set role authenticated');
    const r = await db.query(
      'select public.is_platform_courier() as platform, public.is_courier_for($1) as fish',
      [fish]);
    await db.exec('reset role');
    assert.deepEqual(r.rows[0], { platform: true, fish: true });
  });

  describe('who may change the roster', () => {
    const ownerClaims = (m) => ({ role: 'owner', scope: 'merchant', merchant_id: m });

    it('lets a shop owner attach a courier to their own shop', async () => {
      await as(OWNER_A, ownerClaims(fish));
      await db.exec('set role authenticated');
      await db.query(
        `delete from courier_merchants where courier_uid = $1 and merchant_id = $2`,
        [COURIER, fish]);
      await db.query(
        'insert into courier_merchants (courier_uid, merchant_id) values ($1,$2)',
        [COURIER, fish]);
      await db.exec('reset role');
    });

    it('and refuses them another shop', async () => {
      await as(OWNER_A, ownerClaims(fish));
      await db.exec('set role authenticated');
      await assert.rejects(
        () => db.query(
          'insert into courier_merchants (courier_uid, merchant_id) values ($1,$2)',
          [COURIER, koshari]),
        { code: '42501' });
      await db.exec('reset role');
    });

    // `using` judges the row as it stands and `with check` the row as it will be. Without
    // both, an owner who may write their own roster could move a row onto another shop.
    it('and refuses moving one of their own rows to another shop', async () => {
      await as(OWNER_A, ownerClaims(fish));
      await db.exec('set role authenticated');
      await assert.rejects(
        () => db.query(
          'update courier_merchants set merchant_id = $1 where courier_uid = $2 and merchant_id = $3',
          [koshari, COURIER, fish]),
        { code: '42501' });
      await db.exec('reset role');
    });

    // The platform is not any one shop's to staff.
    it('and refuses an owner the platform row', async () => {
      await as(OWNER_A, ownerClaims(fish));
      await db.exec('set role authenticated');
      await assert.rejects(
        () => db.query(
          'insert into courier_merchants (courier_uid, merchant_id) values ($1, null)',
          [OWNER_A]),
        { code: '42501' });
      await db.exec('reset role');
    });

    it('and a courier cannot attach themselves to anything', async () => {
      await as(COURIER, courierClaims);
      await db.exec('set role authenticated');
      await assert.rejects(
        () => db.query(
          'insert into courier_merchants (courier_uid, merchant_id) values ($1,$2)',
          [COURIER, koshari]),
        { code: '42501' });
      await db.exec('reset role');
    });
  });
});
