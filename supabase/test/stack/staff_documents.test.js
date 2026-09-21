import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * A courier's papers, against the real boundary.
 *
 * PGlite answers what the schema permits; it cannot answer this. Its `storage.objects` is
 * a stub with no policies on it, and `auth.uid()` there is a function the harness writes.
 * The questions below are the ones the local suite is structurally unable to ask:
 *
 *   * can a person read somebody else's national ID?
 *   * can the person the clock is counting down for stop it?
 *
 * The second is the one that matters most. Retention is enforced by `purge_after`, and a
 * rule nobody can be stopped from editing is not a rule. `staff_documents` grants SELECT
 * and nothing else, on purpose — every write goes through a definer function — and this
 * file is what says so out loud.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

const uid = async () => (await q(
  "insert into auth.users (id, instance_id, aud, role) values (gen_random_uuid(), " +
  "'00000000-0000-0000-0000-000000000000','authenticated','authenticated') returning id",
)).rows[0].id;

/** Runs `fn` as one identity, in a transaction that is always rolled back. */
async function as(identity, fn) {
  await q('begin');
  try {
    await q("select set_config('role','authenticated',true)");
    await q("select set_config('request.jwt.claims',$1,true)", [JSON.stringify({
      sub: identity.uid, role: 'authenticated', app_metadata: identity.claims ?? {},
    })]);
    return await fn();
  } finally {
    await q('rollback');
  }
}

/** Whatever `fn` does, reported as the error message or null when it was allowed. */
async function refused(identity, fn) {
  return as(identity, async () => {
    try {
      await fn();
      return null;
    } catch (error) {
      return error.message;
    }
  });
}

describe('a courier\'s papers', () => {
  let admin, rider, other;
  const objects = [];

  const paths = (who) => [
    `${who}/id-front.jpg`, `${who}/id-back.jpg`, `${who}/selfie.jpg`,
  ];

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    admin = { uid: await uid(), claims: { admin: true, role: 'admin', scope: 'platform' } };
    rider = { uid: await uid(), claims: {} };
    other = { uid: await uid(), claims: {} };

    await q("insert into staff (uid,scope,role) values ($1,'platform','admin')", [admin.uid]);

    // Seeded with the service role so the tests can ask about reading rather than about
    // writing; the write path has its own tests below.
    for (const who of [rider.uid, other.uid]) {
      for (const name of paths(who)) {
        await q(`insert into storage.objects (bucket_id, name, owner)
                 values ('staff-docs', $1, $2) on conflict do nothing`, [name, who]);
        objects.push(name);
      }
      const [front, back, selfie] = paths(who);
      await q(`insert into staff_documents (uid, id_front_path, id_back_path, selfie_path)
               values ($1,$2,$3,$4)`, [who, front, back, selfie]);
    }
  });

  after(async () => {
    await q('delete from staff_documents where uid = any($1)', [[rider.uid, other.uid]]);
    // Hosted Supabase's `protect_delete` trigger refuses a direct delete from the storage
    // tables unless the caller names itself — the same door `sweep_staff_documents` goes
    // through. A teardown that does not will leave this project's bucket filling up with
    // every run, which is how `test_live` residue broke a suite at a thousand rows.
    await q("select set_config('storage.allow_delete_query','true',false)");
    await q("delete from storage.objects where bucket_id = 'staff-docs' and name = any($1)",
            [objects]);
    await q('delete from staff where uid = $1', [admin.uid]);
    await q('delete from auth.users where id = any($1)',
            [[admin.uid, rider.uid, other.uid]]);
    await db.end();
  });

  describe('who may look at them', () => {
    it('lets a person see their own', async () => {
      const rows = await as(rider, async () =>
        (await q('select uid from staff_documents')).rows);

      assert.deepEqual(rows.map((r) => r.uid), [rider.uid]);
    });

    it('shows a person nothing of anybody else\'s', async () => {
      // A policy that allows less than the query asks for returns nothing rather than
      // refusing, so this asserts the absence rather than an error.
      const rows = await as(rider, async () =>
        (await q('select uid from staff_documents where uid = $1', [other.uid])).rows);

      assert.equal(rows.length, 0);
    });

    it('lets an admin review anybody\'s', async () => {
      const rows = await as(admin, async () =>
        (await q('select uid from staff_documents where uid = any($1)',
                 [[rider.uid, other.uid]])).rows);

      assert.equal(rows.length, 2);
    });
  });

  describe('the objects themselves', () => {
    it('lets a person read their own photographs', async () => {
      const rows = await as(rider, async () =>
        (await q("select name from storage.objects where bucket_id = 'staff-docs'")).rows);

      assert.equal(rows.length, 3);
      assert.ok(rows.every((r) => r.name.startsWith(`${rider.uid}/`)));
    });

    it('shows a person none of somebody else\'s', async () => {
      const rows = await as(rider, async () =>
        (await q("select name from storage.objects where bucket_id = 'staff-docs' and name = $1",
                 [`${other.uid}/selfie.jpg`])).rows);

      assert.equal(rows.length, 0);
    });

    it('lets an admin read them all, which is the review', async () => {
      const rows = await as(admin, async () =>
        (await q("select name from storage.objects where bucket_id = 'staff-docs' " +
                 'and name = any($1)', [objects])).rows);

      assert.equal(rows.length, objects.length);
    });

    it('refuses an upload under somebody else\'s name', async () => {
      const message = await refused(rider, () =>
        q(`insert into storage.objects (bucket_id, name) values ('staff-docs', $1)`,
          [`${other.uid}/forged.jpg`]));

      assert.match(message ?? '', /row-level security/i);
    });

    it('allows an upload under their own', async () => {
      const message = await refused(rider, () =>
        q(`insert into storage.objects (bucket_id, name) values ('staff-docs', $1)`,
          [`${rider.uid}/second-try.jpg`]));

      assert.equal(message, null);
    });
  });

  describe('removing them is an act with a name on it', () => {
    // H-03. The storage policy used to grant an admin a direct delete, so papers could go
    // with nothing anywhere recording that they had — which breaks the rule H-09 settled.
    // These are the assertions PGlite cannot make: the policy, and the RPC through a real
    // token rather than as the owner of the database.
    let moderator;

    before(async () => {
      moderator = { uid: await uid(),
                    claims: { admin: true, role: 'moderator', scope: 'platform' } };
      await q("insert into staff (uid,scope,role) values ($1,'platform','moderator')",
              [moderator.uid]);
    });

    after(async () => {
      await q('delete from staff where uid = $1', [moderator.uid]).catch(() => {});
      await q('delete from auth.users where id = $1', [moderator.uid]).catch(() => {});
    });

    // Asked of the catalogue rather than by attempting a delete, for two reasons. Hosted
    // storage's own `protect_delete` raises before RLS is consulted, so a SQL attempt
    // tests Supabase's guard and not ours — and the real client path is the Storage HTTP
    // API, which consults exactly this expression. Reading the policy is the only way to
    // assert what that path will decide.
    //
    // It is also how the hole was found: `refuse_moderator_delete` was installed on 25
    // tables chosen by reading the migrations, and `storage.objects` is in a schema those
    // did not enumerate. Ask the catalogue.
    it('no longer names is_admin, so no moderator reaches it', async () => {
      const { rows } = await q(`
        select p.polname, pg_get_expr(p.polqual, p.polrelid) as expr
          from pg_policy p
          join pg_class c on c.oid = p.polrelid
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'storage' and c.relname = 'objects'
           and p.polcmd in ('d','*')`);

      assert.ok(rows.length > 0, 'there are delete policies to check');
      for (const r of rows) {
        assert.doesNotMatch(r.expr ?? '', /is_admin\(\)/,
          `${r.polname} would let a moderator delete`);
      }
    });

    it('refuses a moderator the audited path too', async () => {
      const message = await refused(moderator, () =>
        q('select admin_delete_staff_documents($1, $2)', [rider.uid, 'مش عايزها']));

      assert.match(message ?? '', /only an admin/);
    });

    it('refuses an admin who gives no reason', async () => {
      const message = await refused(admin, () =>
        q('select admin_delete_staff_documents($1, $2)', [rider.uid, '  ']));

      assert.match(message ?? '', /say why/);
    });

    it('lets an admin, with a reason, and writes the evidence', async () => {
      // Inside the `as()` block: it rolls back, so anything asserted afterwards reads a
      // database where none of this happened.
      await as(admin, async () => {
        await q('select admin_delete_staff_documents($1, $2)',
                [rider.uid, 'البطاقة مش بتاعته']);

        const left = await q(
          "select count(*)::int as n from storage.objects where bucket_id = 'staff-docs' " +
          'and name = any($1)', [paths(rider.uid)]);
        assert.equal(left.rows[0].n, 0, 'the bytes went');

        const row = await q('select count(*)::int as n from staff_documents where uid = $1',
                            [rider.uid]);
        assert.equal(row.rows[0].n, 0, 'and the row with them');

        const log = await q(
          "select actor, detail from audit_log where action = 'staffDocuments.deleted' " +
          "and detail->>'uid' = $1", [rider.uid]);
        assert.equal(log.rows.length, 1);
        assert.equal(log.rows[0].actor, admin.uid, 'the actor is who really called');
        assert.equal(log.rows[0].detail.reason, 'البطاقة مش بتاعته');
      });
    });
  });

  describe('the clock is not theirs to move', () => {
    it('refuses to let a person clear their own purge_after', async () => {
      // The whole retention rule rests on this. A courier who can null their own
      // countdown keeps their papers for ever by tapping a button nobody built yet.
      const message = await refused(rider, () =>
        q('update staff_documents set purge_after = null where uid = $1', [rider.uid]));

      assert.ok(message, 'clearing purge_after should not be permitted');
      assert.match(message, /permission denied|row-level security/i);
    });

    it('refuses to let a person delete their papers to escape the review', async () => {
      const message = await refused(rider, () =>
        q('delete from staff_documents where uid = $1', [rider.uid]));

      assert.ok(message, 'deleting the papers should not be permitted');
      assert.match(message, /permission denied|row-level security/i);
    });

    it('refuses an admin the same direct write', async () => {
      // Not a courtesy to admins: a second writer of purge_after is the exact fault that
      // parked the earlier attempt, so the function stays the only one.
      const message = await refused(admin, () =>
        q('update staff_documents set purge_after = null where uid = $1', [rider.uid]));

      assert.ok(message, 'an admin writes retention through the function or not at all');
    });

    it('keeps the retention function out of a signed-in caller\'s reach', async () => {
      const message = await refused(rider, () =>
        q('select refresh_staff_documents_retention($1)', [rider.uid]));

      assert.match(message ?? '', /permission denied/i);
    });

    it('keeps the sweep out of it too', async () => {
      const message = await refused(rider, () => q('select sweep_staff_documents()'));

      assert.match(message ?? '', /permission denied/i);
    });
  });

  describe('the triggers survive being fired by an ordinary caller', () => {
    // `staff_touches_documents` and `application_touches_documents` run as whoever ran
    // the statement, and they call a function revoked from `authenticated`. Without
    // `security definer` on the trigger *as well as* on what it calls, applying fails
    // outright with "permission denied for function" -- the same trap the delivery
    // settlement and the rating refresh each fell into, and each was found the same way:
    // by going through a real token instead of the service key.
    it('lets an applicant file an application with papers already in', async () => {
      const applicant = { uid: await uid(), claims: {} };
      const phone = '0127707' + String(Date.now()).slice(-4);
      await q('update auth.users set email = $1 where id = $2',
              [`${phone}@phone.luqma.app`, applicant.uid]);

      const message = await refused(applicant, async () => {
        await q(`insert into storage.objects (bucket_id, name) values ('staff-docs', $1)`,
                [`${applicant.uid}/id-front.jpg`]);
        await q(`insert into storage.objects (bucket_id, name) values ('staff-docs', $1)`,
                [`${applicant.uid}/id-back.jpg`]);
        await q(`insert into storage.objects (bucket_id, name) values ('staff-docs', $1)`,
                [`${applicant.uid}/selfie.jpg`]);
        await q('select set_my_staff_documents($1,$2,$3)', [
          `${applicant.uid}/id-front.jpg`,
          `${applicant.uid}/id-back.jpg`,
          `${applicant.uid}/selfie.jpg`,
        ]);
        await q(
          `insert into staff_applications (kind, name, phone, applicant_uid)
           values ('courier', 'سعيد', $1, $2)`, [phone, applicant.uid]);
      });

      assert.equal(message, null, 'the application trigger refused an ordinary caller');
      await q('delete from auth.users where id = $1', [applicant.uid]);
    });
  });

  describe('handing papers in, through a real token', () => {
    it('refuses a path that is not the caller\'s', async () => {
      const message = await refused(rider, () =>
        q('select set_my_staff_documents($1,$2,$3)',
          [...paths(rider.uid).slice(0, 2), `${other.uid}/selfie.jpg`]));

      assert.match(message ?? '', /not yours/);
    });

    it('takes a set the caller really uploaded', async () => {
      const message = await refused(rider, () =>
        q('select set_my_staff_documents($1,$2,$3)', paths(rider.uid)));

      assert.equal(message, null);
    });
  });
});
