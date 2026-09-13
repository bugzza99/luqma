import { after, before, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

let db, shop, platformOrder;
const owner = '00000000-0000-0000-0000-000000000081';
const rider = '00000000-0000-0000-0000-000000000082';
const admin = '00000000-0000-0000-0000-0000000000ad';
async function as(uid, claims, fn) {
  await db.exec(`create or replace function auth.uid() returns uuid language sql stable
    as $$ select '${uid}'::uuid $$;
    create or replace function auth.jwt() returns jsonb language sql stable
    as $$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $$;
    set role authenticated;`);
  try { return await fn(); } finally { await db.exec('reset role'); }
}
before(async () => {
  db = await freshDatabase({ realtime: true });
  await db.exec(`grant usage on schema auth to authenticated;
    insert into auth.users(id) values ('${owner}'), ('${rider}');
    insert into cities(id,name) values ('review','Review');`);
  const zone = (await db.query(`insert into zones(city_id,name,default_delivery_fee)
    values ('review','Review',0) returning id`)).rows[0].id;
  shop = (await db.query(`insert into merchants(city_id,type,name,zone_id,phone,status)
    values ('review','restaurant','Review',$1,'0100','approved') returning id`, [zone])).rows[0].id;
  await db.query(`insert into staff(uid,scope,role,merchant_id) values ($1,'merchant','owner',$2)`, [owner,shop]);
  await db.query(`insert into staff(uid,scope,role,phone) values ($1,'platform','courier','01012345678')`, [rider]);
  await db.query(`insert into courier_merchants(courier_uid,merchant_id,is_active)
    values ($1,null,false) on conflict (courier_uid) where merchant_id is null do update set is_active=false`, [rider]);
  platformOrder = (await db.query(`insert into orders(city_id,customer_name,customer_phone,
    merchant_id,merchant_name,zone_id,type,items,pricing,status,delivery_by)
    values ('review','Customer','01000000000',$1,'Review',$2,'instant','[]','{}','preparing','platform') returning id`, [shop,zone])).rows[0].id;
});
after(async () => { await db?.close(); });

it('the application queue and courier attachments publish their live changes', async () => {
  const tables = (await db.query(`select tablename from pg_publication_tables
    where pubname='supabase_realtime'`)).rows.map(r => r.tablename);
  assert.ok(tables.includes('courier_merchants'));
  assert.ok(tables.includes('staff_applications'));
});

it('creating a courier grants its initial scope as an attachment', async () => {
  for (const [uid, scope, merchant] of [
    ['00000000-0000-0000-0000-000000000084','platform',null],
    ['00000000-0000-0000-0000-000000000085','merchant',shop],
  ]) {
    await db.query('insert into auth.users(id) values ($1)',[uid]);
    await db.query(`insert into staff(uid,scope,role,merchant_id) values ($1,$2,'courier',$3)`,[uid,scope,merchant]);
    const rows = await db.query(`select merchant_id,is_active from courier_merchants where courier_uid=$1`,[uid]);
    assert.deepEqual(rows.rows,[{merchant_id:merchant,is_active:true}]);
  }
});

it('an owner cannot manufacture a roster link to read an admin account', async () => {
  await as(owner,{role:'owner',scope:'merchant',merchant_id:shop},async () => {
    assert.equal((await db.query('select uid from staff where uid=$1',[admin])).rowCount,0);
    await assert.rejects(() => db.query(`insert into courier_merchants(courier_uid,merchant_id)
      values ($1,$2)`,[admin,shop]), {code:'42501'});
    assert.equal((await db.query('select uid from staff where uid=$1',[admin])).rowCount,0);
  });
});

it('detaching platform coverage hides unassigned orders despite a stale platform token', async () => {
  await as(rider,{role:'courier',scope:'platform'},async () => {
    const rows = await db.query('select id from orders where id=$1',[platformOrder]);
    assert.equal(rows.rowCount,0);
    const changed = await db.query(`update orders set status='outForDelivery',courier_uid=$1
      where id=$2 returning id`,[rider,platformOrder]);
    assert.equal(changed.rowCount,0);
  });
});

it('a detached courier is no longer readable through its legacy staff merchant', async () => {
  const legacy = '00000000-0000-0000-0000-000000000083';
  await db.query('insert into auth.users(id) values ($1)',[legacy]);
  await db.query(`insert into staff(uid,scope,role,merchant_id)
    values ($1,'merchant','courier',$2)`,[legacy,shop]);
  await db.query(`insert into courier_merchants(courier_uid,merchant_id,is_active)
    values ($1,$2,false) on conflict (courier_uid,merchant_id) where merchant_id is not null
    do update set is_active=false`,[legacy,shop]);
  await as(owner,{role:'owner',scope:'merchant',merchant_id:shop},async () => {
    assert.equal((await db.query('select uid from staff where uid=$1',[legacy])).rowCount,0);
  });
});

it('an application decision cannot bypass its audit RPC with a direct update', async () => {
  const id = (await db.query(`insert into staff_applications(kind,name,phone)
    values ('courier','Applicant','01099999991') returning id`)).rows[0].id;
  await as(admin,{admin:true,role:'admin',scope:'platform'},async () => {
    await assert.rejects(() => db.query(`update staff_applications set status='approved',
      reviewed_by=$1 where id=$2`,[owner,id]),{code:'42501'});
  });
});

it('an applicant cannot choose its queue timestamp', async () => {
  await db.exec('set role anon');
  try {
    await assert.rejects(() => db.query(`insert into staff_applications(kind,name,phone,created_at)
      values ('courier','Applicant','01099999992','2099-01-01')`),{code:'42501'});
  } finally { await db.exec('reset role'); }
});

it('adding shop addresses preserves the owners preparation-time edit', async () => {
  await as(owner,{role:'owner',scope:'merchant',merchant_id:shop},async () => {
    const rows = await db.query('update merchants set prep_minutes=45 where id=$1 returning prep_minutes',[shop]);
    assert.equal(rows.rows[0].prep_minutes,45);
  });
});
