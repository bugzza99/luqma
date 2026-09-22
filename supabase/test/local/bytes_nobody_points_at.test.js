import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * M-03: a sweep that starts from the bytes, and a cap on uploading.
 *
 * The two halves cover each other. A cap on rows does not stop anybody filling the bucket
 * with objects; a sweep does not stop anybody filling the table.
 */
describe('bytes nobody points at, and a hand that cannot flood', () => {
  const ADMIN = '00000000-0000-0000-0000-00000000a001';

  let db;

  const rows = async (sql, params) => (await db.query(sql, params)).rows;

  const url = (name) =>
    `https://p.supabase.co/storage/v1/object/public/media/${name}`;

  /** An object in the bucket, aged by hand so the sweep's week can be tested. */
  const object = (name, ageDays) => db.query(
    `insert into storage.objects (bucket_id, name, owner, created_at)
     values ('media', $1, $2, now() - make_interval(days => $3))`,
    [name, ADMIN, ageDays]);

  const names = async () => (await rows(
    `select name from storage.objects where bucket_id = 'media' order by name`))
    .map((r) => r.name);

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${ADMIN}') on conflict (id) do nothing;
      insert into storage.buckets (id, name, public)
        values ('media', 'media', true) on conflict (id) do nothing;`);
  });

  after(async () => { await db?.close(); });

  beforeEach(async () => {
    await db.exec(`
      delete from storage.objects where bucket_id = 'media';
      delete from media;`);
  });

  describe('the sweep starts from the bytes as well as the rows', () => {
    it('removes an object no row has ever named', async () => {
      // The gap this closes. `upload()` writes the object and then the row; a process that
      // dies between the two leaves bytes the product cannot see, the admin cannot see,
      // and — until now — the sweep could not see either, because it began from the rows.
      await object('menuItem/orphan.jpg', 30);

      await db.query('select sweep_orphan_media()');

      assert.deepEqual(await names(), []);
    });

    it('leaves an object a row still points at', async () => {
      await object('menuItem/kept.jpg', 30);
      await db.query(
        `insert into media (kind, url, status, uploaded_by)
         values ('menuItem', $1, 'approved', $2)`, [url('menuItem/kept.jpg'), ADMIN]);

      await db.query('select sweep_orphan_media()');

      assert.deepEqual(await names(), ['menuItem/kept.jpg']);
    });

    it('leaves an upload that is still in flight', async () => {
      // An object written seconds ago whose row has not landed yet is not an orphan, it is
      // somebody in the middle of adding a picture. Sweeping it deletes their photograph
      // out from under them.
      await object('menuItem/still-uploading.jpg', 0);

      await db.query('select sweep_orphan_media()');

      assert.deepEqual(await names(), ['menuItem/still-uploading.jpg']);
    });

    it('still does the first pass it always did', async () => {
      // A pending row older than a week that nothing points at, and its object with it.
      await object('menuItem/rejected.jpg', 30);
      await db.query(
        `insert into media (kind, url, status, uploaded_by, created_at)
         values ('menuItem', $1, 'pending', $2, now() - interval '30 days')`,
        [url('menuItem/rejected.jpg'), ADMIN]);

      const removed = (await rows('select sweep_orphan_media() as n'))[0].n;

      assert.equal(removed, 1, 'the row was counted');
      assert.deepEqual(await names(), [], 'and its bytes went too');
    });

    it('leaves a bucket it was not asked about alone', async () => {
      // `staff-docs` has its own sweep, its own grace period and its own rules. This one
      // deleting from it would be a national ID removed by the wrong clock.
      await db.exec(`
        insert into storage.buckets (id, name, public)
          values ('staff-docs', 'staff-docs', false) on conflict (id) do nothing;`);
      await db.query(
        `insert into storage.objects (bucket_id, name, created_at)
         values ('staff-docs', 'someone/id-front.jpg', now() - interval '60 days')`);

      await db.query('select sweep_orphan_media()');

      assert.equal(
        (await rows(
          `select count(*)::int n from storage.objects where bucket_id = 'staff-docs'`))[0].n,
        1);
    });
  });

  it('still declares the door hosted storage needs, whoever rewrites it next', async () => {
    // Not observable at runtime here: PGlite has no `protect_delete`, so a sweep that
    // cannot delete a single object on production passes every test in this file. The
    // line was added by a *later* migration than the one that first wrote the function,
    // so anybody building a `create or replace` from the original copy drops it — which
    // is precisely what the first draft of this migration did.
    const def = (await rows(
      `select pg_get_functiondef(p.oid) as src
         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'sweep_orphan_media'`))[0].src;

    assert.match(def, /storage\.allow_delete_query/,
      'without this the sweep silently stops deleting anything on hosted Supabase');
  });

  describe('the cap on uploading', () => {
    const upload = (n) => db.query(
      `insert into media (kind, url, status, uploaded_by)
       select 'menuItem', $1 || g || '.jpg', 'pending', $2
         from generate_series(1, $3) g`,
      [url('menuItem/bulk-'), ADMIN, n]);

    it('is far above what the owner really does', async () => {
      // Six hundred photographs over a fortnight is the real workload. A cap that caught
      // that would be a cap somebody turns off.
      assert.equal((await rows('select media_uploads_per_hour() as n'))[0].n, 200);
    });

    it('lets an ordinary run of uploads through', async () => {
      await upload(50);

      assert.equal((await rows('select count(*)::int n from media'))[0].n, 50);
    });

    it('stops a script', async () => {
      await upload(200);

      await assert.rejects(
        () => db.query(
          `insert into media (kind, url, status, uploaded_by)
           values ('menuItem', $1, 'pending', $2)`, [url('menuItem/201.jpg'), ADMIN]),
        /too many uploads/);
    });

    it('counts the hour, not for ever', async () => {
      await upload(200);
      await db.query(
        "update media set created_at = now() - interval '2 hours'");

      await db.query(
        `insert into media (kind, url, status, uploaded_by)
         values ('menuItem', $1, 'pending', $2)`, [url('menuItem/later.jpg'), ADMIN]);

      assert.equal((await rows('select count(*)::int n from media'))[0].n, 201);
    });

    it('does not stand in the way of trusted server work', async () => {
      // A seed, a migration and the nightly pass are not a person with a camera. The same
      // door every other guard here is passed through.
      await upload(200);

      await db.query(`do $$ begin
        perform set_config('app.server_mode','on',true);
        insert into media (kind, url, status, uploaded_by)
        values ('menuItem', 'https://x/object/public/media/seeded.jpg', 'approved',
                '${ADMIN}');
      end $$;`);

      assert.equal((await rows('select count(*)::int n from media'))[0].n, 201);
    });

    it('is a rate limit rather than a refusal, and says so', async () => {
      // The difference matters to whoever reads the message: the picture is fine, the
      // pace is not.
      await upload(200);

      await assert.rejects(
        () => db.query(
          `insert into media (kind, url, status, uploaded_by)
           values ('menuItem', $1, 'pending', $2)`, [url('menuItem/again.jpg'), ADMIN]),
        (error) => {
          assert.equal(error.code, '53400', 'a resource limit, not a permission refusal');
          return true;
        });
    });
  });
});
