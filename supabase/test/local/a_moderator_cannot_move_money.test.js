import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { freshDatabase } from './harness.mjs';

/**
 * A moderator is an admin except money — and three doors to the money were still open.
 *
 * `20261024000000` narrowed fourteen named functions, but `admin_set_revenue_model` was
 * not among them. And the column guards on `merchants` and `orders` both step aside for
 * `is_admin()`, which answers for a moderator since that same migration — so a moderator
 * could PATCH a wallet, a commission balance or a plan's expiry straight through
 * PostgREST, rewrite an order's pricing, and then mark it delivered, which settles on the
 * rewritten figures. None of those writes reached `audit_log`.
 *
 * Everything below runs after `set local role authenticated`, because PGlite's owner is a
 * superuser and the merchant guard asks which database role is writing: a server function
 * runs as its owner, a phone runs as `authenticated`.
 */
describe('a moderator cannot move money', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000a8';
  const MOD = '00000000-0000-0000-0000-0000000000b8';

  let db, zone, shop;

  const as = (uid, claims) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  // The claims the hook actually mints for each.
  const admin = () => as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
  const moderator = () => as(MOD, { admin: true, role: 'moderator', scope: 'platform' });

  const rows = async (sql, params) => (await db.query(sql, params)).rows;

  /** One statement as the role a phone speaks as, rolled back or not as the test needs. */
  async function asPhone(fn) {
    await db.exec('begin; set local role authenticated;');
    try {
      return await fn();
    } finally {
      await db.exec('rollback');
    }
  }

  /** By SQLSTATE: 42501 is the only answer that means the server considered it and said no. */
  const refused = (message) => (error) => {
    assert.equal(error.code, '42501',
      `expected a permission refusal, got ${error.code}: ${error.message}`);
    if (message) assert.match(error.message, new RegExp(message));
    return true;
  };

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${ADMIN}'), ('${MOD}');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;
      insert into plans (id, name, price_monthly) values ('basic', 'أساسية', 25000)
        on conflict (id) do nothing;
      insert into staff (uid, scope, role, is_active) values
        ('${ADMIN}', 'platform', 'admin', true),
        ('${MOD}', 'platform', 'moderator', true);`);
    zone = (await rows(
      `insert into zones (city_id, name, default_delivery_fee)
       values ('edku', 'الزغبي', 2000) returning id`))[0].id;
  });

  after(async () => { await db?.close(); });

  beforeEach(async () => {
    await admin();
    await db.exec(`delete from merchants where not exists (
                     select 1 from orders o where o.merchant_id = merchants.id);`);
    shop = (await rows(
      `insert into merchants (city_id, type, name, zone_id, phone, status,
                              revenue_model, revenue_value, wallet_balance, commission_owed)
       values ('edku', 'restaurant', 'مطعم الفلوس', $1, '0100', 'approved',
               'commission', 500, 3000, 12000) returning id`,
      [zone]))[0].id;
  });

  describe('the revenue model', () => {
    it('refuses a moderator setting prepaid at one piastre', async () => {
      await moderator();

      await assert.rejects(
        () => asPhone(() => db.query(
          `select admin_set_revenue_model($1::uuid, 'prepaid', 1)`, [shop])),
        refused('only an admin'));
    });

    it('still lets an admin set it, and it lands', async () => {
      await admin();

      const after = await asPhone(async () => {
        await db.query(`select admin_set_revenue_model($1::uuid, 'prepaid', 700)`, [shop]);
        return (await rows(
          'select revenue_model, revenue_value from merchants where id = $1', [shop]))[0];
      });

      assert.deepEqual(after, { revenue_model: 'prepaid', revenue_value: 700 });
    });
  });

  describe("a shop's money columns", () => {
    // The six columns a phone must never write directly. Each of them moves only inside a
    // function that declares server mode: settlement, a hold, a top-up, a collection, a
    // subscription term, the nightly plan pass.
    const writes = [
      ['wallet_balance', '999999'],
      // Not zero: the shop holds nothing, and a write of the value already there changes
      // nothing and is rightly let through.
      ['wallet_held', '500'],
      ['commission_owed', '0'],
      ['commission_custom', 'true'],
      ['plan_id', "'basic'"],
      ['plan_expires_at', "now() + interval '10 years'"],
    ];

    for (const [column, value] of writes) {
      it(`refuses a moderator writing ${column}`, async () => {
        await moderator();

        await assert.rejects(
          () => asPhone(() => db.query(
            `update merchants set ${column} = ${value} where id = $1`, [shop])),
          refused('money'));
      });
    }

    // H-09: a sensitive admin mutation goes through an audited function. A platform admin
    // writing the wallet straight through PostgREST is a balance with no evidence behind
    // it, which is exactly what `top_up_wallet` and its receipt exist to rule out.
    it('refuses a platform admin writing them directly too', async () => {
      await admin();

      await assert.rejects(
        () => asPhone(() => db.query(
          'update merchants set commission_owed = 0 where id = $1', [shop])),
        refused('money'));
    });

    it('leaves the row as it was', async () => {
      // Committed when it succeeds, unlike `asPhone`: the question is what is left behind.
      await moderator();
      await db.exec('begin; set local role authenticated;');
      try {
        await db.query('update merchants set wallet_balance = 999999 where id = $1', [shop]);
        await db.exec('commit');
      } catch {
        await db.exec('rollback');
      }

      await admin();
      assert.equal(
        (await rows('select wallet_balance from merchants where id = $1', [shop]))[0]
          .wallet_balance,
        3000);
    });

    // A whole-row save re-sends the money columns unchanged. That is how the merchant's
    // own screens and AdminApp save a shop, and it must keep working.
    it('lets a moderator save a shop that re-sends the same figures', async () => {
      await moderator();

      const name = await asPhone(async () => (await rows(
        `update merchants set name = 'اسم جديد', wallet_balance = 3000,
                commission_owed = 12000, plan_id = null
          where id = $1 returning name`, [shop]))[0].name);

      assert.equal(name, 'اسم جديد');
    });

    it('still lets the real paths move them', async () => {
      await admin();

      const owed = await asPhone(async () => {
        await db.query('select top_up_wallet($1::uuid, 500::integer)', [shop]);
        await db.query('select record_commission_payment($1::uuid, 2000::integer)', [shop]);
        return (await rows(
          'select wallet_balance, commission_owed from merchants where id = $1', [shop]))[0];
      });

      assert.deepEqual(owed, { wallet_balance: 3500, commission_owed: 10000 });
    });
  });

  describe('an order', () => {
    let order;

    beforeEach(async () => {
      await admin();
      order = (await rows(
        `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                             merchant_id, merchant_name, zone_id, type, items, pricing,
                             status, delivery_by)
         values ('edku', null, 'عميل', '01000000000', $1, 'مطعم الفلوس', $2, 'instant',
                 '[]', '{"subtotal":10000,"total":12000}', 'needsAttention', 'merchant')
         returning id`, [shop, zone]))[0].id;
    });

    it('refuses a moderator rewriting the pricing', async () => {
      await moderator();

      await assert.rejects(
        () => asPhone(() => db.query(
          `update orders set pricing = '{"subtotal":1,"total":1}' where id = $1`, [order])),
        refused('pricing'));
    });

    it('refuses a moderator assigning a courier', async () => {
      await moderator();

      await assert.rejects(
        () => asPhone(() => db.query(
          'update orders set courier_uid = $2 where id = $1', [order, MOD])),
        refused());
    });

    it('refuses a moderator marking it delivered', async () => {
      await moderator();

      await assert.rejects(
        () => asPhone(() => db.query(
          `update orders set status = 'delivered' where id = $1`, [order])),
        refused('moderator'));
    });

    it('refuses a moderator reopening a delivered order', async () => {
      // A reopen reverses a settlement: the shop's balance moves back.
      await db.exec(`do $$ begin
        perform set_config('app.server_mode','on',true);
        update orders set status = 'delivered', delivered_at = now() where id = '${order}';
      end $$;`);
      await moderator();

      await assert.rejects(
        () => asPhone(() => db.query(
          `update orders set status = 'outForDelivery' where id = $1`, [order])),
        refused('moderator'));
    });

    // The work the role exists for: an order nobody answered, cancelled so the customer
    // is not left waiting. It is the one order write AdminApp's «اليوم» sheet makes.
    for (const from of ['placed', 'needsAttention']) {
      it(`lets a moderator cancel an unanswered order (${from})`, async () => {
        await db.exec(`do $$ begin
          perform set_config('app.server_mode','on',true);
          update orders set status = '${from}' where id = '${order}';
        end $$;`);
        await moderator();

        const status = await asPhone(async () => (await rows(
          `update orders set status = 'cancelled',
                  cancel_reason = 'المحل مردّش على الأوردر', cancelled_by = 'customer'
            where id = $1 returning status`, [order]))[0].status);

        assert.equal(status, 'cancelled');
      });
    }

    it('refuses a moderator cancelling an order a kitchen has started', async () => {
      await db.exec(`do $$ begin
        perform set_config('app.server_mode','on',true);
        update orders set status = 'preparing' where id = '${order}';
      end $$;`);
      await moderator();

      await assert.rejects(
        () => asPhone(() => db.query(
          `update orders set status = 'cancelled' where id = $1`, [order])),
        refused('moderator'));
    });

    it('leaves a platform admin as it was', async () => {
      await admin();

      const status = await asPhone(async () => (await rows(
        `update orders set status = 'accepted' where id = $1 returning status`,
        [order]))[0].status);

      assert.equal(status, 'accepted');
    });
  });

  // Astra's review of the first pass: both order guards run on UPDATE, and `admin_orders`
  // is `for all` — so the door the update guards shut was standing open one verb over.
  describe('an order written from nothing', () => {
    const CUSTOMER = '00000000-0000-0000-0000-0000000000c8';

    before(async () => {
      // Hosted Supabase grants every sequence in `public` to `authenticated` by default
      // privilege; PGlite has no such default. Without this the insert below is refused by
      // `order_number_seq` before any guard is asked, and a test would pass for the wrong
      // reason — on the real stack the sequence is no obstacle at all.
      await db.exec(`grant usage, select on all sequences in schema public to authenticated;
                     insert into auth.users (id) values ('${CUSTOMER}')
                     on conflict (id) do nothing;
                     update users set name = 'عميل', phone = '01000000000'
                      where id = '${CUSTOMER}';`);
    });

    // A prepaid order whose frozen terms say a fortune an order: the hold trigger reads
    // `revenue` off the row and raises `wallet_held` by it, which is a shop that stops
    // taking orders the moment it lands.
    const insertOrder = (status = 'placed',
        revenue = '{"model":"prepaid","value":999999}') => db.query(
      `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                           merchant_id, merchant_name, zone_id, type, items, pricing,
                           revenue, status, delivery_by)
       values ('edku', null, 'عميل', '01000000000', $1, 'مطعم الفلوس', $2, 'instant',
               '[]', '{"subtotal":1,"total":1}', $4::jsonb,
               $3, 'merchant') returning id`, [shop, zone, status, revenue]);

    it('refuses a moderator inserting an order, and nothing is held', async () => {
      await moderator();

      const held = await asPhone(async () => {
        await db.exec('savepoint attempt');
        await assert.rejects(() => insertOrder(), refused('place_order'));
        await db.exec('rollback to savepoint attempt');
        return (await rows('select wallet_held from merchants where id = $1', [shop]))[0]
          .wallet_held;
      });

      assert.equal(held, 0);
    });

    // Straight to `delivered` is the other half: settlement is an UPDATE trigger, so an
    // order born finished never settles and leaves the money records disagreeing.
    it('refuses a moderator inserting one already delivered', async () => {
      await moderator();

      await assert.rejects(
        () => asPhone(() => insertOrder('delivered')),
        refused('place_order'));
    });

    it('leaves a platform admin as it was', async () => {
      await admin();

      const n = await asPhone(async () =>
        (await insertOrder('placed', '{"model":"commission","value":500}')).rows.length);

      assert.equal(n, 1);
    });

    // A7 reaches here too, and rightly: the hold refuses what the free credit cannot
    // cover whoever writes the order, so not even a platform admin can hold a fortune
    // against a shop's wallet and stop it trading.
    it('and not even a platform admin holds more than the wallet has', async () => {
      await admin();

      await assert.rejects(
        () => asPhone(() => insertOrder()),
        /not accepting orders/);
    });

    // The one real way in, through the role a phone speaks as.
    it('still lets a customer place an order through place_order', async () => {
      await admin();
      const kitchen = (await rows(
        `insert into merchants (city_id, type, name, zone_id, phone, status, delivers_self,
                                opening_hours)
         values ('edku', 'restaurant', 'مطبخ', $1, '0100', 'approved', true,
           (select jsonb_agg(jsonb_build_object('weekday', d, 'openMinute', 0,
                                                'closeMinute', 1439))
              from generate_series(1, 7) d)) returning id`, [zone]))[0].id;
      const category = (await rows(
        `insert into menu_categories (merchant_id, name) values ($1, 'أطباق') returning id`,
        [kitchen]))[0].id;
      const item = (await rows(
        `insert into menu_items (merchant_id, category_id, name, price)
         values ($1, $2, 'سمك', 10000) returning id`, [kitchen, category]))[0].id;
      const address = (await rows(
        `insert into addresses (user_id, zone_id, label) values ($1, $2, 'البيت')
         returning id`, [CUSTOMER, zone]))[0].id;

      await as(CUSTOMER, {});
      const status = await asPhone(async () => (await rows(
        'select place_order($1::jsonb) as o', [JSON.stringify({
          merchantId: kitchen, addressId: address, type: 'instant',
          items: [{ itemId: item, name: 'سمك', unitPrice: 10000, quantity: 1 }],
        })]))[0].o.status);

      assert.equal(status, 'placed');
    });
  });

  // `admin_merchants` is `for all`, and the update guard never sees a row's first values.
  // AdminApp really does insert shops, so the verb stays; what a moderator may put in the
  // money columns of a new one is what every new shop starts with, and nothing else.
  describe('a shop written from nothing', () => {
    // The exact row AdminApp sends, not a hand-written imitation of it: the file is what
    // `SupabaseMerchantRepository.rowFor` produces for the create form, and
    // `apps/admin_app/test/a_new_shop_payload_test.dart` fails the day the two disagree.
    const payload = () => ({
      ...JSON.parse(readFileSync(new URL('../fixtures/admin_app_creates_a_shop.json',
                                         import.meta.url), 'utf8')),
      zone_id: zone,
    });

    // As PostgREST does it: only the columns sent, so every other one takes its default.
    const insertShop = (row) => {
      const columns = Object.keys(row).join(', ');
      return db.query(
        `insert into merchants (${columns})
         select ${columns} from jsonb_populate_record(null::merchants, $1::jsonb)
         returning id, revenue_model, revenue_value, commission_custom`,
        [JSON.stringify(row)]);
    };

    beforeEach(async () => {
      await admin();
      await db.query('delete from merchants where id = $1', [payload().id]);
    });

    it('lets a moderator add a shop exactly as AdminApp does', async () => {
      await moderator();

      const made = await asPhone(async () => (await insertShop(payload())).rows[0]);

      // The one rate, set by `merchants_start_on_the_rate`, not by whoever typed the row.
      assert.equal(made.revenue_model, 'commission');
      assert.equal(made.commission_custom, false);
    });

    for (const [column, value] of [
      ['wallet_balance', 999999],
      ['wallet_held', 999999],
      ['commission_owed', -999999],
      ['commission_custom', true],
      ['plan_id', 'basic'],
      ['plan_expires_at', '2036-01-01T00:00:00Z'],
      ['revenue_model', 'prepaid'],
      // A commission written out is kept by the rate trigger — it only fills in a zero.
      ['revenue_value', 1],
    ]) {
      it(`refuses a moderator adding a shop with ${column} already set`, async () => {
        await moderator();

        const row = { ...payload(), [column]: value };
        if (column === 'revenue_value') row.revenue_model = 'commission';

        await assert.rejects(
          () => asPhone(() => insertShop(row)),
          refused('new shop'));
      });
    }

    it('leaves a platform admin as it was', async () => {
      await admin();

      const made = await asPhone(async () => (await insertShop(
        { ...payload(), revenue_model: 'prepaid', revenue_value: 700 })).rows[0]);

      assert.equal(made.revenue_value, 700);
    });
  });

  // A subscription term is a receipt, and `plan_expires_at` is extended from the latest
  // one — so a fabricated term becomes a real expiry on the next genuine payment.
  describe('a subscription term', () => {
    const fabricate = () => db.query(
      `insert into subscriptions (merchant_id, plan_id, amount, started_at, expires_at)
       values ($1, 'basic', 0, now(), now() + interval '10 years')`, [shop]);

    for (const [who, become] of [['a moderator', moderator], ['an admin', admin]]) {
      it(`refuses ${who} writing one directly`, async () => {
        await become();

        await assert.rejects(() => asPhone(fabricate), refused('subscriptions'));
      });

      it(`refuses ${who} moving one's expiry directly`, async () => {
        // A real term to move, written by the owner of the database rather than through
        // a role that has just lost the verb.
        await db.query(
          `insert into subscriptions (merchant_id, plan_id, amount, started_at, expires_at)
           values ($1, 'basic', 25000, now(), now() + interval '30 days')`, [shop]);
        await become();

        await assert.rejects(
          () => asPhone(() => db.query(
            `update subscriptions set expires_at = now() + interval '10 years'
              where merchant_id = $1`, [shop])),
          refused('subscriptions'));
      });
    }

    it('still lets an admin record a payment', async () => {
      await admin();

      const term = await asPhone(async () => (await rows(
        `select record_subscription_payment($1::uuid, 'basic', 25000, 1) as t`,
        [shop]))[0].t);

      assert.equal(term.plan_id, 'basic');
    });
  });

  // The one order write a moderator is meant to keep, and it never worked: the «اليوم»
  // sheet cancelled through the customer's own path, which only matches `placed` and signs
  // the cancellation as the customer — so every order in a queue of `needsAttention`
  // orders matched nothing.
  describe('cancelling an order nobody answered', () => {
    const CUSTOMER = '00000000-0000-0000-0000-0000000000c9';
    let order;

    before(async () => {
      await db.exec(`insert into auth.users (id) values ('${CUSTOMER}')
                     on conflict (id) do nothing;`);
    });

    beforeEach(async () => {
      await admin();
      order = (await rows(
        `insert into orders (city_id, customer_uid, customer_name, customer_phone,
                             merchant_id, merchant_name, zone_id, type, items, pricing,
                             status, delivery_by)
         values ('edku', null, 'عميل', '01000000000', $1, 'مطعم الفلوس', $2, 'instant',
                 '[]', '{"subtotal":10000,"total":12000}', 'needsAttention', 'merchant')
         returning id`, [shop, zone]))[0].id;
    });

    const cancel = (id = order, reason = 'المحل مردّش على الأوردر') => rows(
      'select admin_cancel_order($1::uuid, $2)', [id, reason]);

    for (const [who, become, uid] of [['a moderator', moderator, MOD],
                                      ['an admin', admin, ADMIN]]) {
      it(`lets ${who} cancel it, signed as staff and written down`, async () => {
        await become();

        const [row, audit] = await asPhone(async () => {
          await cancel();
          return [
            (await rows('select status, cancelled_by, cancel_reason from orders where id = $1',
                        [order]))[0],
            await rows(`select actor, detail from audit_log
                         where action = 'order.cancelled_by_staff'`),
          ];
        });

        assert.deepEqual(row, { status: 'cancelled', cancelled_by: 'admin',
                                cancel_reason: 'المحل مردّش على الأوردر' });
        assert.equal(audit.length, 1);
        assert.equal(audit[0].actor, uid);
        assert.equal(audit[0].detail.orderId, order);
        assert.equal(audit[0].detail.from, 'needsAttention');
      });
    }

    it('cancels one still placed as well', async () => {
      await db.exec(`do $$ begin
        perform set_config('app.server_mode','on',true);
        update orders set status = 'placed' where id = '${order}';
      end $$;`);
      await moderator();

      const status = await asPhone(async () => {
        await cancel();
        return (await rows('select status from orders where id = $1', [order]))[0].status;
      });

      assert.equal(status, 'cancelled');
    });

    // A kitchen that has started is food somebody cooked; the order moved while the sheet
    // was open, and that is a conflict to be said in words, not a permission refusal.
    it('refuses once the kitchen has started', async () => {
      await db.exec(`do $$ begin
        perform set_config('app.server_mode','on',true);
        update orders set status = 'preparing' where id = '${order}';
      end $$;`);
      await moderator();

      await assert.rejects(() => asPhone(() => cancel()), (error) => {
        assert.equal(error.code, '23505', error.message);
        return true;
      });
    });

    it('says an order that is not there is not there', async () => {
      await moderator();

      await assert.rejects(
        () => asPhone(() => cancel('00000000-0000-0000-0000-00000000dead')),
        (error) => { assert.equal(error.code, 'P0002', error.message); return true; });
    });

    it('needs a reason', async () => {
      await moderator();

      await assert.rejects(() => asPhone(() => cancel(order, '  ')), (error) => {
        assert.equal(error.code, '23514', error.message);
        return true;
      });
    });

    it('refuses a customer', async () => {
      await as(CUSTOMER, {});

      await assert.rejects(() => asPhone(() => cancel()), refused('staff'));
    });
  });
});
