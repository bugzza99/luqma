import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * Removing a courier's papers is an act with a name on it.
 *
 * An admin could delete the objects straight from the client and nothing recorded that it
 * happened — which breaks the rule H-09 settled: a sensitive admin mutation goes through
 * a function that writes the change and its evidence together, and the direct path is
 * taken away, because a write that skips the function skips the audit with it.
 *
 * Identity documents are the strongest case for that rule in the product. They are the
 * only thing a courier hands over that they cannot get back, and the one thing whose
 * disappearance they would notice only when asked for them again.
 */
describe('a document is removed on the record', () => {
  const ADMIN = '00000000-0000-0000-0000-0000000000d1';
  const MOD = '00000000-0000-0000-0000-0000000000d2';
  const COURIER = '00000000-0000-0000-0000-0000000000d3';
  const COURIER_PHONE = '01000000123';

  let db;

  const as = (uid, claims) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select '${uid}'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const admin = () => as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
  const moderator = () => as(MOD, { admin: true, role: 'moderator', scope: 'platform' });

  const rows = async (sql, params) => (await db.query(sql, params)).rows;

  const paths = () => [
    `${COURIER}/id-front.jpg`, `${COURIER}/id-back.jpg`, `${COURIER}/selfie.jpg`,
  ];

  const objects = async () => (await rows(
    `select name from storage.objects where bucket_id = 'staff-docs' order by name`))
    .map((r) => r.name);

  const docs = async () => (await rows(
    'select id_front_path, id_back_path, selfie_path from staff_documents where uid = $1',
    [COURIER]))[0];

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${ADMIN}'), ('${MOD}');
      -- A real account address, because an application must be filed for the number the
      -- account is on (application_phone_is_the_applicant_s). A fixture that skipped it
      -- would be testing a row production cannot produce.
      insert into auth.users (id, email)
        values ('${COURIER}', '${COURIER_PHONE}@phone.luqma.app');
      grant usage on schema auth to anon, authenticated;
      insert into staff (uid, scope, role, is_active) values
        ('${ADMIN}', 'platform', 'admin', true),
        ('${MOD}', 'platform', 'moderator', true);
      insert into storage.buckets (id, name, public)
        values ('staff-docs', 'staff-docs', false) on conflict (id) do nothing;`);
  });

  after(async () => { await db?.close(); });

  beforeEach(async () => {
    await admin();
    await db.exec(`
      delete from audit_log where action = 'staffDocuments.deleted';
      delete from staff_documents;
      delete from storage.objects where bucket_id = 'staff-docs';`);
    const [front, back, selfie] = paths();
    await db.query(
      `insert into storage.objects (bucket_id, name, owner)
       values ('staff-docs', $1, $4), ('staff-docs', $2, $4), ('staff-docs', $3, $4)`,
      [front, back, selfie, COURIER]);
    await db.query(
      `insert into staff_documents (uid, id_front_path, id_back_path, selfie_path)
       values ($1, $2, $3, $4)`, [COURIER, front, back, selfie]);
  });

  describe('an admin, with a reason', () => {
    it('takes the bytes and the row together', async () => {
      // Either half alone is its own defect: bytes with no row leave a national ID in a
      // bucket nothing points at, and a row with no bytes draws a broken image on
      // «شوف البطاقة», which reads as a bug rather than a decision somebody took.
      await admin();

      await db.query(
        `select admin_delete_staff_documents($1, 'الصور مش بتاعته')`, [COURIER]);

      assert.equal(await docs(), undefined, 'no row');
      assert.deepEqual(await objects(), [], 'and no bytes');
    });

    it('puts the applicant back to needing papers, through the real guard', async () => {
      // The table holds three `not null` paths written together, and the approval trigger
      // asks whether the row exists at all. There is no state in the product for «two
      // papers on file», so an unacceptable photograph means the papers are handed in
      // again — and this asserts that through `courier_application_needs_papers` rather
      // than by re-reading the column this function just wrote.
      await admin();
      const app = (await rows(
        `insert into staff_applications (kind, name, phone, applicant_uid, status)
         values ('courier', 'مندوب', '${COURIER_PHONE}', $1, 'pending') returning id`,
        [COURIER]))[0].id;

      await db.query(`select admin_delete_staff_documents($1, 'الصور مرفوضة')`, [COURIER]);

      await assert.rejects(
        () => db.query(
          `update staff_applications set status = 'approved' where id = $1`, [app]),
        /approved on their papers, and there are none/);
    });

    it('writes who, what went, and why', async () => {
      await admin();

      await db.query(
        `select admin_delete_staff_documents($1, 'الصورة مش واضحة')`, [COURIER]);

      const log = (await rows(
        `select actor, detail from audit_log where action = 'staffDocuments.deleted'`))[0];
      assert.equal(log.actor, ADMIN, 'the actor is who really called');
      assert.equal(log.detail.uid, COURIER);
      assert.equal(log.detail.reason, 'الصورة مش واضحة');
      assert.deepEqual(log.detail.paths, paths(), 'which objects went');
    });

    it('refuses without a reason, and an empty one is not a reason', async () => {
      // The audit row exists to answer «why are this courier's papers gone». A log that
      // may be blank does not answer it.
      await admin();

      for (const reason of [null, '', '   ']) {
        await assert.rejects(
          () => db.query('select admin_delete_staff_documents($1, $2)', [COURIER, reason]),
          /say why/);
      }

      assert.equal((await objects()).length, 3, 'and nothing went while it refused');
    });

    it('refuses papers that are already gone, rather than saying it removed them', async () => {
      await admin();
      await db.query(`select admin_delete_staff_documents($1, 'سبب')`, [COURIER]);

      await assert.rejects(
        () => db.query(`select admin_delete_staff_documents($1, 'سبب')`, [COURIER]),
        /no papers on file/);
    });

    it('puts the storage door back when it is done', async () => {
      // Transaction-local, inside somebody else's transaction. Leaving it standing lets
      // whatever the caller does next delete objects unasked — the same lesson as
      // `app.server_mode` in `apply_order_settlement`.
      await admin();

      await db.query(`select admin_delete_staff_documents($1, 'سبب')`, [COURIER]);

      assert.equal(
        (await rows(`select current_setting('storage.allow_delete_query', true) as s`))[0].s,
        '');
    });
  });

  describe('and nobody else', () => {
    it('refuses a moderator', async () => {
      // Deletion is the half the owner excepted, and papers are the sharpest case of it.
      await moderator();

      await assert.rejects(
        () => db.query(`select admin_delete_staff_documents($1, 'سبب')`, [COURIER]),
        /only an admin/);

      assert.equal((await objects()).length, 3);
    });

    it('refuses the courier themselves', async () => {
      // The rule the table was built on: somebody who could delete their own papers could
      // delete them the morning a dispute started.
      await as(COURIER, {});

      await assert.rejects(
        () => db.query(`select admin_delete_staff_documents($1, 'سبب')`, [COURIER]),
        /only an admin/);
    });
  });
});
