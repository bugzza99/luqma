import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A9. An account cannot be deleted while an order of theirs is on its way, and a
 * deleted account leaves no free text behind.
 *
 * Both deletion paths scrubbed every order of the departing customer at once, whatever
 * its status. An order out for delivery lost its street and its phone number while the
 * courier was carrying it — food in the street with nowhere to go. The owner decided
 * (2026-09-23) that deletion waits until the order is finished.
 *
 * And the scrub left `orders.note` and each line's `note`: free text the customer typed,
 * which is exactly where somebody writes «ورا بيت الحاج فلان، رن على 0100…».
 */
describe('an account with an order on its way', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000a1';
  const OWNER = '00000000-0000-0000-0000-0000000000b2';
  let db, zoneId, merchantId;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const asRole = async (fn) => {
    await db.exec('set role authenticated');
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  let n = 0;
  const customer = async () => {
    n += 1;
    const id = `00000000-0000-0000-0000-0000000001${String(n).padStart(2, '0')}`;
    await db.query('insert into auth.users (id) values ($1)', [id]);
    return id;
  };

  const order = async (customerUid, status, { note = null, items } = {}) => (await db.query(`
    insert into orders (
      city_id, customer_uid, customer_name, customer_phone,
      merchant_id, merchant_name, zone_id, address, delivery_by,
      type, items, pricing, revenue, status, note
    ) values (
      'a9', $1, 'عميل', '01012345678',
      $2, 'مطعم', $3, $4::jsonb, 'merchant',
      'instant', $5::jsonb, '{"subtotal":9000,"total":10000}'::jsonb,
      '{"model":"commission","value":0}'::jsonb, $6, $7
    ) returning id`, [
      customerUid, merchantId, zoneId,
      JSON.stringify({ zoneId, street: 'شارع الجلاء' }),
      JSON.stringify(items ?? [{ itemId: 'i1', name: 'كشري', unitPrice: 9000, quantity: 1 }]),
      status, note,
    ])).rows[0].id;

  const read = async (id) => (await db.query('select * from orders where id = $1', [id])).rows[0];

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${ADMIN}'), ('${OWNER}');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('a9', 'إدكو');
      insert into staff (uid, scope, role, is_active) values ('${ADMIN}', 'platform', 'admin', true);`);
    zoneId = (await db.query(`insert into zones (city_id, name, default_delivery_fee)
      values ('a9', 'المعدية', 1000) returning id`)).rows[0].id;
    merchantId = (await db.query(`insert into merchants
      (city_id, type, name, zone_id, phone, status, owner_uid)
      values ('a9', 'restaurant', 'مطعم', $1, '0100', 'approved', $2) returning id`,
      [zoneId, OWNER])).rows[0].id;
  });

  after(async () => { await db?.close(); });

  for (const status of ['placed', 'accepted', 'preparing', 'outForDelivery', 'needsAttention']) {
    it(`a customer with an order ${status} cannot delete themselves yet`, async () => {
      const me = await customer();
      const live = await order(me, status);

      await as(me);
      await assert.rejects(
        asRole(() => db.query('select public.delete_my_account()')),
        /an order is still on its way/);

      const kept = await read(live);
      assert.equal(kept.customer_uid, me);
      assert.equal(kept.address.street, 'شارع الجلاء', 'the courier still has the street');
    });
  }

  it('once the order is finished, deletion goes ahead', async () => {
    const me = await customer();
    await order(me, 'delivered');
    await order(me, 'cancelled');

    await as(me);
    await asRole(() => db.query('select public.delete_my_account()'));

    const left = (await db.query('select count(*)::int n from auth.users where id = $1', [me])).rows[0].n;
    assert.equal(left, 0);
  });

  it('an admin cannot delete a customer whose order is on its way either', async () => {
    const them = await customer();
    await order(them, 'outForDelivery');

    await as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
    await assert.rejects(
      asRole(() => db.query('select public.admin_delete_account($1)', [them])),
      /an order is still on its way/);
  });

  it('what the customer typed goes with them: the order note and every line note',
    async () => {
      const me = await customer();
      const id = await order(me, 'delivered', {
        note: 'ورا بيت الحاج فلان، رن على 01099998888',
        items: [
          { itemId: 'i1', name: 'كشري', unitPrice: 9000, quantity: 1, note: 'من غير بصل — للأستاذ محمد' },
          { itemId: 'i2', name: 'رز', unitPrice: 1000, quantity: 2 },
        ],
      });

      await as(me);
      await asRole(() => db.query('select public.delete_my_account()'));

      const scrubbed = await read(id);
      assert.equal(scrubbed.note, null);
      assert.deepEqual(scrubbed.items, [
        { itemId: 'i1', name: 'كشري', unitPrice: 9000, quantity: 1 },
        { itemId: 'i2', name: 'رز', unitPrice: 1000, quantity: 2 },
      ], 'the food and the money stay, the words go');
    });

  it('an admin deletion scrubs the notes too', async () => {
    const them = await customer();
    const id = await order(them, 'delivered', { note: 'رن على 01099998888' });

    await as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
    await asRole(() => db.query('select public.admin_delete_account($1)', [them]));

    assert.equal((await read(id)).note, null);
  });
});
