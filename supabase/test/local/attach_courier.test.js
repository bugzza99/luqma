import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A shop attaching a courier by the number on a piece of paper.
 *
 * `read_staff` shows an owner their own account and the staff attached to their shop, so a
 * rider who works for the fish place is invisible to the koshari place. That is correct
 * and it is also the difficulty: they are the same rider.
 *
 * So the owner types a number they already have and this attaches whoever it belongs to.
 * It is deliberately not a search — no listing, no partial match — and it refuses anybody
 * who is not an active courier.
 */
describe('attaching a courier by their number', () => {
  const OWNER = '00000000-0000-0000-0000-0000000000b1';
  const RIDER = '00000000-0000-0000-0000-0000000000d5';
  const OTHER_OWNER = '00000000-0000-0000-0000-0000000000b2';
  let db, fish, koshari;

  const as = (uid, claims) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const owner = (m) => ({ role: 'owner', scope: 'merchant', merchant_id: m });

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id)
        values ('${OWNER}'), ('${RIDER}'), ('${OTHER_OWNER}');
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
      `insert into staff (uid,scope,role,merchant_id,is_active,name,phone)
       values ($1,'merchant','owner',$2,true,'صاحب المحل','01000000001')`,
      [OWNER, fish]);
    await db.query(
      `insert into staff (uid,scope,role,merchant_id,is_active,name,phone)
       values ($1,'merchant','owner',$2,true,'صاحب تاني','01000000003')`,
      [OTHER_OWNER, koshari]);
    // The rider already works for the koshari place. The fish place has their number.
    await db.query(
      `insert into staff (uid,scope,role,merchant_id,is_active,name,phone)
       values ($1,'merchant','courier',$2,true,'محمود','01000000002')`,
      [RIDER, koshari]);
  });

  after(async () => { await db?.close(); });

  const attach = async (uid, claims, merchant, phone) => {
    await as(uid, claims);
    await db.exec('set role authenticated');
    try {
      const r = await db.query(
        'select public.attach_courier_by_phone($1,$2) as r', [merchant, phone]);
      return r.rows[0].r;
    } finally {
      await db.exec('reset role');
    }
  };

  it('attaches a rider who already works for another shop', async () => {
    const r = await attach(OWNER, owner(fish), fish, '01000000002');

    assert.equal(r.name, 'محمود', 'enough to confirm the right person, and no more');
    assert.equal(r.attachment.merchant_id, fish);
    assert.equal(r.attachment.is_active, true);
  });

  // The same number typed the way an Arabic keyboard types it. The Dart normalises;
  // without the same two rules here, the shop is told the rider does not exist.
  it('and finds them when the number is typed in Arabic-Indic digits', async () => {
    const r = await attach(OWNER, owner(fish), fish, '٠١٠٠٠٠٠٠٠٠٢');
    assert.equal(r.name, 'محمود');
  });

  // A rider detached in March and brought back in June is the same row, not a second one.
  it('re-activates rather than duplicating', async () => {
    await db.query(
      `update courier_merchants set is_active = false
        where courier_uid = $1 and merchant_id = $2`, [RIDER, fish]);

    const r = await attach(OWNER, owner(fish), fish, '01000000002');
    assert.equal(r.attachment.is_active, true);

    const rows = await db.query(
      `select count(*)::int as n from courier_merchants
        where courier_uid = $1 and merchant_id = $2`, [RIDER, fish]);
    assert.equal(rows.rows[0].n, 1);
  });

  it('refuses a number that belongs to nobody', async () => {
    await assert.rejects(
      () => attach(OWNER, owner(fish), fish, '01099999999'),
      /no active courier/);
  });

  // Attaching an owner would hand them a rider's read of another shop's orders.
  it('refuses a number that belongs to an owner rather than a courier', async () => {
    await assert.rejects(
      () => attach(OWNER, owner(fish), fish, '01000000003'),
      /no active courier/);
  });

  it('refuses a dismissed courier', async () => {
    await db.query(`do $$ begin
      perform set_config('app.server_mode','on',true);
      update public.staff set is_active = false where uid = '${RIDER}';
    end $$;`);

    await assert.rejects(
      () => attach(OWNER, owner(fish), fish, '01000000002'),
      /no active courier/);

    await db.query(`do $$ begin
      perform set_config('app.server_mode','on',true);
      update public.staff set is_active = true where uid = '${RIDER}';
    end $$;`);
  });

  // The boundary. An owner staffs their own shop and nobody else's.
  it('refuses an owner attaching to a shop that is not theirs', async () => {
    await assert.rejects(
      () => attach(OWNER, owner(fish), koshari, '01000000002'),
      /only this shop/);
  });

  it('and refuses a courier attaching themselves anywhere', async () => {
    await assert.rejects(
      () => attach(RIDER, { role: 'courier', scope: 'merchant' }, fish, '01000000002'),
      /only this shop/);
  });
});

/**
 * And then the shop has to be able to read the rider it just attached.
 *
 * `read_staff` lets an owner see the staff whose **`staff.merchant_id`** is their shop.
 * That column is a scalar and holds one shop, so a rider who works for the koshari place
 * and was attached to the fish place is, to the fish place, an attachment row with no name
 * and no telephone number on it — which is the roster screen showing a blank where a
 * person goes, for exactly the riders the join table was built for.
 */
describe('reading the rider a shop attached', () => {
  const OWNER = '00000000-0000-0000-0000-0000000000b3';
  const RIDER = '00000000-0000-0000-0000-0000000000d6';
  let db, fish, koshari;

  const as = (uid, claims) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${OWNER}'), ('${RIDER}');
      grant usage on schema auth to authenticated;
      insert into cities (id,name) values ('edku','إدكو');`);
    const zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee)
       values ('edku','الزغبي',1000) returning id`)).rows[0].id;
    const shop = async (n) => (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ('edku','restaurant',$1,$2,'0100','approved') returning id`,
      [n, zone])).rows[0].id;
    fish = await shop('السمك');
    koshari = await shop('الكشري');

    await db.query(
      `insert into staff (uid,scope,role,merchant_id,is_active,name,phone)
       values ($1,'merchant','owner',$2,true,'صاحب السمك','01000000010')`, [OWNER, fish]);
    // The rider's own row still names the koshari place.
    await db.query(
      `insert into staff (uid,scope,role,merchant_id,is_active,name,phone)
       values ($1,'merchant','courier',$2,true,'محمود','01000000011')`, [RIDER, koshari]);
    await db.query(
      'insert into courier_merchants (courier_uid, merchant_id) values ($1,$2)',
      [RIDER, fish]);
  });

  after(async () => { await db?.close(); });

  it('shows the owner the name and number of a rider on their roster', async () => {
    await as(OWNER, { role: 'owner', scope: 'merchant', merchant_id: fish });
    await db.exec('set role authenticated');
    const r = await db.query('select name, phone from staff where uid = $1', [RIDER]);
    await db.exec('reset role');

    assert.equal(r.rowCount, 1, 'a roster row with no person on it is a blank line');
    assert.equal(r.rows[0].name, 'محمود');
  });

  // And no further. Being able to read one's own riders is not a directory.
  it('and no staff the shop has not attached', async () => {
    const stranger = '00000000-0000-0000-0000-0000000000d7';
    await db.query(`insert into auth.users (id) values ('${stranger}')`);
    await db.query(
      `insert into staff (uid,scope,role,merchant_id,is_active,name,phone)
       values ($1,'merchant','courier',$2,true,'غريب','01000000012')`,
      [stranger, koshari]);

    await as(OWNER, { role: 'owner', scope: 'merchant', merchant_id: fish });
    await db.exec('set role authenticated');
    const r = await db.query('select uid from staff where uid = $1', [stranger]);
    await db.exec('reset role');

    assert.equal(r.rowCount, 0);
  });
});
