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

    // The insert trigger grants the initial scope for accounts created after backfill.
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

    it('requires the phone RPC even for an owner attaching to their own shop', async () => {
      const newcomer = '00000000-0000-0000-0000-0000000000d8';
      await db.query('insert into auth.users(id) values ($1)', [newcomer]);
      await db.query(`insert into staff(uid,role,scope,merchant_id)
        values ($1,'courier','merchant',$2)`, [newcomer, koshari]);
      await as(OWNER_A, ownerClaims(fish));
      await db.exec('set role authenticated');
      await assert.rejects(() => db.query(
        'insert into courier_merchants (courier_uid, merchant_id) values ($1,$2)',
        [newcomer, fish]), { code: '42501' });
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

/**
 * Detaching a courier has to actually detach them.
 *
 * `staff.merchant_id` is still a scalar and the access-token hook still copies it into the
 * JWT, so a courier who was attached to a shop when their account was made carries that
 * shop's id on their token for as long as the session lasts. The first version of
 * `belongs_to_merchant` accepted **either** that claim or the join — which meant the join
 * was not the authority it was introduced to be: switching a courier's attachment off left
 * them reading that shop's orders, with every customer's address and telephone number on
 * them.
 *
 * The claim arm belongs to owners. A courier is the join and nothing else.
 */
describe('a courier who has been detached', () => {
  const COURIER = '00000000-0000-0000-0000-0000000000d2';
  let db, shop, order;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${COURIER}');
      grant usage on schema auth to authenticated;
      insert into cities (id,name) values ('edku','إدكو');`);
    const zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee)
       values ('edku','الزغبي',1000) returning id`)).rows[0].id;
    shop = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ('edku','restaurant','مطعم',$1,'0100','approved') returning id`,
      [zone])).rows[0].id;

    // The scalar column still names the shop — that is the state every courier account
    // created before today is in, and what the token is stamped from.
    await db.query(
      `insert into staff (uid,scope,role,merchant_id,is_active)
       values ($1,'merchant','courier',$2,true)`, [COURIER, shop]);
    await db.query(
      `update courier_merchants set is_active=false where courier_uid=$1 and merchant_id=$2`,
      [COURIER, shop]);

    order = (await db.query(
      `insert into orders (city_id,customer_uid,customer_name,customer_phone,
                           merchant_id,merchant_name,zone_id,type,items,pricing,status)
       values ('edku',null,'عميل','01000000000',$1,'مطعم',$2,'instant','[]','{}','preparing')
       returning id`, [shop, zone])).rows[0].id;

    await db.exec(`
      create or replace function auth.uid() returns uuid language sql stable
        as $fn$ select '${COURIER}'::uuid $fn$;
      create or replace function auth.jwt() returns jsonb language sql stable
        as $fn$ select '${JSON.stringify({
          app_metadata: { role: 'courier', scope: 'merchant', merchant_id: null },
        })}'::jsonb $fn$;`);
  });

  after(async () => { await db?.close(); });

  const withShopClaim = (m) => db.exec(
    `create or replace function auth.jwt() returns jsonb language sql stable
       as $fn$ select '${JSON.stringify({
         app_metadata: { role: 'courier', scope: 'merchant' },
       })}'::jsonb || jsonb_build_object('app_metadata',
         jsonb_build_object('role','courier','scope','merchant','merchant_id','${m}'))
       $fn$;`);

  it('cannot read the shop it no longer carries for, whatever its token says',
    async () => {
      await withShopClaim(shop);
      await db.exec('set role authenticated');
      const rows = await db.query('select id from orders where id = $1', [order]);
      const belongs = await db.query(
        'select public.belongs_to_merchant($1) as yes', [shop]);
      await db.exec('reset role');

      assert.equal(belongs.rows[0].yes, false,
        'the claim is the owner path; a courier is the join and nothing else');
      assert.equal(rows.rowCount, 0,
        'that row carries the customer address and telephone number');
    });

  // And the platform is a row now, so holding it has to be enough to act.
  it('acts on a platform order on the strength of the platform row alone', async () => {
    await db.query(
      `insert into courier_merchants (courier_uid, merchant_id) values ($1, null)`,
      [COURIER]);
    const platformOrder = (await db.query(
      `insert into orders (city_id,customer_uid,customer_name,customer_phone,
                           merchant_id,merchant_name,zone_id,type,items,pricing,status,
                           delivery_by)
       values ('edku',null,'عميل','01000000000',$1,'مطعم',
               (select zone_id from merchants where id = $1),
               'instant','[]','{}','preparing','platform') returning id`,
      [shop])).rows[0].id;

    // Deliberately **without** the shop claim. With it this passed before the fix and for
    // the wrong reason: the stale `merchant_id` satisfied the predicate, so a test about
    // the platform row was being answered by the very claim this change exists to stop
    // trusting.
    await db.exec(`create or replace function auth.jwt() returns jsonb language sql stable
      as $$ select '{"app_metadata":{"role":"courier","scope":"merchant"}}'::jsonb $$;
      set role authenticated`);
    const visible = await db.query('select id from orders where id=$1',[platformOrder]);
    const changed = await db.query(`update orders set status='outForDelivery',courier_uid=$1
      where id=$2 returning id`,[COURIER,platformOrder]);
    await db.exec('reset role');

    assert.equal(visible.rowCount, 1);
    assert.equal(changed.rowCount, 1,
      'the actual order can be picked up using only the platform attachment');
  });
});
