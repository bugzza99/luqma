import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { seed, edkuData } from '../../seed.mjs';
import { freshDatabase } from './harness.mjs';

/**
 * Edku, landing in Postgres.
 *
 * The interesting property is not that it inserts rows — it is that it reads the *same*
 * `data/edku.json` the Firestore seed reads. The zone and landmark names in it are
 * still placeholders, and a courier sent to the wrong part of town because one backend
 * was re-seeded and the other was not is the failure this is guarding against.
 */

let db;

before(async () => {
  db = await freshDatabase();
});

after(() => db?.close());

const count = async (table) => {
  const r = await db.query(`select count(*)::int as n from ${table}`);
  return r.rows[0].n;
};

describe('seeding Edku', () => {
  it('puts the city, its zones and its landmarks in', async () => {
    const data = edkuData();
    await seed(db);

    assert.equal(await count('cities'), 1);
    assert.equal(await count('zones'), data.zones.length);
    assert.equal(await count('landmarks'), data.landmarks.length);
  });

  it('resolves a landmark to the zone the file named by slug', async () => {
    const data = edkuData();
    const first = data.landmarks[0];
    const zoneName = data.zones.find((z) => z.id === first.zoneId).name;

    const r = await db.query(
      `select z.name as zone from landmarks l join zones z on z.id = l.zone_id
        where l.name = $1`,
      [first.name],
    );

    assert.equal(r.rows[0].zone, zoneName);
  });

  it('brings the plans, with their features intact', async () => {
    const r = await db.query("select features from plans where id = 'basic'");
    assert.equal(r.rows[0].features.verifiedBadge, true);
  });

  it('brings the home sections, with their params', async () => {
    const r = await db.query(
      "select params from home_sections where key = 'top_banner' and city_id = 'edku'",
    );
    assert.equal(r.rows[0].params.maxAds, 3);
  });

  it('starts unfinished launch capabilities closed', async () => {
    const r = await db.query(
      `select key, value from config where key in (
        'otp_enabled', 'admob_enabled', 'public_comments_enabled',
        'online_payment_enabled', 'marketing_push_per_week'
      ) order by key`,
    );

    assert.deepEqual(Object.fromEntries(r.rows.map(({ key, value }) => [key, value])), {
      admob_enabled: false,
      marketing_push_per_week: 0,
      online_payment_enabled: false,
      otp_enabled: false,
      public_comments_enabled: false,
    });
  });

  // The names in the file are placeholders the owner will replace, so this runs again
  // and again by design. Twice must mean the same thing as once.
  it('seeding twice changes nothing', async () => {
    const before = {
      zones: await count('zones'),
      landmarks: await count('landmarks'),
      plans: await count('plans'),
      sections: await count('home_sections'),
    };

    await seed(db);

    assert.deepEqual(
      {
        zones: await count('zones'),
        landmarks: await count('landmarks'),
        plans: await count('plans'),
        sections: await count('home_sections'),
      },
      before,
    );
  });

  // The real reason it is idempotent: correcting a name is the expected operation.
  it('a corrected fee reaches a zone that is already there', async () => {
    await db.query("update zones set default_delivery_fee = 1 where sort_order = 0");
    await seed(db);

    const data = edkuData();
    const expected = data.zones.find((z) => (z.sortOrder ?? 0) === 0).defaultDeliveryFee;
    const r = await db.query('select default_delivery_fee as fee from zones where sort_order = 0');

    assert.equal(r.rows[0].fee, expected);
  });

  // A landmark pointing at a zone nobody defined. Without the guard this inserts against
  // nothing, and a landmark in no zone is one nobody is ever sent to. Remove the `if` in
  // `seed` and this fails on the count, not on the log line.
  it('a landmark in an unknown zone is skipped, and said out loud', async () => {
    const before = await count('landmarks');
    const said = [];

    await seed(db, {
      log: (line) => said.push(line),
      data: {
        city: { id: 'edku', name: 'إدكو', isActive: true },
        zones: [{ id: 'balad', name: 'البلد', defaultDeliveryFee: 800, sortOrder: 0 }],
        landmarks: [
          { zoneId: 'balad', name: 'علامة معروفة' },
          { zoneId: 'zone-that-is-not-in-the-file', name: 'علامة تايهة' },
        ],
        plans: [],
        homeSections: [],
      },
    });

    assert.equal(await count('landmarks'), before + 1, 'only the resolvable one lands');

    const complaint = said.find((line) => line.includes('علامة تايهة'));
    assert.ok(complaint, 'the skip has to be visible, or it is data lost in silence');
    assert.match(complaint, /unknown zone/);
  });
});
