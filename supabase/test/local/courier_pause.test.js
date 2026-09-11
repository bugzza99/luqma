import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A courier saying "not now" — and saying nothing else.
 *
 * `staff` is the table every policy in the database reads to decide who you are, so
 * letting its own subjects write it is the part worth being careful about. A courier may
 * set when they are back. They may not set what they are.
 *
 * Everything runs after `set role authenticated`: PGlite's owner is a superuser and FORCE
 * does not constrain one, so a write that succeeds as the harness owner proves nothing.
 */
describe('a courier pausing themselves', () => {
  const COURIER = '00000000-0000-0000-0000-0000000000d3';
  const OTHER = '00000000-0000-0000-0000-0000000000d4';
  let db, shop;

  const as = (uid, claims) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const courier = { role: 'courier', scope: 'merchant' };

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${COURIER}'), ('${OTHER}');
      grant usage on schema auth to authenticated;
      insert into cities (id,name) values ('edku','إدكو');`);
    const zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee)
       values ('edku','الزغبي',1000) returning id`)).rows[0].id;
    shop = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ('edku','restaurant','مطعم',$1,'0100','approved') returning id`,
      [zone])).rows[0].id;
    for (const uid of [COURIER, OTHER]) {
      await db.query(
        `insert into staff (uid,scope,role,merchant_id,is_active)
         values ($1,'merchant','courier',$2,true)`, [uid, shop]);
    }
  });

  after(async () => { await db?.close(); });

  const asCourier = async (fn) => {
    await as(COURIER, courier);
    await db.exec('set role authenticated');
    try {
      return await fn();
    } finally {
      await db.exec('reset role');
    }
  };

  it('sets when it is back', async () => {
    await asCourier(() => db.query(
      `update staff set paused_until = now() + interval '1 hour' where uid = $1`,
      [COURIER]));

    const r = await db.query('select paused_until from staff where uid = $1', [COURIER]);
    assert.ok(r.rows[0].paused_until, 'the pause is stored');
  });

  it('and comes back by clearing it', async () => {
    await asCourier(() => db.query(
      'update staff set paused_until = null where uid = $1', [COURIER]));

    const r = await db.query('select paused_until from staff where uid = $1', [COURIER]);
    assert.equal(r.rows[0].paused_until, null);
  });

  // The reason the guard exists. `using (uid = auth.uid())` alone would let a courier
  // rewrite what they are, and every predicate in the database believes this row.
  it('cannot promote itself to owner', async () => {
    await assert.rejects(
      () => asCourier(() => db.query(
        `update staff set role = 'owner' where uid = $1`, [COURIER])),
      /may only pause itself/);
  });

  it('cannot move itself to another shop', async () => {
    const other = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ('edku','restaurant','تاني',(select zone_id from merchants where id=$1),
               '0100','approved') returning id`, [shop])).rows[0].id;

    await assert.rejects(
      () => asCourier(() => db.query(
        'update staff set merchant_id = $1 where uid = $2', [other, COURIER])),
      /may only pause itself/);
  });

  // The activation guard was already there and still is: a dismissal is the server's.
  it('cannot reactivate itself', async () => {
    await db.query(`do $$ begin
      perform set_config('app.server_mode','on',true);
      update public.staff set is_active = false where uid = '${COURIER}';
    end $$;`);

    await assert.rejects(
      () => asCourier(() => db.query(
        'update staff set is_active = true where uid = $1', [COURIER])),
      /activation changes must use the server boundary|may only pause itself/);

    await db.query(`do $$ begin
      perform set_config('app.server_mode','on',true);
      update public.staff set is_active = true where uid = '${COURIER}';
    end $$;`);
  });

  it('and cannot pause anybody else', async () => {
    await assert.rejects(
      () => asCourier(async () => {
        const r = await db.query(
          `update staff set paused_until = now() + interval '1 hour'
            where uid = $1 returning uid`, [OTHER]);
        // RLS filters rather than refuses, so an empty result is the refusal.
        if (r.rowCount === 0) throw new Error('no rows: the policy filtered it away');
        return r;
      }),
      /no rows/);
  });
});
