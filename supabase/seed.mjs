import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

/**
 * Edku, into Postgres.
 *
 * Reads `data/edku.json` — the same file the Firestore seed reads, deliberately, and
 * deliberately *outside* `firebase/`: that directory is deleted at the end of this
 * migration, and the zone and landmark names in this file are the one thing in the whole
 * backend that nobody can regenerate.
 *
 * Those names are still placeholders the owner has to replace with local knowledge. One
 * file means that happens once and both backends get it, rather than the two drifting
 * apart mid-migration and a courier being sent to the wrong part of town by whichever
 * one was forgotten.
 *
 * Idempotent. Re-seeding corrects what is there instead of piling up duplicates, which
 * matters because the names above are expected to change.
 *
 * Takes anything with `query(sql, params)`: PGlite in the tests, `pg` or the Supabase
 * client against a real project.
 */

const here = dirname(fileURLToPath(import.meta.url));

export function edkuData() {
  return JSON.parse(
    readFileSync(join(here, '..', 'data', 'edku.json'), 'utf8'),
  );
}

export async function seed(db, { log = () => {}, data = edkuData() } = {}) {

  await db.query(
    `insert into cities (id, name, is_active) values ($1, $2, $3)
     on conflict (id) do update set name = excluded.name, is_active = excluded.is_active`,
    [data.city.id, data.city.name, data.city.isActive ?? true],
  );
  log(`  city        ${data.city.name}`);

  // The file names zones by slug — `balad`, `sahel` — and landmarks point at those slugs.
  // The database keys them by uuid, so the mapping lives here for the length of one run
  // rather than as a column that exists only to make seeding convenient.
  const zoneIdBySlug = new Map();
  for (const zone of data.zones) {
    const existing = await db.query(
      'select id from zones where city_id = $1 and name = $2',
      [data.city.id, zone.name],
    );

    if (existing.rows.length > 0) {
      const id = existing.rows[0].id;
      await db.query(
        'update zones set default_delivery_fee = $2, sort_order = $3, is_active = $4 where id = $1',
        [id, zone.defaultDeliveryFee ?? 0, zone.sortOrder ?? 0, zone.isActive ?? true],
      );
      zoneIdBySlug.set(zone.id, id);
      continue;
    }

    const inserted = await db.query(
      `insert into zones (city_id, name, default_delivery_fee, sort_order, is_active)
       values ($1, $2, $3, $4, $5) returning id`,
      [data.city.id, zone.name, zone.defaultDeliveryFee ?? 0, zone.sortOrder ?? 0,
       zone.isActive ?? true],
    );
    zoneIdBySlug.set(zone.id, inserted.rows[0].id);
  }
  log(`  zones       ${data.zones.length}`);

  let landmarks = 0;
  for (const landmark of data.landmarks) {
    const zoneId = zoneIdBySlug.get(landmark.zoneId);
    if (!zoneId) {
      // Named against a zone the file does not define. Skipped loudly rather than
      // inserted against nothing, because a landmark in no zone is a landmark nobody
      // will ever be sent to.
      log(`  ! landmark "${landmark.name}" names unknown zone "${landmark.zoneId}", skipped`);
      continue;
    }

    const existing = await db.query(
      'select id from landmarks where zone_id = $1 and name = $2',
      [zoneId, landmark.name],
    );
    if (existing.rows.length > 0) {
      await db.query('update landmarks set icon = $2 where id = $1',
                     [existing.rows[0].id, landmark.icon ?? null]);
    } else {
      await db.query(
        'insert into landmarks (city_id, zone_id, name, icon) values ($1, $2, $3, $4)',
        [data.city.id, zoneId, landmark.name, landmark.icon ?? null],
      );
    }
    landmarks++;
  }
  log(`  landmarks   ${landmarks}`);

  for (const plan of data.plans) {
    await db.query(
      `insert into plans (id, name, price_monthly, features, sort_order, is_active)
       values ($1, $2, $3, $4, $5, $6)
       on conflict (id) do update set
         name = excluded.name,
         price_monthly = excluded.price_monthly,
         features = excluded.features,
         sort_order = excluded.sort_order,
         is_active = excluded.is_active`,
      [plan.id, plan.name, plan.priceMonthly ?? 0, JSON.stringify(plan.features ?? {}),
       plan.sortOrder ?? 0, plan.isActive ?? true],
    );
  }
  log(`  plans       ${data.plans.length}`);

  for (const section of data.homeSections) {
    await db.query(
      `insert into home_sections (key, city_id, type, title_ar, sort_order, is_visible, params)
       values ($1, $2, $3, $4, $5, $6, $7)
       on conflict (key, city_id) do update set
         type = excluded.type,
         title_ar = excluded.title_ar,
         sort_order = excluded.sort_order,
         is_visible = excluded.is_visible,
         params = excluded.params`,
      [section.key, data.city.id, section.type, section.titleAr ?? '',
       section.sortOrder ?? 0, section.isVisible ?? true,
       JSON.stringify(section.params ?? {})],
    );
  }
  log(`  sections    ${data.homeSections.length}`);

  // What `RemoteConfigService` used to fetch. Key by key, so a value the owner has
  // already set is not reset by a re-seed.
  for (const [key, value] of Object.entries({
    support_whatsapp: '',
    otp_enabled: false,
    admob_enabled: false,
    public_comments_enabled: false,
    online_payment_enabled: false,
    marketing_push_per_week: 0,
  })) {
    await db.query(
      'insert into config (key, value) values ($1, $2) on conflict (key) do nothing',
      [key, JSON.stringify(value)],
    );
  }
  log('  config      appConfig');

  return { zones: data.zones.length, landmarks, plans: data.plans.length };
}
