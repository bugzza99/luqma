/**
 * Creates and manages the accounts that are not customers: merchant owners, couriers,
 * and platform admins.
 *
 * A local script rather than a Cloud Function, because none of this needs one. Creating a
 * Firebase Auth user and stamping a custom claim on it are ordinary Admin SDK calls, and
 * the Admin SDK running on a laptop costs nothing on the Spark plan. Only *deployed*
 * functions need Blaze. The `createStaffAccount` function in `docs/07` is still worth
 * building later — it is what lets a merchant owner create their own couriers from their
 * phone without anyone opening a terminal — but the owner does not have to wait for it to
 * put real merchants on the platform.
 *
 * The claim is the whole point. `firestore.rules` decides ownership with
 * `request.auth.token.merchantId == merchantId`, and a claim can only be issued by a
 * server. A Firestore field would be something the client could try to write, and the
 * rules would then be trusting a value supplied by whoever is holding the phone.
 *
 * Against the emulator (the default, and safe):
 *   node firebase/scripts/staff.js create-owner --merchant m1 --email x@y.z
 *
 * Against the real project, which needs credentials and an explicit flag:
 *   node firebase/scripts/staff.js create-owner --merchant <id> --email <email> --production
 *
 * Credentials for --production, either one:
 *   gcloud auth application-default login
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccountKey.json
 *
 * Commands:
 *   list                                        every staff account
 *   create-owner   --merchant <id> --email <e>  a merchant owner
 *   create-courier --merchant <id> --email <e>  a courier for one merchant
 *   create-courier --platform     --email <e>   a courier for home kitchens and
 *                                               merchants that do not deliver
 *   grant-admin    --email <e>                  the platform admin claim
 *   deactivate     --email <e>                  revoke access, keep the history
 *   reactivate     --email <e>
 *
 * Optional on any create: --name "الاسم" --phone 01000000000 --password <pw>
 */
import { randomBytes } from 'node:crypto';

import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';

const PROJECT = 'luqma-edku';

const argv = process.argv.slice(2);
const command = argv[0];
const production = argv.includes('--production');

/** Reads `--flag value`, or null. */
function option(name) {
  const at = argv.indexOf(`--${name}`);
  return at >= 0 && argv[at + 1] && !argv[at + 1].startsWith('--')
    ? argv[at + 1]
    : null;
}

const flag = (name) => argv.includes(`--${name}`);

if (!production) {
  // Set before initializeApp, or the Admin SDK connects to the real project — which is
  // the whole failure this guard exists to prevent.
  process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
  process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';
}

initializeApp({ projectId: PROJECT });
const db = getFirestore();
const auth = getAuth();

/** A password somebody can read down a phone line without spelling anything twice. */
function generatePassword() {
  // No look-alikes: a merchant reading "lI0O" off a screen gets it wrong every time.
  const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
  const bytes = randomBytes(10);
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('');
}

async function findOrCreateUser(email, password) {
  const existing = await auth.getUserByEmail(email).catch(() => null);
  if (existing) return { user: existing, password: null, created: false };

  const chosen = password ?? generatePassword();
  const user = await auth.createUser({ email, password: chosen, emailVerified: false });
  return { user, password: chosen, created: true };
}

async function requireMerchant(merchantId) {
  const doc = await db.collection('merchants').doc(merchantId).get();
  if (!doc.exists) {
    // A claim naming a merchant that does not exist produces an account that signs in
    // fine and then sees nothing, with no error anywhere to explain it.
    throw new Error(
      `No merchant '${merchantId}'. Run \`list-merchants\` or create it in AdminApp first.`,
    );
  }
  return doc;
}

/** Writes the claim and the staff document together. Either both or neither is useful. */
async function grant(user, { scope, role, merchantId, name, phone }) {
  const claims = { role, scope };
  if (merchantId) claims.merchantId = merchantId;
  if (role === 'admin') claims.admin = true;

  await auth.setCustomUserClaims(user.uid, claims);
  await db.collection('staff').doc(user.uid).set(
    {
      uid: user.uid,
      scope,
      role,
      ...(merchantId ? { merchantId } : {}),
      name: name ?? user.email,
      ...(phone ? { phone } : {}),
      isActive: true,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function report({ user, password, created }, description) {
  console.log(`\n  ${created ? 'created' : 'updated'}   ${description}`);
  console.log(`  email     ${user.email}`);
  if (password) console.log(`  password  ${password}`);
  console.log(`  uid       ${user.uid}`);
  // The claim reaches the phone on the next token refresh, which is up to an hour away
  // for an app that is already open. Saying so here saves a confused message later.
  console.log('\n  Sign out and in again on the device: a claim reaches an already-open');
  console.log('  app only on the next token refresh.');
}

const commands = {
  async list() {
    const snapshot = await db.collection('staff').get();
    if (snapshot.empty) return console.log('No staff accounts.');

    for (const doc of snapshot.docs) {
      const s = doc.data();
      const where = s.merchantId ? `merchant ${s.merchantId}` : 'platform';
      const state = s.isActive === false ? ' [inactive]' : '';
      console.log(`  ${s.role.padEnd(9)} ${where.padEnd(22)} ${s.name ?? ''}${state}`);
    }
  },

  async 'list-merchants'() {
    const snapshot = await db.collection('merchants').get();
    if (snapshot.empty) return console.log('No merchants.');
    for (const doc of snapshot.docs) {
      const m = doc.data();
      console.log(`  ${doc.id.padEnd(24)} ${m.status.padEnd(10)} ${m.name}`);
    }
  },

  async 'create-owner'() {
    const merchantId = option('merchant');
    const email = option('email');
    if (!merchantId || !email) throw new Error('Needs --merchant <id> and --email <e>.');

    const merchant = await requireMerchant(merchantId);
    const account = await findOrCreateUser(email, option('password'));

    await grant(account.user, {
      scope: 'merchant',
      role: 'owner',
      merchantId,
      name: option('name') ?? merchant.data().name,
      phone: option('phone'),
    });

    // The merchant document points back, so AdminApp can show who owns it.
    await merchant.ref.set({ ownerUid: account.user.uid }, { merge: true });
    report(account, `owner of ${merchant.data().name}`);
  },

  async 'create-courier'() {
    const email = option('email');
    if (!email) throw new Error('Needs --email <e>.');

    const platform = flag('platform');
    const merchantId = option('merchant');
    if (platform === Boolean(merchantId)) {
      throw new Error('Give exactly one of --platform or --merchant <id>.');
    }

    if (merchantId) await requireMerchant(merchantId);
    const account = await findOrCreateUser(email, option('password'));

    await grant(account.user, {
      scope: platform ? 'platform' : 'merchant',
      role: 'courier',
      merchantId: merchantId ?? undefined,
      name: option('name'),
      phone: option('phone'),
    });

    report(account, platform ? 'platform courier' : `courier for ${merchantId}`);
  },

  async 'grant-admin'() {
    const email = option('email');
    if (!email) throw new Error('Needs --email <e>.');

    const account = await findOrCreateUser(email, option('password'));
    await grant(account.user, {
      scope: 'platform',
      role: 'admin',
      name: option('name'),
      phone: option('phone'),
    });
    report(account, 'platform admin');
  },

  async deactivate() {
    await setActive(false);
  },

  async reactivate() {
    await setActive(true);
  },
};

/**
 * Access is revoked in two places at once, and both matter.
 *
 * Disabling the Auth user stops any new sign-in. Clearing the claim stops the token the
 * device already holds — which is valid for up to an hour and would otherwise keep
 * reading orders from a phone somebody just took off the payroll.
 */
async function setActive(isActive) {
  const email = option('email');
  if (!email) throw new Error('Needs --email <e>.');

  const user = await auth.getUserByEmail(email);
  const doc = await db.collection('staff').doc(user.uid).get();
  if (!doc.exists) throw new Error(`No staff document for ${email}.`);

  const staff = doc.data();
  await auth.updateUser(user.uid, { disabled: !isActive });

  if (isActive) {
    await grant(user, staff);
  } else {
    await auth.setCustomUserClaims(user.uid, null);
    await auth.revokeRefreshTokens(user.uid);
    await doc.ref.set({ isActive: false, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  }

  console.log(`\n  ${isActive ? 'reactivated' : 'deactivated'}  ${email}`);
}

async function main() {
  const run = commands[command];
  if (!run) {
    console.error(
      `Unknown command '${command ?? ''}'.\n\n` +
        `  ${Object.keys(commands).join('\n  ')}\n\n` +
        'Add --production to act on the real project; without it this talks to the emulator.',
    );
    process.exit(1);
  }

  console.log(production ? `\n${PROJECT} — the real project` : '\nemulator');
  await run();
  console.log();
}

main().catch((error) => {
  console.error(`\n  ${error.message}\n`);
  process.exit(1);
});
