// Adds المعدية and its eight places to the live geography.
//
// It was left out of `apply-edku-geography.mjs` because the owner excluded it, and put
// back on 2026-09-11 because they asked for it — «من أكبر الأماكن في إدكو».
//
// **Additive only.** Nothing here deletes, and nothing here touches a zone or a landmark
// that already exists: the previous geography script had to move merchants and delete a
// test order because it was replacing the whole city, and none of that risk belongs in
// adding one zone. It is safe to run twice — the zone is matched by name and the
// landmarks by (zone, name), so a second run reports zero inserts rather than a duplicate
// set.
//
// The eight points come from the same research as the other thirty-five, and they sit in
// **two clusters about seven kilometres apart**: five around longitude 30.17 and three
// around 30.25. That is what the sources say rather than a transcription error, and the
// research file flags two of the school names as possibly one place listed twice. Both
// are recorded here rather than quietly averaged, because a landmark in the wrong part of
// town sends a courier to the wrong part of town — and the places screen in AdminApp is
// where somebody with local knowledge fixes it.
//
// Run: node add-maadiya.mjs <password-file> <pooler-url-file> [--commit]
// Without --commit it rolls back and prints what it would have done.
import pg from 'pg';
import { readFileSync } from 'node:fs';

const ZONE = { name: 'المعدية', fee: 1500, sortOrder: 3 };

// Names exactly as their source lists them, including «المعديه» on the technical school:
// that is what is on the sign and what somebody will say on the phone.
const PLACES = [
  ['المعدية', 31.2838358, 30.2455033],
  ['محطة قطار المعدية', 31.2673033, 30.1745691],
  ['مدرسة المعدية الثانوية المشتركة', 31.2688999, 30.1803588],
  ['مدرسة المعدية الاعدادية المشتركه', 31.2661203, 30.1749165],
  ['مدرسة المعدية الابتدائية المشتركة', 31.2677242, 30.1755029],
  ['مدرسة بني المعدية', 31.2676486, 30.1758945],
  ['مدرسة المعديه الفنيه بنات', 31.2786712, 30.2523813],
  ['مدرسة المعدية الرسمية لغات', 31.2799523, 30.2504565],
];

const pw = readFileSync(process.argv[2], 'utf8').trim();
const u = new URL(readFileSync(process.argv[3], 'utf8').trim());
const commit = process.argv.includes('--commit');

const client = new pg.Client({
  host: u.hostname,
  port: Number(u.port),
  database: u.pathname.replace(/^\//, ''),
  user: decodeURIComponent(u.username),
  password: pw,
  ssl: { rejectUnauthorized: false },
});
await client.connect();

try {
  await client.query('begin');

  const city = (await client.query('select id from cities limit 1')).rows[0]?.id;
  if (!city) throw new Error('no city row — this is not the Edku database');

  const existing = await client.query(
    'select id from zones where city_id = $1 and name = $2', [city, ZONE.name]);

  const zone = existing.rowCount
    ? existing.rows[0].id
    : (await client.query(
        `insert into zones (city_id, name, default_delivery_fee, sort_order)
         values ($1, $2, $3, $4) returning id`,
        [city, ZONE.name, ZONE.fee, ZONE.sortOrder])).rows[0].id;
  console.log(existing.rowCount ? `zone already there: ${zone}` : `zone added: ${zone}`);

  let added = 0;
  for (const [name, lat, lng] of PLACES) {
    const there = await client.query(
      'select 1 from landmarks where zone_id = $1 and name = $2', [zone, name]);
    if (there.rowCount) {
      console.log(`  = ${name}`);
      continue;
    }
    await client.query(
      `insert into landmarks (city_id, zone_id, name, lat, lng)
       values ($1, $2, $3, $4, $5)`, [city, zone, name, lat, lng]);
    console.log(`  + ${name}  ${lat}, ${lng}`);
    added += 1;
  }

  // Read back through the same connection before deciding anything: the count that
  // matters is what the database holds, not what this script believes it sent.
  const check = await client.query(
    `select count(*)::int as n, count(lat)::int as pinned
       from landmarks where zone_id = $1`, [zone]);
  console.log(`\n${ZONE.name}: ${check.rows[0].n} landmarks, ${check.rows[0].pinned} pinned`);
  console.log(`added this run: ${added}`);

  if (check.rows[0].n !== PLACES.length || check.rows[0].pinned !== PLACES.length) {
    throw new Error(
      `expected ${PLACES.length} landmarks all pinned; refusing to commit a half-built zone`);
  }

  if (commit) {
    await client.query('commit');
    console.log('committed');
  } else {
    await client.query('rollback');
    console.log('rolled back — pass --commit to keep it');
  }
} catch (e) {
  await client.query('rollback');
  console.error('rolled back:', e.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
