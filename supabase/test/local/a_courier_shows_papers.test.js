import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * A courier shows their papers, and the papers belong to the person.
 *
 * The earlier attempt hung the three paths off `staff_applications`, so an approved
 * courier's national ID photographs were kept alive by their application row and swept
 * within a day of it going. These tests are written against the rewrite, and the thing
 * most of them are really asking is the same question twice: is there exactly one
 * answer to "how long do these papers live", and does every path reach it?
 */
describe('a courier shows papers', () => {
  const ADMIN = '00000000-0000-0000-0000-00000000d001';
  const RIDER = '00000000-0000-0000-0000-00000000d002';
  const OTHER = '00000000-0000-0000-0000-00000000d003';

  const PHONES = {
    [RIDER]: '01277070001',
    [OTHER]: '01277070002',
  };

  let db;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select ${uid ? `'${uid}'::uuid` : 'null::uuid'} $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  // The three objects a person uploads, under their own uid, the way the policy requires.
  const paths = (uid) => [`${uid}/id-front.jpg`, `${uid}/id-back.jpg`, `${uid}/selfie.jpg`];

  const upload = async (uid) => {
    for (const name of paths(uid)) {
      await db.query(
        `insert into storage.objects (bucket_id, name, owner) values ('staff-docs', $1, $2)
         on conflict do nothing`,
        [name, uid],
      );
    }
  };

  const hand_in = async (uid) => {
    const [front, back, selfie] = paths(uid);
    return db.query('select * from set_my_staff_documents($1, $2, $3)', [front, back, selfie]);
  };

  const papers = async (uid) =>
    (await db.query('select * from staff_documents where uid = $1', [uid])).rows[0];

  // `guard_staff_self_edit` lets a staff account pause itself and change nothing else, so
  // hiring, dismissing and reinstating are an admin's statements here as they are in the
  // product. Doing them as the rider would test a path nobody can take.
  const asAdmin = async (fn) => {
    await as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
    try { return await fn(); } finally { await as(RIDER); }
  };

  // `guard_staff_activation` sends every activation change through the server boundary, so
  // that GoTrue is told and refresh credentials actually die. `set-staff-active` is that
  // boundary in the product; this is the same declaration it makes.
  const setActive = (uid, value) => db.query(`do $$ begin
    perform set_config('app.server_mode','on',true);
    update public.staff set is_active = ${value} where uid = '${uid}';
  end $$;`);

  const apply = async (uid, kind = 'courier') =>
    (await db.query(
      `insert into staff_applications (kind, name, phone, applicant_uid)
       values ($1, 'سعيد المندوب', $2, $3) returning id`,
      [kind, PHONES[uid], uid],
    )).rows[0].id;

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id, email) values
        ('${ADMIN}', 'owner@luqma.app'),
        ('${RIDER}', '${PHONES[RIDER]}@phone.luqma.app'),
        ('${OTHER}', '${PHONES[OTHER]}@phone.luqma.app');
      grant usage on schema auth to anon, authenticated;
      insert into cities (id, name) values ('edku', 'إدكو') on conflict (id) do nothing;
      insert into staff (uid, scope, role, is_active)
        values ('${ADMIN}', 'platform', 'admin', true);
    `);
  });

  after(async () => { await db?.close(); });

  beforeEach(async () => {
    await db.exec(`
      delete from staff_documents;
      delete from staff_applications;
      delete from staff where uid <> '${ADMIN}';
      delete from storage.objects where bucket_id = 'staff-docs';
      update config set value = '30'::jsonb where key = 'staff_docs_grace_days';
    `);
    await as(RIDER);
  });

  describe('handing them in', () => {
    it('takes three photographs and keys them on the person', async () => {
      await upload(RIDER);
      const { rows } = await hand_in(RIDER);

      assert.equal(rows[0].uid, RIDER);
      assert.equal(rows[0].id_front_path, `${RIDER}/id-front.jpg`);
      assert.equal(rows[0].selfie_path, `${RIDER}/selfie.jpg`);
    });

    it('refuses a set with a photograph missing', async () => {
      await upload(RIDER);
      const [front, back] = paths(RIDER);
      await assert.rejects(
        () => db.query('select set_my_staff_documents($1, $2, $3)', [front, back, '  ']),
        /all three documents are required/,
      );
    });

    it('refuses a path that belongs to somebody else', async () => {
      await upload(RIDER);
      await upload(OTHER);
      const [front, back] = paths(RIDER);
      await assert.rejects(
        () => db.query('select set_my_staff_documents($1, $2, $3)',
          [front, back, `${OTHER}/selfie.jpg`]),
        /not yours/,
      );
    });

    it('refuses a path nothing was ever uploaded to', async () => {
      await upload(RIDER);
      const [front, back] = paths(RIDER);
      await assert.rejects(
        () => db.query('select set_my_staff_documents($1, $2, $3)',
          [front, back, `${RIDER}/imaginary.jpg`]),
        /was not uploaded/,
      );
    });

    it('replaces a bad photograph rather than making a second row', async () => {
      await upload(RIDER);
      await hand_in(RIDER);
      await db.query(
        `insert into storage.objects (bucket_id, name, owner) values ('staff-docs', $1, $2)`,
        [`${RIDER}/selfie-2.jpg`, RIDER],
      );
      const [front, back] = paths(RIDER);
      await db.query('select set_my_staff_documents($1, $2, $3)',
        [front, back, `${RIDER}/selfie-2.jpg`]);

      const { rows } = await db.query('select * from staff_documents where uid = $1', [RIDER]);
      assert.equal(rows.length, 1);
      assert.equal(rows[0].selfie_path, `${RIDER}/selfie-2.jpg`);
    });
  });

  describe('how long they live', () => {
    it('counts down when papers are handed in and nothing is applied for', async () => {
      // Not an edge case: this is what replaces the earlier attempt's orphan sweep. An
      // upload that never became an application cleans itself up by the ordinary rule.
      await upload(RIDER);
      await hand_in(RIDER);

      assert.notEqual((await papers(RIDER)).purge_after, null);
    });

    it('stops counting while an application is waiting to be heard', async () => {
      await upload(RIDER);
      await hand_in(RIDER);
      await apply(RIDER);

      assert.equal((await papers(RIDER)).purge_after, null);
    });

    it('stops counting once the person is working', async () => {
      await upload(RIDER);
      await hand_in(RIDER);
      await apply(RIDER);
      await db.query(
        `insert into staff (uid, scope, role, is_active) values ($1, 'platform', 'courier', true)`,
        [RIDER],
      );

      assert.equal((await papers(RIDER)).purge_after, null);
    });

    it('starts counting when the application is turned down', async () => {
      await upload(RIDER);
      await hand_in(RIDER);
      const id = await apply(RIDER);
      assert.equal((await papers(RIDER)).purge_after, null);

      await as(ADMIN, { admin: true, role: 'admin', scope: 'platform' });
      await db.query('select review_staff_application($1, $2)', [id, 'rejected']);

      assert.notEqual((await papers(RIDER)).purge_after, null);
    });

    it('starts counting when a working courier is dismissed', async () => {
      await upload(RIDER);
      await hand_in(RIDER);
      // Approved, not merely applied for. A dismissed courier whose application is still
      // pending is somebody still waiting to hear, and the rule keeps their papers — which
      // is what the first draft of this test got wrong, not the code.
      const id = await apply(RIDER);
      await db.query(`update staff_applications set status = 'approved' where id = $1`, [id]);
      await db.query(
        `insert into staff (uid, scope, role, is_active) values ($1, 'platform', 'courier', true)`,
        [RIDER],
      );
      assert.equal((await papers(RIDER)).purge_after, null);

      await setActive(RIDER, false);

      assert.notEqual((await papers(RIDER)).purge_after, null);
    });

    it('stops counting again when they are taken back', async () => {
      await upload(RIDER);
      await hand_in(RIDER);
      await db.query(
        `insert into staff (uid, scope, role, is_active) values ($1, 'platform', 'courier', false)`,
        [RIDER],
      );
      assert.notEqual((await papers(RIDER)).purge_after, null);

      await setActive(RIDER, true);

      assert.equal((await papers(RIDER)).purge_after, null);
    });

    it('does not restart the clock on papers already counting down', async () => {
      // A dismissed courier whose row is touched again next week must not be given
      // another thirty days by the touch.
      await upload(RIDER);
      await hand_in(RIDER);
      await db.query(
        `insert into staff (uid, scope, role, is_active) values ($1, 'platform', 'courier', false)`,
        [RIDER],
      );
      const first = (await papers(RIDER)).purge_after;

      await asAdmin(() =>
        db.query(`update staff set name = 'سعيد' where uid = $1`, [RIDER]));

      assert.deepEqual((await papers(RIDER)).purge_after, first);
    });

    it('honours the grace period the owner set', async () => {
      await db.query(`update config set value = '1'::jsonb where key = 'staff_docs_grace_days'`);
      await upload(RIDER);
      await hand_in(RIDER);

      const { rows } = await db.query(
        `select purge_after <= now() + interval '1 day' + interval '1 minute' as soon
           from staff_documents where uid = $1`, [RIDER]);
      assert.equal(rows[0].soon, true);
    });

    it('refuses a grace period outside its range, whoever writes it', async () => {
      for (const bad of ['0', '400', '"soon"', '2.5']) {
        await assert.rejects(
          () => db.query(
            `update config set value = $1::jsonb where key = 'staff_docs_grace_days'`, [bad]),
          /staff_docs_grace_days/,
          `expected ${bad} to be refused`,
        );
      }
    });

    it('goes with the person when the account goes', async () => {
      await upload(RIDER);
      await hand_in(RIDER);
      await db.query('delete from auth.users where id = $1', [RIDER]);

      assert.equal(await papers(RIDER), undefined);
      // Restored for the tests that follow; beforeEach cannot put an auth user back.
      await db.query(`insert into auth.users (id, email) values ($1, $2)`,
        [RIDER, `${PHONES[RIDER]}@phone.luqma.app`]);
    });
  });

  describe('no papers, no approval', () => {
    it('refuses to approve a courier who has shown nothing', async () => {
      const id = await apply(RIDER);
      await assert.rejects(
        () => db.query(
          `update staff_applications set status = 'approved' where id = $1`, [id]),
        /approved on their papers/,
      );
    });

    it('approves a courier who has', async () => {
      await upload(RIDER);
      await hand_in(RIDER);
      const id = await apply(RIDER);

      await db.query(`update staff_applications set status = 'approved' where id = $1`, [id]);
      const { rows } = await db.query('select status from staff_applications where id = $1', [id]);
      assert.equal(rows[0].status, 'approved');
    });

    it('asks nothing of a restaurant', async () => {
      const id = await apply(OTHER, 'restaurant');
      await db.query(`update staff_applications set status = 'approved' where id = $1`, [id]);
      const { rows } = await db.query('select status from staff_applications where id = $1', [id]);
      assert.equal(rows[0].status, 'approved');
    });

    it('does not fail a later touch once the papers have been purged', async () => {
      // Retention outlives the decision by design, so re-stamping an approved row years
      // later must not trip a rule about papers that were correctly deleted.
      await upload(RIDER);
      await hand_in(RIDER);
      const id = await apply(RIDER);
      await db.query(`update staff_applications set status = 'approved' where id = $1`, [id]);
      await db.query('delete from staff_documents where uid = $1', [RIDER]);

      await db.query(
        `update staff_applications set review_note = 'rang them again' where id = $1`, [id]);
    });
  });

  describe('the sweep', () => {
    it('deletes the objects and the row once the grace period is up', async () => {
      await upload(RIDER);
      await hand_in(RIDER);
      await db.query(
        `update staff_documents set purge_after = now() - interval '1 minute' where uid = $1`,
        [RIDER]);

      const removed = (await db.query('select sweep_staff_documents() as n')).rows[0].n;

      assert.equal(removed, 1);
      assert.equal(await papers(RIDER), undefined);
      const { rows } = await db.query(
        `select count(*)::int as n from storage.objects where bucket_id = 'staff-docs'`);
      assert.equal(rows[0].n, 0);
    });

    it('leaves papers that are still counting down', async () => {
      await upload(RIDER);
      await hand_in(RIDER);

      const removed = (await db.query('select sweep_staff_documents() as n')).rows[0].n;

      assert.equal(removed, 0);
      assert.notEqual(await papers(RIDER), undefined);
    });

    it('corrects a stale clock rather than acting on it', async () => {
      // The triggers make retention prompt; the sweep makes it true. A row left counting
      // down by a path nobody thought of is put right, not deleted.
      await upload(RIDER);
      await hand_in(RIDER);
      await db.query(
        `insert into staff (uid, scope, role, is_active) values ($1, 'platform', 'courier', true)`,
        [RIDER]);
      await db.query(
        `update staff_documents set purge_after = now() - interval '1 minute' where uid = $1`,
        [RIDER]);

      const removed = (await db.query('select sweep_staff_documents() as n')).rows[0].n;

      assert.equal(removed, 0);
      assert.equal((await papers(RIDER)).purge_after, null);
    });

    it('leaves another bucket alone', async () => {
      await upload(RIDER);
      await hand_in(RIDER);
      await db.query(
        `insert into storage.objects (bucket_id, name) values ('media', $1)`,
        [`${RIDER}/id-front.jpg`]);
      await db.query(
        `update staff_documents set purge_after = now() - interval '1 minute' where uid = $1`,
        [RIDER]);

      await db.query('select sweep_staff_documents()');

      const { rows } = await db.query(
        `select count(*)::int as n from storage.objects where bucket_id = 'media'`);
      assert.equal(rows[0].n, 1);
    });
  });
});
