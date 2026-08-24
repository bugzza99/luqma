/**
 * Puts Edku into an empty database.
 *
 * Written as a script rather than typed into AdminApp because the emulator's data is
 * wiped constantly during development, and re-entering eight zones and thirty landmarks
 * by hand every time is time spent on nothing. It also makes Edku's own data part of the
 * repository — reviewable, diffable, and correctable in one place.
 *
 * Against the emulator (the default, and safe):
 *   node firebase/seed/seed.js
 *
 * Against the real project, which will refuse unless you mean it:
 *   node firebase/seed/seed.js --production
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

const HERE = dirname(fileURLToPath(import.meta.url));
const PROJECT = 'luqma-edku';

const production = process.argv.includes('--production');

if (production) {
  // Seeding production twice would overwrite prices and fees the owner had adjusted by
  // hand. Nothing here is destructive by accident.
  if (!process.env.LUQMA_SEED_PRODUCTION) {
    console.error(
      'Refusing to seed production without LUQMA_SEED_PRODUCTION set.\n' +
      'This overwrites zones, plans and home sections with the contents of edku.json,\n' +
      'including any delivery fee you have since changed in AdminApp.',
    );
    process.exit(1);
  }
} else {
  // Pointing the Admin SDK at the emulator. Set before initializeApp, or it connects to
  // the real project — which is the whole failure this guard exists to prevent.
  process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
  process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
}

initializeApp({ projectId: PROJECT });
const db = getFirestore();
const auth = getAuth();

// Edku lives in `data/`, not here: this directory goes away with Firebase, and the
// zone and landmark names in that file are the one thing in it nobody can regenerate.
const data = JSON.parse(readFileSync(join(HERE, '..', '..', 'data', 'edku.json'), 'utf8'));

/** Writes a batch, keyed by document id. */
async function put(collection, docs, idOf = (d) => d.id) {
  const batch = db.batch();
  for (const doc of docs) {
    const { id, ...rest } = doc;
    batch.set(db.collection(collection).doc(idOf(doc)), {
      ...rest,
      cityId: data.city.id,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  await batch.commit();
  return docs.length;
}

async function main() {
  console.log(`seeding ${production ? 'PRODUCTION' : 'the emulator'} — project ${PROJECT}\n`);

  await db.collection('cities').doc(data.city.id).set(data.city, { merge: true });
  console.log(`  city        ${data.city.name}`);

  console.log(`  zones       ${await put('zones', data.zones)}`);

  // Landmarks have no natural id in the file; one derived from the zone and the name
  // keeps re-seeding idempotent instead of piling up duplicates.
  const landmarks = data.landmarks.map((l) => ({
    ...l,
    id: `${l.zoneId}-${l.name.replace(/\s+/g, '-')}`,
  }));
  console.log(`  landmarks   ${await put('landmarks', landmarks)}`);

  console.log(`  plans       ${await put('plans', data.plans)}`);
  console.log(`  sections    ${await put('homeSections', data.homeSections, (s) => s.key)}`);

  await db.collection('config').doc('appConfig').set({
    supportWhatsapp: '',
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  console.log('  config      appConfig');

  if (!production) {
    // A ready-made admin so development does not begin with a sign-in every time.
    // Only ever on the emulator: on the real project the claim is granted once, by hand,
    // to the owner's own Google account.
    const email = 'admin@luqma.test';
    const user = await auth.createUser({ uid: 'dev-admin', email, password: 'luqma1234' })
      .catch(() => auth.getUser('dev-admin'));
    await auth.setCustomUserClaims(user.uid, { admin: true });
    await db.collection('staff').doc(user.uid).set({
      scope: 'platform',
      role: 'admin',
      name: 'أدمن التطوير',
      isActive: true,
    }, { merge: true });
    console.log(`\n  dev admin   ${email} / luqma1234`);
  }

  console.log('\ndone.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
