import { describe, it } from 'node:test';
import { strictEqual, rejects } from 'node:assert';
import { freshDatabase } from './harness.mjs';

/**
 * Prepaid credit, between the order and the door.
 *
 * Placement refused a merchant whose balance was under one order's fee, and the fee was
 * taken on delivery. Nothing held the money in between, so the same five pounds funded as
 * many orders as arrived before the first one landed — sequentially, with no race.
 */
describe('prepaid credit is held, not hoped for', () => {
  const CUSTOMER = '00000000-0000-0000-0000-0000000000c1';
  const FEE = 500;
  let db, merchant, item, zone, addressId;

  const setup = async (balance) => {
    db = await freshDatabase();
    await db.query('insert into auth.users (id) values ($1)', [CUSTOMER]);
    await db.query(`create or replace function auth.uid() returns uuid
      language sql stable as $fn$ select '${CUSTOMER}'::uuid $fn$`);
    await db.query(`update users set name='عميل', phone='01000000000' where id=$1`, [CUSTOMER]);

    await db.query(`insert into cities (id,name) values ('p','مدينة')`);
    zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee) values ('p','منطقة',0) returning id`
    )).rows[0].id;
    merchant = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status,delivers_self,
                              revenue_model,revenue_value,wallet_balance,opening_hours)
       values ('p','restaurant','مطعم',$1,'0100','approved',true,'prepaid',$2,$3,
         (select jsonb_agg(jsonb_build_object('weekday',d,'openMinute',0,'closeMinute',1439))
            from generate_series(1,7) d)) returning id`,
      [zone, FEE, balance])).rows[0].id;
    const cat = (await db.query(
      `insert into menu_categories (merchant_id,name) values ($1,'أطباق') returning id`,
      [merchant])).rows[0].id;
    item = (await db.query(
      `insert into menu_items (merchant_id,category_id,name,price) values ($1,$2,'سمك',10000)
       returning id`, [merchant, cat])).rows[0].id;
    addressId = (await db.query(
      `insert into addresses (user_id,zone_id,label) values ($1,$2,'البيت') returning id`,
      [CUSTOMER, zone])).rows[0].id;
  };

  const place = () =>
    db.query('select place_order($1::jsonb) as o', [JSON.stringify({
      merchantId: merchant, addressId, type: 'instant',
      items: [{ itemId: item, name: 'سمك', unitPrice: 10000, quantity: 1 }],
    })]).then((r) => r.rows[0].o.id);

  const wallet = async () => (await db.query(
    'select wallet_balance, wallet_held from merchants where id = $1', [merchant])).rows[0];

  // `app.server_mode` is transaction-local and each `query` is its own transaction, so
  // declaring it in a separate call leaves the guard armed for the update that follows.
  // A `do` block puts both in one statement, and one statement means no parameters —
  // hence the interpolated literals, which are ids this file created.
  const step = (id, status) => db.query(`do $$ begin
      perform set_config('app.server_mode','on',true);
      update public.orders set status='${status}' where id='${id}';
    end $$;`);
  const deliver = async (id) => {
    for (const s of ['accepted', 'preparing', 'outForDelivery', 'delivered']) {
      await step(id, s);
    }
  };

  // The whole finding, in one test: one order's worth of credit, two orders.
  it('one order of credit funds exactly one order', async () => {
    await setup(FEE);
    await place();
    await rejects(() => place(), /not accepting orders/);
  });

  // A7. place_order read the balance without a lock and the hold added to wallet_held
  // without re-checking it, so two customers pressing «اطلب» in the same instant both
  // passed the check against one order's worth of credit, and delivering both left the
  // wallet a fee below zero. Sequential placements cannot show the race; what can be
  // shown here is the rule that closes it — the hold itself refuses what the free credit
  // cannot cover, in the one statement that takes it, which a row lock serialises.
  it('the hold refuses what the free credit cannot cover, at the moment it is taken',
    async () => {
      await setup(FEE);
      await place();
      await rejects(
        () => db.query(`do $$ begin
            perform set_config('app.server_mode','on',true);
            insert into public.orders (
              city_id, customer_uid, customer_name, customer_phone, merchant_id,
              merchant_name, zone_id, address, delivery_by, type, items, pricing, revenue)
            values ('p', '${CUSTOMER}', 'عميل', '01000000000', '${merchant}', 'مطعم',
              '${zone}', '{}'::jsonb, 'merchant', 'instant', '[]'::jsonb,
              '{"total":10000}'::jsonb, '{"model":"prepaid","value":${FEE}}'::jsonb);
          end $$;`),
        /not accepting orders/);
      strictEqual((await wallet()).wallet_held, FEE, 'held once, not twice');
    });

  it('and the balance itself does not move until the food arrives', async () => {
    await setup(FEE);
    const id = await place();

    let w = await wallet();
    strictEqual(w.wallet_balance, FEE, 'nothing is taken at placement');
    strictEqual(w.wallet_held, FEE, 'but it is spoken for');

    await deliver(id);
    w = await wallet();
    strictEqual(w.wallet_balance, 0, 'taken on delivery, as it always was');
    strictEqual(w.wallet_held, 0, 'and released, so it is not counted twice');
  });

  // A hold that is never released is a merchant slowly locked out of their own credit.
  it('a cancelled order gives its hold back', async () => {
    await setup(FEE);
    const id = await place();
    strictEqual((await wallet()).wallet_held, FEE);

    await db.query(`do $$ begin
        perform set_config('app.server_mode','on',true);
        update public.orders set status='cancelled', cancel_reason='غيّر رأيه'
         where id='${id}';
      end $$;`);

    const w = await wallet();
    strictEqual(w.wallet_held, 0);
    strictEqual(w.wallet_balance, FEE, 'and nothing was taken for food nobody cooked');

    // Released means spendable: the next order goes through.
    await place();
  });

  it('two orders of credit fund two orders, and then stop', async () => {
    await setup(FEE * 2);
    await place();
    await place();
    strictEqual((await wallet()).wallet_held, FEE * 2);
    await rejects(() => place(), /not accepting orders/);
  });

  // The refusal belongs at placement. A `check (wallet_balance >= 0)` would instead strand
  // a courier at a door with the cash already in their pocket and no way to record it.
  it('delivering everything held never overdraws the wallet', async () => {
    await setup(FEE * 2);
    const a = await place();
    const b = await place();
    await deliver(a);
    await deliver(b);

    const w = await wallet();
    strictEqual(w.wallet_balance, 0);
    strictEqual(w.wallet_held, 0);
  });
  // An admin can reopen a delivered or cancelled order. The hold was released on the way
  // out and nothing took it again on the way back in, so delivering it a second time
  // released a hold that no longer existed — out of another live order's share, with
  // `greatest(…, 0)` hiding the drift. A reopened order holds its fee again.
  it('a reopened order holds its fee again, so another order keeps its own', async () => {
    await setup(FEE * 3);
    const a = await place();
    await place();
    strictEqual((await wallet()).wallet_held, FEE * 2);

    await deliver(a);
    strictEqual((await wallet()).wallet_held, FEE, 'A released, B still held');

    await step(a, 'outForDelivery');
    strictEqual((await wallet()).wallet_held, FEE * 2, 'A holds again while it is live');

    await step(a, 'delivered');
    strictEqual((await wallet()).wallet_held, FEE, 'B keeps its hold');
  });
});
