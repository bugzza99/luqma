import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A menu starts with four shelves.
 *
 * The first real shop opened a menu screen that said there were no categories and offered
 * no way to make one. A restaurant starts with the four parts the owner asked for now; a
 * home kitchen, which has no standing menu, starts with none.
 */
describe('a menu starts with four shelves', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000d1';
  const OWNER = '00000000-0000-0000-0000-0000000000d2';
  let db, zoneId;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select ${uid ? `'${uid}'::uuid` : 'null::uuid'} $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const role = async (r, fn) => {
    await db.exec(`set role ${r}`);
    try { return await fn(); } finally { await db.exec('reset role'); }
  };

  const shop = async (type, name) => (await db.query(
    `insert into merchants (city_id, type, name, zone_id, phone, status)
     values ('edku', $1, $2, $3, '01000000000', 'approved') returning id`,
    [type, name, zoneId])).rows[0].id;

  const shelves = async (merchantId) => (await db.query(
    'select name from menu_categories where merchant_id = $1 order by sort_order',
    [merchantId])).rows.map((r) => r.name);

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${ADMIN}'), ('${OWNER}');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;
      insert into staff (uid, scope, role, is_active) values ('${ADMIN}', 'platform', 'admin', true);
    `);
    zoneId = (await db.query(
      `insert into zones (city_id, name, default_delivery_fee)
       values ('edku', 'الزغبي', 1000) returning id`)).rows[0].id;
  });

  after(async () => { await db?.close(); });

  it('a restaurant starts with the four parts, in order', async () => {
    const id = await shop('restaurant', 'ابو حاتم');
    assert.deepEqual(await shelves(id),
      ['الوجبات الأساسية', 'العروض', 'الإضافات', 'المشروبات']);
  });

  it('a home kitchen starts with none', async () => {
    const id = await shop('homeKitchen', 'مطبخ ام محمد');
    assert.deepEqual(await shelves(id), []);
  });

  it('the shelves are ordinary categories: the owner can rename one', async () => {
    const id = await shop('restaurant', 'مطعم البحر');
    await db.query(
      `insert into staff (uid, scope, role, merchant_id, is_active)
       values ($1, 'merchant', 'owner', $2, true)`, [OWNER, id]);
    await as(OWNER, { role: 'owner', scope: 'merchant', merchant_id: id });

    const r = await role('authenticated', () => db.query(
      `update menu_categories set name = 'السندوتشات'
        where merchant_id = $1 and sort_order = 0`, [id]));
    assert.equal(r.rowCount, 1);
    assert.equal((await shelves(id))[0], 'السندوتشات');
  });

  it('seeding never adds to a menu that already has a category', async () => {
    const id = await shop('restaurant', 'كشري');
    await db.query('delete from menu_categories where merchant_id = $1', [id]);
    await db.query(
      `insert into menu_categories (merchant_id, name, sort_order) values ($1, 'كشري', 0)`, [id]);

    await db.query('select public.seed_default_menu_categories($1)', [id]);
    assert.deepEqual(await shelves(id), ['كشري']);
  });

  it('a phone cannot call the seeding function', async () => {
    const id = await shop('restaurant', 'فول');
    await as(OWNER, {});
    await assert.rejects(
      () => role('authenticated', () => db.query(
        'select public.seed_default_menu_categories($1)', [id])),
      /permission denied/i);
  });

  describe('a shop asking for an advert', () => {
    const request = (merchantId, channel, status = 'requested') => db.query(
      `insert into promotions (city_id, merchant_id, channel, status, title,
                               start_at, end_at, requested_by)
       values ('edku', $1, $2, $3, 'عرض', now(), now() + interval '7 days', $4)
       returning id`, [merchantId, channel, status, OWNER]);

    // Through the shop owner's own token, the way the partner app writes it: the push
    // table is closed to a phone, so this passes only while the trigger is a definer.
    const requestAsOwner = async (merchantId, channel) => {
      const owner = (await db.query(
        `insert into auth.users (id) values (gen_random_uuid()) returning id`)).rows[0].id;
      await db.query(
        `insert into staff (uid, scope, role, merchant_id, is_active)
         values ($1, 'merchant', 'owner', $2, true)`, [owner, merchantId]);
      await as(owner, { role: 'owner', scope: 'merchant', merchant_id: merchantId });
      await role('authenticated', () => db.query(
        `insert into promotions (city_id, merchant_id, channel, title,
                                 start_at, end_at, requested_by)
         values ('edku', $1, $2, 'عرض', now(), now() + interval '7 days', $3)`,
        [merchantId, channel, owner]));
      return (await db.query(
        `select id from promotions where merchant_id = $1 order by created_at desc limit 1`,
        [merchantId])).rows[0].id;
    };

    it('tells every active admin, with the promotion to open', async () => {
      const id = await shop('restaurant', 'شاورما');
      const promo = await requestAsOwner(id, 'push');

      const told = await db.query(
        `select uid, title, body, channel, data from push_outbox
          where data->>'promotionId' = $1`, [promo]);
      const admins = (await db.query(
        `select uid from staff where scope = 'platform' and role = 'admin' and is_active`)).rows;
      assert.equal(told.rows.length, admins.length);
      assert.ok(told.rows.some((r) => r.uid === ADMIN));
      assert.equal(told.rows[0].data.kind, 'promotionRequest');
      assert.equal(told.rows[0].channel, 'orders');
      assert.match(told.rows[0].body, /شاورما/);
      assert.match(told.rows[0].body, /إشعار للعملاء/);
    });

    it('an admin’s own approved placement tells nobody', async () => {
      const id = await shop('restaurant', 'بيتزا');
      const promo = (await request(id, 'homeBanner', 'approved')).rows[0].id;
      const told = await db.query(
        `select 1 from push_outbox where data->>'promotionId' = $1`, [promo]);
      assert.equal(told.rows.length, 0);
    });

    // A request is a row a shop may write as often as it likes; the admins' phones are not.
    it('a shop asking again within ten minutes does not wake anybody twice', async () => {
      const id = await shop('restaurant', 'حواوشي');
      await requestAsOwner(id, 'homeBanner');
      await requestAsOwner(id, 'push');
      await requestAsOwner(id, 'boost');

      const told = await db.query(
        `select count(distinct data->>'promotionId')::int as n from push_outbox
          where data->>'kind' = 'promotionRequest'
            and data->>'promotionId' in (select id::text from promotions where merchant_id = $1)`,
        [id]);
      assert.equal(told.rows[0].n, 1);
    });

    it('a backdated request does not reopen the window', async () => {
      const id = await shop('restaurant', 'سمك');
      await requestAsOwner(id, 'push');
      // The shop writes its own created_at on a path the quota trigger does not stamp.
      await db.query(
        `insert into promotions (city_id, merchant_id, channel, title, start_at, end_at,
                                 requested_by, created_at)
         values ('edku', $1, 'boost', 'عرض', now(), now() + interval '7 days', $2,
                 now() - interval '1 day')`, [id, OWNER]);
      const told = await db.query(
        `select count(distinct data->>'promotionId')::int as n from push_outbox
          where data->>'kind' = 'promotionRequest'
            and data->>'promotionId' in (select id::text from promotions where merchant_id = $1)`,
        [id]);
      assert.equal(told.rows[0].n, 1);
    });

    it('answering a request does not reopen the window either', async () => {
      const id = await shop('restaurant', 'فطاطري');
      const first = await requestAsOwner(id, 'push');
      await db.query(`update promotions set status = 'rejected', rejection_reason = 'مش مناسب' where id = $1`, [first]);
      await requestAsOwner(id, 'homeBanner');
      const told = await db.query(
        `select count(distinct data->>'promotionId')::int as n from push_outbox
          where data->>'kind' = 'promotionRequest'
            and data->>'promotionId' in (select id::text from promotions where merchant_id = $1)`,
        [id]);
      assert.equal(told.rows[0].n, 1);
    });

    it('the clock is read by nobody but the trigger', async () => {
      await as(OWNER, {});
      await assert.rejects(
        () => role('authenticated', () => db.query('select * from promotion_request_pings')),
        /permission denied/i);
    });
  });
});
