import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * A moderator is an admin except money, deletion, and who anybody is.
 *
 * `moderator` has been in the schema, in `StaffRole` and on the admin's own staff form
 * since Phase 2, and the access gate only ever asked `is_admin()` — which a moderator did
 * not satisfy. Creating one produced an account that opened nothing and said nothing
 * about it.
 *
 * The fix grants first and excepts afterwards: `is_admin()` widens to cover both roles,
 * so all 47 policies and 44 functions that ask it keep working unchanged, and the money,
 * the deletions and the roster are taken back by triggers and by a narrower
 * `is_platform_admin()`.
 *
 * That shape is only provable here. PGlite has no RLS, so it can show the triggers firing
 * and cannot show whether a moderator can *reach* anything at all — and "the policy
 * filtered every row away" and "the moderator may edit this" look identical from a
 * client: an empty list either way.
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

const refusedAs = (code) => (error) => {
  assert.equal(error.code, code,
    `expected SQLSTATE ${code}, got ${error.code}: ${error.message}`);
  return true;
};

describe('a moderator is an admin except', () => {
  let city, zone, merchant, admin, moderator, media;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = 'mod-' + Date.now();
    await q('insert into cities (id,name) values ($1,$2)', [city, 'مدينة المشرف']);
    zone = (await q('insert into zones (city_id,name) values ($1,$2) returning id',
                    [city, 'منطقة'])).rows[0].id;
    merchant = (await q(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ($1,'restaurant','مطعم',$2,'0100','approved') returning id`,
      [city, zone])).rows[0].id;

    admin = await uid();
    await q("insert into staff (uid,scope,role) values ($1,'platform','admin')", [admin]);
    moderator = await uid();
    await q("insert into staff (uid,scope,role) values ($1,'platform','moderator')",
            [moderator]);

    media = (await q(
      `insert into media (kind,url,status,uploaded_by) values ('menuItem',$1,'pending',$2)
       returning id`, [`https://example.test/${city}.jpg`, admin])).rows[0].id;
  });

  after(async () => {
    await q('delete from audit_log where actor = any($1)', [[admin, moderator]]).catch(() => {});
    await q('delete from media where id = $1', [media]).catch(() => {});
    await q('delete from staff where uid = any($1)', [[admin, moderator]]).catch(() => {});
    await q('delete from merchants where city_id = $1', [city]).catch(() => {});
    await q('delete from zones where city_id = $1', [city]).catch(() => {});
    await q('delete from cities where id = $1', [city]).catch(() => {});
    await db.end();
  });

  const ADMIN = () => ({ uid: admin,
                         claims: { admin: true, role: 'admin', scope: 'platform' } });
  // The claims the hook really mints for a moderator, asserted below before anything
  // leans on them.
  const MOD = () => ({ uid: moderator,
                       claims: { admin: true, role: 'moderator', scope: 'platform' } });

  describe('the token', () => {
    it('carries the admin claim, which is what lets them in at all', async () => {
      const meta = (await q(
        `select custom_access_token_hook(jsonb_build_object(
           'user_id', $1::uuid,
           'claims', jsonb_build_object('app_metadata','{}'::jsonb)
         )) -> 'claims' -> 'app_metadata' as m`, [moderator])).rows[0].m;

      assert.equal(meta.admin, true, 'without this they sign in and land on «مالكش صلاحية»');
      assert.equal(meta.role, 'moderator', 'and the screens still know which they are');
    });

    it('answers the wide question yes and the narrow one no', async () => {
      await as(MOD(), async () => {
        const r = (await q('select is_admin() as wide, is_platform_admin() as narrow')).rows[0];
        assert.equal(r.wide, true);
        assert.equal(r.narrow, false);
      });
      await as(ADMIN(), async () => {
        const r = (await q('select is_admin() as wide, is_platform_admin() as narrow')).rows[0];
        assert.equal(r.wide, true);
        assert.equal(r.narrow, true);
      });
    });

    // The reverse of a promotion is what matters: an admin demoted an hour ago carries a
    // token that still says admin, and the till has to close now rather than when the JWT
    // expires. Same lesson as a dismissal being a boundary change, not a claim change.
    it('reads the role from the row, not from the claim', async () => {
      await as({ uid: moderator, claims: { admin: true, role: 'admin', scope: 'platform' } },
        async () => {
          assert.equal((await q('select is_platform_admin() as a')).rows[0].a, false,
            'a claim that says admin does not make one');
        });
    });
  });

  describe('the work a moderator is for', () => {
    // The reach, not a trigger. A policy that allows less than the query asks for returns
    // nothing rather than refusing, so "may edit" and "sees an empty screen" are only
    // distinguishable by counting what came back.
    it('sees the shops', async () => {
      await as(MOD(), async () => {
        const r = await q('select count(*)::int as n from merchants where id = $1', [merchant]);
        assert.equal(r.rows[0].n, 1, 'an empty list reads as «مفيش مطاعم», which is a lie');
      });
    });

    it('corrects a shop, and the row really changes', async () => {
      await as(MOD(), async () => {
        const r = await q(
          "update merchants set name = 'الاسم بعد التصحيح' where id = $1 returning name",
          [merchant]);
        assert.equal(r.rowCount, 1, 'a write filtered to zero rows is a silent no');
        assert.equal(r.rows[0].name, 'الاسم بعد التصحيح');
      });
    });

    it('reviews an image, and the decision is signed with their own uid', async () => {
      await as(MOD(), async () => {
        await q("select admin_review_media($1,'rejected','مش واضحة')", [media]);
        const r = await q('select status, reviewed_by from media where id = $1', [media]);
        assert.equal(r.rows[0].status, 'rejected');
        assert.equal(r.rows[0].reviewed_by, moderator);
      });
    });
  });

  describe('the till', () => {
    it('refuses a moderator recording a collection', async () => {
      await assert.rejects(
        as(MOD(), () => q('select record_commission_payment($1,$2)', [merchant, 500])),
        refusedAs('42501'));
    });

    it('refuses a moderator filling a wallet', async () => {
      await assert.rejects(
        as(MOD(), () => q('select top_up_wallet($1,$2,$3)', [merchant, 500, moderator])),
        refusedAs('42501'));
    });

    it('refuses a moderator moving the commission rate for the whole city', async () => {
      await assert.rejects(
        as(MOD(), () => q('select admin_set_commission_policy(40, 500)')),
        refusedAs('42501'));
    });

    // The other direction, and not a formality: a change that shut the till to everybody
    // would pass all three tests above.
    it('and an admin is untouched', async () => {
      await as(ADMIN(), async () => {
        await q('select top_up_wallet($1,$2,$3)', [merchant, 500, admin]);
        const r = await q('select wallet_balance from merchants where id = $1', [merchant]);
        assert.equal(r.rows[0].wallet_balance, 500);
      });
    });
  });

  describe('deletion', () => {
    // Twenty-five tables carry a `for all` policy gated on `is_admin()`, so widening that
    // function opened the delete on every one of them at once.
    it('refuses a moderator deleting a shop', async () => {
      await assert.rejects(
        as(MOD(), () => q('delete from merchants where id = $1', [merchant])),
        refusedAs('42501'));
    });

    it('refuses a moderator deleting a place', async () => {
      await assert.rejects(
        as(MOD(), () => q('delete from zones where id = $1', [zone])),
        refusedAs('42501'));
    });

    it('refuses a moderator deleting an account', async () => {
      await assert.rejects(
        as(MOD(), () => q('delete from staff where uid = $1', [admin])),
        refusedAs('42501'));
    });

    it('and an admin still deletes', async () => {
      await as(ADMIN(), async () => {
        const r = await q('delete from media where id = $1', [media]);
        assert.equal(r.rowCount, 1);
      });
    });
  });

  describe('who mints an account', () => {
    // The trigger above already refused these — from inside the write, after the function
    // had agreed to do it and written its audit row. A door that is going to be shut is
    // shut at the door (`20261024010000_and_who_mints_an_account.sql`).
    let application;

    before(async () => {
      application = (await q(
        `insert into staff_applications (kind, name, phone, note, status)
         values ('courier', 'مندوب', $1, 'أهلاً', 'pending') returning id`,
        [`0100${Date.now() % 10000000}`])).rows[0].id;
    });

    after(async () => {
      await q('delete from staff_applications where id = $1', [application]).catch(() => {});
    });

    it('refuses a moderator approving an application', async () => {
      await assert.rejects(
        as(MOD(), () => q('select approve_staff_application($1)', [application])),
        refusedAs('42501'));
    });

    it('refuses a moderator writing the control plane through the function', async () => {
      await assert.rejects(
        as(MOD(), () => q(`select admin_set_config('{"support_whatsapp":"0100"}'::jsonb)`)),
        refusedAs('42501'));
    });

    it('refuses a moderator attaching a courier to a shop', async () => {
      // `courier_merchants` is how a rider reaches a shop's customers' addresses and
      // telephone numbers. Granting that is identity, not moderation.
      await assert.rejects(
        as(MOD(), () => q('select attach_courier_by_phone($1, $2)',
                          [merchant, '01000000000'])),
        refusedAs('42501'));
    });

    // The half that stays theirs, and the reason the whole module is still shown to them:
    // rejecting mints nothing, and a queue somebody may read and not work is not a job.
    it('but lets a moderator reject one', async () => {
      await as(MOD(), async () => {
        await q(`select review_staff_application($1, 'rejected', 'مش دلوقتي')`,
                [application]);
        const r = await q('select status from staff_applications where id = $1',
                          [application]);
        assert.equal(r.rows[0].status, 'rejected');
      });
    });
  });

  describe('who anybody is', () => {
    // The one permission that hands out every other one. `staff` carries a `for all`
    // policy, so without this a moderator with an admin's reach writes `role = 'admin'`
    // onto their own row and the rest of this file is decoration.
    it('refuses a moderator promoting themselves', async () => {
      await assert.rejects(
        as(MOD(), () => q("update staff set role='admin' where uid=$1", [moderator])),
        refusedAs('42501'));
    });

    it('refuses a moderator promoting anybody else either', async () => {
      const other = await uid();
      await q("insert into staff (uid,scope,role) values ($1,'platform','moderator')", [other]);
      try {
        await assert.rejects(
          as(MOD(), () => q("update staff set role='admin' where uid=$1", [other])),
          refusedAs('42501'));
      } finally {
        await q('delete from staff where uid = $1', [other]);
      }
    });

    // `default_commission_percent` is money by another name, and `min_supported_version`
    // walls every customer out of the product with no back door.
    it('refuses a moderator writing the control plane', async () => {
      await assert.rejects(
        as(MOD(), () => q(
          "update config set value='40'::jsonb where key='default_commission_percent'")),
        refusedAs('42501'));
    });

    it('and an admin writes it', async () => {
      await as(ADMIN(), async () => {
        const r = await q(
          "update config set value='7'::jsonb where key='default_commission_percent' " +
          'returning key');
        assert.equal(r.rowCount, 1);
      });
    });
  });
});
