import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * Images, and the cuisines that carry one.
 *
 * Every image column in this product has existed since the first schema — a merchant's
 * logo and cover, a menu item, a daily meal, a promotion — and the moderation queue that
 * reviews them was built and tested. Nothing could ever put an image in it: there was no
 * bucket, no policy on `storage.objects`, and no upload method on the repository. The
 * queue reviewed a table nothing wrote to.
 *
 * This is the boundary half of closing that. What a *screen* does is a widget test's
 * question; what the database permits is this one's, against real tokens.
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

describe('images and cuisines', () => {
  let city, zone, merchant, admin, owner, customer;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();

    city = 'img-' + Date.now();
    await q('insert into cities (id,name) values ($1,$2)', [city, 'مدينة الصور']);
    zone = (await q('insert into zones (city_id,name) values ($1,$2) returning id',
                    [city, 'منطقة'])).rows[0].id;
    merchant = (await q(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ($1,'restaurant','مطعم',$2,'0100','approved') returning id`,
      [city, zone])).rows[0].id;

    admin = { uid: await uid(), claims: { admin: true, role: 'admin', scope: 'platform' } };
    owner = { uid: await uid(),
              claims: { role: 'owner', scope: 'merchant', merchant_id: merchant } };
    customer = { uid: await uid(), claims: {} };

    await q("insert into staff (uid,scope,role) values ($1,'platform','admin')", [admin.uid]);
    await q("insert into staff (uid,scope,role,merchant_id) values ($1,'merchant','owner',$2)",
            [owner.uid, merchant]);
  });

  after(async () => {
    await q('delete from merchants where city_id = $1', [city]);
    await q('delete from zones where city_id = $1', [city]);
    await q('delete from cities where id = $1', [city]);
    await db.end();
  });

  describe('the moderation gate', () => {
    // The gate as it already stood: an uploader approving their own upload is the gate
    // with a hole in it.
    it('a customer cannot file an image already approved', async () => {
      const error = await refused(customer, () => q(
        `insert into media (kind,url,status,uploaded_by)
         values ('menuItem','x.jpg','approved',$1)`, [customer.uid]));
      assert.ok(error, 'refused');
    });

    it('a merchant owner cannot either', async () => {
      const error = await refused(owner, () => q(
        `insert into media (kind,url,status,uploaded_by)
         values ('menuItem','x.jpg','approved',$1)`, [owner.uid]));
      assert.ok(error, 'refused');
    });

    // The admin *is* the moderator. Making them upload, then walk to the queue and
    // approve their own photo, is one decision taken twice by one person.
    it('an admin may, because approving is the thing they do', async () => {
      const error = await refused(admin, () => q(
        `insert into media (kind,url,status,uploaded_by)
         values ('menuItem','x.jpg','approved',$1)`, [admin.uid]));
      assert.equal(error, null, 'an admin uploads pre-approved');
    });
  });

  // The owner's photo on حول لقمة, and the picture on a cuisine circle, are images like
  // any other — so they need a kind, or they cannot pass through the one door.
  describe('what an image can be of', () => {
    for (const kind of ['aboutPhoto', 'cuisine']) {
      it(`${kind} is a kind an image may have`, async () => {
        const error = await refused(admin, () => q(
          `insert into media (kind,url,status,uploaded_by)
           values ($1,'x.jpg','approved',$2)`, [kind, admin.uid]));
        assert.equal(error, null);
      });
    }
  });

  describe('cuisines', () => {
    it('anybody may read them — they are the home screen', async () => {
      const rows = await as(customer, () => q('select * from cuisines'));
      assert.ok(Array.isArray(rows.rows));
    });

    it('only an admin writes one', async () => {
      const byCustomer = await refused(customer, () => q(
        'insert into cuisines (city_id,name) values ($1,$2)', [city, 'مشويات']));
      assert.ok(byCustomer, 'a customer cannot invent a cuisine');

      const byOwner = await refused(owner, () => q(
        'insert into cuisines (city_id,name) values ($1,$2)', [city, 'مشويات']));
      assert.ok(byOwner, 'nor can a merchant, or every shop names its own');

      const byAdmin = await refused(admin, () => q(
        'insert into cuisines (city_id,name) values ($1,$2)', [city, 'مشويات']));
      assert.equal(byAdmin, null);
    });

    // A merchant tagging themselves "مشويات" to appear under a circle they do not
    // belong in is the cheapest promotion in the product, and it is not for sale.
    it('a merchant cannot tag itself into a cuisine', async () => {
      const cuisine = (await q(
        'insert into cuisines (city_id,name) values ($1,$2) returning id',
        [city, 'أسماك-' + Date.now()])).rows[0].id;

      const error = await refused(owner, () => q(
        'insert into merchant_cuisines (merchant_id,cuisine_id) values ($1,$2)',
        [merchant, cuisine]));
      assert.ok(error);

      await q('delete from cuisines where id = $1', [cuisine]);
    });
  });

  describe('how long the food takes', () => {
    it('every merchant has an answer, without anyone typing one', async () => {
      const row = (await q('select prep_minutes from merchants where id = $1',
                           [merchant])).rows[0];
      assert.ok(row.prep_minutes > 0,
                'a card that says nothing about time is worse than an estimate');
    });

    it('is settable, within reason', async () => {
      const tooLong = await refused(admin, () => q(
        'update merchants set prep_minutes = 600 where id = $1', [merchant]));
      assert.ok(tooLong, 'ten hours is a typo, not a kitchen');
    });
  });
});
