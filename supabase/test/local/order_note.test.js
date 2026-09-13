import { describe, it } from 'node:test';
import { strictEqual, rejects } from 'node:assert';
import { freshDatabase } from './harness.mjs';

// A checkout instruction belongs to the whole order, separately from the dish notes.
// Read the saved row as well as the RPC response: returning an echoed draft would make
// the phone look correct while leaving the kitchen with precisely the original bug.
describe('the checkout instruction reaches the kitchen', () => {
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


  const place = async (note) => {
    const addressId = (await db.query(
      `insert into addresses (user_id,zone_id,street)
       values ($1,$2,'شارع البحر') returning id`, [CUSTOMER, zone])).rows[0].id;
    const placed = (await db.query('select place_order($1::jsonb) as o',
      [JSON.stringify({ merchantId: merchant, addressId, type: 'instant', note,
        items: [{ itemId: item, quantity: 1, note: 'الصوص لوحده' }],
      })])).rows[0].o;
    const saved = (await db.query('select * from orders where id=$1', [placed.id])).rows[0];
    return { placed, saved };
  };

  it('stores the order instruction without replacing the dish instruction', async () => {
    await setup();
    const { placed, saved } = await place('من غير شطة');
    strictEqual(saved.note, 'من غير شطة');
    strictEqual(placed.note, 'من غير شطة');
    strictEqual(saved.items[0].note, 'الصوص لوحده');
  });

  it('keeps an omitted instruction null', async () => {
    await setup();
    const { placed, saved } = await place(undefined);
    strictEqual(saved.note, null);
    strictEqual(placed.note, null);
  });

  it('trims the outside whitespace and preserves the words and line break', async () => {
    await setup();
    const { saved } = await place(' \t\nمن غير شطة\nالجرس مكسور\r\n ');
    strictEqual(saved.note, 'من غير شطة\nالجرس مكسور');
  });

  it('stores empty and whitespace-only instructions as null', async () => {
    await setup();
    for (const note of ['', ' \t\r\n ']) {
      strictEqual((await place(note)).saved.note, null);
    }
  });

  it('accepts 500 characters and refuses 501 without placing an order', async () => {
    await setup();
    const limit = 'ش'.repeat(500);
    strictEqual((await place(limit)).saved.note, limit);
    await rejects(() => place(`${limit}ة`), /the note is too long|orders_note_length/);
    strictEqual((await db.query('select count(*)::int as n from orders')).rows[0].n, 1);
  });

  it('enforces the cap on direct writes too', async () => {
    await setup();
    const { saved } = await place('من غير شطة');
    // A trusted writer bypasses the column guard, never the storage constraint.
    await db.query("select set_config('app.server_mode','on',false)");
    await rejects(() => db.query('update orders set note=$1 where id=$2',
      ['ش'.repeat(501), saved.id]), /orders_note_length/);
  });

  for (const actor of ['customer', 'merchant']) {
    it(`does not let the ${actor} rewrite the instruction after placement`, async () => {
      await setup();
      const { saved } = await place('من غير شطة');
      if (actor === 'merchant') {
        const owner = '00000000-0000-0000-0000-0000000000b1';
        await db.query('insert into auth.users (id) values ($1)', [owner]);
        await db.query(`insert into staff (uid,scope,role,merchant_id)
          values ($1,'merchant','owner',$2)`, [owner, merchant]);
        await db.query(`create or replace function auth.uid() returns uuid
          language sql stable as $fn$ select '${owner}'::uuid $fn$`);
        await db.query(`create or replace function auth.jwt() returns jsonb
          language sql stable as $fn$ select '${JSON.stringify({app_metadata: {
            scope: 'merchant', role: 'owner', merchant_id: merchant,
          }})}'::jsonb $fn$`);
        strictEqual((await db.query('select is_merchant_owner($1) as yes', [merchant])).rows[0].yes, true);
      }
      // A legitimate change first proves that this is a usable identity and the
      // refusal below is about the note, not a fixture nobody recognises.
      await db.query('update orders set status=status where id=$1', [saved.id]);
      await rejects(() => db.query("update orders set note='بدون ملح' where id=$1", [saved.id]),
        /column not yours to change on an order: note/);
      strictEqual((await db.query('select note from orders where id=$1', [saved.id])).rows[0].note,
        'من غير شطة');
    });
  }
});
