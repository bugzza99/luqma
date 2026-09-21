import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A moderator is an admin except money, deletion, and who anybody is.
 *
 * The role has existed since Phase 2 and the gate only ever asked for an admin, so
 * creating one produced an account that opened nothing and said nothing about it. The
 * owner's decision was to define it rather than remove it.
 *
 * Both directions are tested, and both matter: a moderator who cannot do the work is the
 * bug this closes, and a moderator who can empty the till or promote themselves is a
 * worse one than the bug.
 */
describe('a moderator is an admin except', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000a9';
  const MOD = '00000000-0000-0000-0000-0000000000b9';

  let db, zone, shop;

  const as = (uid, claims) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  // The claims the hook actually mints for each, so the tests run on the token the
  // product issues rather than one a fixture imagined.
  const admin = () => as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
  const moderator = () => as(MOD, { admin: true, role: 'moderator', scope: 'platform' });

  const rows = async (sql, params) => (await db.query(sql, params)).rows;

  /**
   * A refusal, by SQLSTATE rather than by words.
   *
   * Matching the message alone let a call that does not exist pass as a refusal: a
   * two-argument `admin_set_config` raises 42883 «function does not exist», and a regex
   * looking for "admin" matched the function's own name. 42501 is the only answer that
   * means the server considered the request and said no.
   */
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
      insert into staff (uid, scope, role, is_active) values
        ('${ADMIN}', 'platform', 'admin', true),
        ('${MOD}', 'platform', 'moderator', true);`);
    zone = (await rows(
      `insert into zones (city_id, name, default_delivery_fee)
       values ('edku', 'الزغبي', 2000) returning id`))[0].id;
  });

  after(async () => { await db?.close(); });

  beforeEach(async () => {
    // As the admin, because the guard this file is about refuses a moderator's delete —
    // including the teardown's.
    await admin();
    await db.exec(`delete from merchants;`);
    shop = (await rows(
      `insert into merchants (city_id, type, name, zone_id, phone, status)
       values ('edku', 'restaurant', 'مطعم السمك', $1, '0100', 'approved') returning id`,
      [zone]))[0].id;
  });

  describe('the hook mints a usable token', () => {
    it('gives a moderator the claim the gate reads', async () => {
      // The whole defect in one assertion: without this the account signs in and is sent
      // straight to «مالكش صلاحية», with no way to tell that from a typo in the password.
      const meta = (await rows(
        `select custom_access_token_hook(
           jsonb_build_object('user_id', $1::uuid,
                              'claims', jsonb_build_object('app_metadata','{}'::jsonb))
         ) -> 'claims' -> 'app_metadata' as m`, [MOD]))[0].m;

      assert.equal(meta.admin, true, 'the gate lets them in');
      assert.equal(meta.role, 'moderator', 'and the screens still know which they are');
    });

    it('still tells the two apart where it counts', async () => {
      await moderator();
      assert.equal((await rows('select is_admin() a'))[0].a, true);
      assert.equal((await rows('select is_platform_admin() a'))[0].a, false);

      await admin();
      assert.equal((await rows('select is_admin() a'))[0].a, true);
      assert.equal((await rows('select is_platform_admin() a'))[0].a, true);
    });

    it('reads the role from the row, not the claim', async () => {
      // An admin demoted an hour ago carries a token that still says admin. The till has
      // to close now rather than when the JWT expires — the same lesson as a dismissal
      // being a boundary change rather than a claim change.
      await as(MOD, { admin: true, role: 'admin', scope: 'platform' });

      assert.equal((await rows('select is_platform_admin() a'))[0].a, false);
    });
  });

  describe('the work a moderator is for', () => {
    it('can edit a shop', async () => {
      await moderator();

      await db.query(
        `update merchants set name = 'الاسم بعد التصحيح' where id = $1`, [shop]);

      assert.equal((await rows('select name from merchants where id = $1', [shop]))[0].name,
        'الاسم بعد التصحيح');
    });

    it('can review an image', async () => {
      const id = (await rows(
        `insert into media (kind, url, status, uploaded_by)
         values ('menuItem', 'x.jpg', 'pending', $1) returning id`, [ADMIN]))[0].id;
      await moderator();

      await db.query(`select admin_review_media($1, 'rejected', 'مش واضحة')`, [id]);

      const row = (await rows('select status, reviewed_by from media where id = $1', [id]))[0];
      assert.equal(row.status, 'rejected');
      assert.equal(row.reviewed_by, MOD, 'signed by whoever decided');
    });

    it('can read everything an admin reads', async () => {
      await moderator();
      assert.equal((await rows('select count(*)::int n from merchants'))[0].n, 1);
    });
  });

  describe('the money', () => {
    const coupon = (code) =>
      `select * from create_coupon('${code}', 'edku', 'percentage', 1000, 3000, 0,
         null::uuid, false, 0, 0, true, 'platform', null::timestamptz, null::timestamptz)`;

    it('refuses a moderator recording a collection', async () => {
      await moderator();

      await assert.rejects(
        () => db.query('select record_commission_payment($1::uuid, $2::integer)', [shop, 500]),
        /only an admin/);
    });

    it('refuses a moderator topping up a wallet', async () => {
      await moderator();

      await assert.rejects(
        () => db.query(
          'select top_up_wallet($1::uuid, $2::integer, $3::uuid)', [shop, 500, MOD]),
        /admin/i);
    });

    it('refuses a moderator writing a coupon', async () => {
      await moderator();

      await assert.rejects(() => db.query(coupon('MOD10')), /not allowed/i);
    });

    it('lets an admin do all three', async () => {
      // The other direction, and it is not a formality: a change that closed the till to
      // everybody would pass every test above.
      await admin();

      await db.query(
        'select top_up_wallet($1::uuid, $2::integer, $3::uuid)', [shop, 500, ADMIN]);
      await db.query(
        'select record_commission_payment($1::uuid, $2::integer)', [shop, 500]);
      await db.query(coupon('ADM10'));

      assert.equal(
        (await rows(`select count(*)::int n from coupons where code = 'ADM10'`))[0].n, 1);
    });
  });

  describe('deletion', () => {
    it('refuses a moderator deleting a shop', async () => {
      await moderator();

      await assert.rejects(
        () => db.query('delete from merchants where id = $1', [shop]),
        /may review and edit, but not delete/);
    });

    it('refuses a moderator deleting anywhere else either', async () => {
      // Twenty-five tables carry a `for all` policy, and widening `is_admin()` opened the
      // delete on all of them at once. One of these standing would be enough.
      await moderator();

      for (const [table, sql] of [
        ['zones', 'delete from zones where id = $1'],
        ['staff', `delete from staff where uid = '${ADMIN}'`],
      ]) {
        await assert.rejects(
          () => db.query(sql, sql.includes('$1') ? [zone] : []),
          /not delete/, `${table} should refuse a moderator`);
      }
    });

    it('lets an admin delete', async () => {
      await admin();

      await db.query('delete from merchants where id = $1', [shop]);

      assert.equal((await rows('select count(*)::int n from merchants'))[0].n, 0);
    });

    it('lets a trusted server function through', async () => {
      // Cascades and scheduled work declare server mode. A guard that stopped those would
      // break account deletion for everybody, not just a moderator.
      await moderator();

      await db.query(`do $$ begin
        perform set_config('app.server_mode','on',true);
        delete from merchants where id = '${shop}';
      end $$;`);

      assert.equal((await rows('select count(*)::int n from merchants'))[0].n, 0);
    });
  });

  describe('who mints an account', () => {
    // The second half. These four write `staff`, `courier_merchants` or `config`, so the
    // trigger above already refused them — from inside the write, after the function had
    // agreed to do it. A door that is going to be shut is shut at the door.
    it('refuses a moderator approving an application', async () => {
      await moderator();

      await assert.rejects(
        () => db.query(
          `select approve_staff_application($1::uuid, $2::uuid, null, null)`,
          ['00000000-0000-0000-0000-0000000000c1', zone]),
        refused('only an admin approves an application'));
    });

    it('refuses a moderator writing the control plane through the function', async () => {
      await moderator();

      await assert.rejects(
        () => db.query(
          `select admin_set_config('{"support_whatsapp":"0100"}'::jsonb)`),
        refused());
    });

    // Rejecting is moderation and mints nothing — it is the reason the role exists, and
    // taking it away would leave a moderator with a queue they can read and not work.
    it('but lets a moderator reject one', async () => {
      const app = (await rows(
        `insert into staff_applications (kind, name, phone, note, status)
         values ('courier', 'مندوب', '01000000009', 'أهلاً', 'pending') returning id`))[0].id;
      await moderator();

      await db.query(`select review_staff_application($1, 'rejected', 'مش دلوقتي')`, [app]);

      assert.equal(
        (await rows('select status from staff_applications where id = $1', [app]))[0].status,
        'rejected');
    });
  });

  describe('who anybody is', () => {
    it('refuses a moderator promoting themselves', async () => {
      // The one permission that hands out every other one. It is not money and it is not
      // deletion, so the owner's sentence did not name it — and plainly did not mean it.
      await moderator();

      await assert.rejects(
        () => db.query(`update staff set role = 'admin' where uid = $1`, [MOD]),
        /may not change who anybody is/);

      assert.equal((await rows('select role from staff where uid = $1', [MOD]))[0].role,
        'moderator');
    });

    it('refuses a moderator changing the control plane', async () => {
      // `default_commission_percent` is money by another name, and
      // `min_supported_version` walls every customer out with no back door.
      await moderator();

      await assert.rejects(
        () => db.query(
          `update config set value = '40'::jsonb where key = 'default_commission_percent'`),
        /may not change who anybody is/);
    });

    it('lets an admin do both', async () => {
      await admin();

      await db.query(
        `update config set value = '7'::jsonb where key = 'default_commission_percent'`);

      assert.equal(
        (await rows(
          `select value #>> '{}' v from config where key = 'default_commission_percent'`))[0].v,
        '7');
    });
  });
});
