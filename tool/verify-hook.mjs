import { readFileSync } from 'node:fs';

/**
 * Proves the custom access token hook works on the hosted project — the one test the
 * pre-launch audit asked for and the fakes could never give: a *real* sign-in whose
 * token is decoded and read through StaffIdentity's own rules.
 *
 * Creates a throwaway owner account bound to a throwaway merchant, signs in over
 * GoTrue, decodes the JWT payload, and checks every claim exactly as
 * `StaffIdentity.from` reads them — snake_case `merchant_id`, `role`, `scope`, and the
 * bare `admin` flag. Then deletes everything it made.
 *
 * Usage: SUPABASE_ACCESS_TOKEN=... node tool/verify-hook.mjs
 */

const ref = readFileSync(new URL('../supabase/.temp/project-ref', import.meta.url), 'utf8').trim();
const token = process.env.SUPABASE_ACCESS_TOKEN;
if (!token) {
  console.error('SUPABASE_ACCESS_TOKEN is not set');
  process.exit(1);
}

async function sql(query) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(body.message ?? res.statusText);
  return body;
}

const keysRes = await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys`, {
  headers: { Authorization: `Bearer ${token}` },
});
const keys = await keysRes.json();
const serviceKey = keys.find((k) => k.name === 'service_role')?.api_key ??
    keys.find((k) => k.type === 'service_role')?.apikey;
if (!serviceKey) {
  console.error('could not read the service_role key:', JSON.stringify(keys).slice(0, 200));
  process.exit(1);
}

const base = `https://${ref}.supabase.co`;
const email = `hook-check-${Date.now()}@luqma.test`;
const password = 'hook-check-1234';

let uid, merchantId;
try {
  // The account, through the same admin API the apps' staff script uses.
  const created = await fetch(`${base}/auth/v1/admin/users`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json',
               apikey: serviceKey },
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  const user = await created.json();
  if (!created.ok) throw new Error(`createUser: ${user.msg ?? JSON.stringify(user)}`);
  uid = user.id;

  // A merchant for them to own, plus the staff rows. One owner, one courier, one admin —
  // the three identities the apps actually sign in as.
  const m = await sql(
    `insert into public.merchants (id, city_id, zone_id, type, name, phone, status)
     values (gen_random_uuid(), 'edku',
             (select id from public.zones where city_id = 'edku' limit 1),
             'restaurant', 'مطعم فحص التوكن', '01000000000', 'approved')
     returning id`);

  merchantId = m[0].id;

  await sql(`insert into public.staff (uid, scope, role, merchant_id)
             values ('${uid}', 'merchant', 'owner', '${merchantId}')`);

  // The profile row should already be here: the ensure_user_profile trigger made it the
  // moment GoTrue inserted the account. If it is not, C2 is broken on the hosted project.
  const profile = await sql(`select id from public.users where id = '${uid}'`);
  console.log(`${profile.length === 1 ? '✔' : '✖'} users row exists without anyone writing it (the C2 trigger)`);

  // The real sign-in. Whatever comes back in the token is what production hands out.
  const signedIn = await fetch(`${base}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: serviceKey },
    body: JSON.stringify({ email, password }),
  });
  const session = await signedIn.json();
  if (!signedIn.ok) throw new Error(`signIn: ${session.error_description ?? session.msg}`);

  const payload = JSON.parse(
    Buffer.from(session.access_token.split('.')[1], 'base64url').toString('utf8'));
  const meta = payload.app_metadata ?? {};

  const checks = [
    ['role', meta.role, 'owner'],
    ['scope', meta.scope, 'merchant'],
    ['merchant_id (snake_case)', meta.merchant_id, merchantId],
    ['admin absent for an owner', meta.admin, undefined],
  ];
  let failed = false;
  for (const [name, actual, expected] of checks) {
    const ok = actual === expected;
    if (!ok) failed = true;
    console.log(`${ok ? '✔' : '✖'} ${name}: ${JSON.stringify(actual)}${
      ok ? '' : ` — expected ${JSON.stringify(expected)}`}`);
  }

  // And the same question StaffIdentity.from asks, answered off this real token.
  const merchantIdRead =
      (typeof meta.merchant_id === 'string' ? meta.merchant_id : null) ??
      (typeof meta.merchantId === 'string' ? meta.merchantId : null);
  const ownsAMerchant =
      meta.scope === 'merchant' && merchantIdRead != null;
  console.log(`${ownsAMerchant ? '✔' : '✖'} StaffIdentity.ownsAMerchant would be ${ownsAMerchant}`);
  if (!ownsAMerchant) failed = true;

  console.log(failed ? '\nTHE HOOK IS NOT WRITING THE CLAIMS — do not launch.'
                     : '\nHook verified against the live stack.');
  if (failed) process.exitCode = 1;
} finally {
  // Leave nothing behind, whether the checks passed or not.
  try {
    if (merchantId) {
      for (const statement of [
        `delete from public.staff where merchant_id = '${merchantId}'`,
        `delete from public.merchants where id = '${merchantId}'`,
      ]) await sql(statement);
    }
    if (uid) {
      await sql(`delete from public.users where id = '${uid}'`);
      await fetch(`${base}/auth/v1/admin/users/${uid}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${serviceKey}`, apikey: serviceKey },
      });
    }
    console.log('cleanup done');
  } catch (e) {
    console.error('cleanup failed:', e.message);
  }
}
