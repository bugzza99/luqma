import { readFileSync } from 'node:fs';

/**
 * Proves create-staff-account end to end against the hosted project: a real admin
 * signs in, calls the function with a real JWT, and a second real account comes out
 * the other side with its staff row beside it. Then nothing is left behind.
 *
 * Usage: SUPABASE_ACCESS_TOKEN=... node tool/verify-create-staff.mjs
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
const serviceKey =
  keys.find((k) => k.name === 'service_role')?.api_key ??
  keys.find((k) => k.type === 'service_role')?.apikey;

const base = `https://${ref}.supabase.co`;
const stamp = Date.now();
const adminEmail = `fn-admin-${stamp}@luqma.test`;
const newEmail = `fn-new-${stamp}@luqma.test`;
const password = 'verify-1234';

const goTrue = async (path, method, body, jwt) => {
  const res = await fetch(`${base}/auth/v1/${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      apikey: serviceKey,
      Authorization: `Bearer ${jwt ?? serviceKey}`,
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  return { status: res.status, body: await res.json().catch(() => ({})) };
};

let adminUid, newUid, merchantId;
try {
  // The admin who will do the creating.
  const created = await goTrue('admin/users', 'POST', {
    email: adminEmail, password, email_confirm: true,
  });
  adminUid = created.body.id;
  if (!adminUid) throw new Error(`createAdmin: ${JSON.stringify(created.body).slice(0, 200)}`);

  // A shop for the new owner to answer for.
  const m = await sql(
    `insert into public.merchants (id, city_id, zone_id, type, name, phone, status)
     values (gen_random_uuid(), 'edku',
             (select id from public.zones where city_id = 'edku' limit 1),
             'restaurant', 'مطعم فحص الدالة', '01000000000', 'approved')
     returning id`);
  merchantId = m[0].id;
  await sql(`insert into public.staff (uid, scope, role)
             values ('${adminUid}', 'platform', 'admin')`);

  // A real sign-in, so the function judges exactly what production hands it.
  const session = await goTrue('token?grant_type=password', 'POST', {
    email: adminEmail, password,
  });
  const jwt = session.body.access_token;
  if (!jwt) throw new Error('admin sign-in produced no token');

  // The act itself.
  const fnRes = await fetch(
    `${base}/functions/v1/create-staff-account`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${jwt}` },
      body: JSON.stringify({
        email: newEmail, password, name: 'صاحب جديد',
        scope: 'merchant', role: 'owner', merchantId,
      }),
    },
  );
  const fnBody = await fnRes.json();
  console.log(`function said ${fnRes.status}: ${JSON.stringify(fnBody)}`);
  if (fnRes.status !== 200) throw new Error('the function refused');

  newUid = fnBody.uid;

  const row = (
    await sql(`select scope, role, merchant_id from public.staff
               where uid = '${newUid}'`)
  )[0];
  const okRow = row && row.scope === 'merchant' && row.role === 'owner' &&
      row.merchant_id === merchantId;
  console.log(`${okRow ? '✔' : '✖'} the new staff row is right: ${JSON.stringify(row)}`);

  // And the profile row came free from the C2 trigger.
  const profile = await sql(`select id from public.users where id = '${newUid}'`);
  console.log(`${profile.length === 1 ? '✔' : '✖'} the new account has a users row`);

  // And the new owner can actually sign in.
  const signIn = await goTrue('token?grant_type=password', 'POST', {
    email: newEmail, password,
  });
  console.log(`${signIn.status === 200 ? '✔' : '✖'} the new account can sign in`);

  if (!okRow || profile.length !== 1 || signIn.status !== 200) process.exitCode = 1;
} finally {
  try {
    const victims = [];
    if (newUid) victims.push(newUid);
    if (adminUid) victims.push(adminUid);
    for (const uid of victims) {
      await sql(`delete from public.staff where uid = '${uid}'`);
      await sql(`delete from public.users where id = '${uid}'`);
      await goTrue(`admin/users/${uid}`, 'DELETE');
    }
    if (merchantId) {
      await sql(`delete from public.staff where merchant_id = '${merchantId}'`);
      await sql(`delete from public.merchants where id = '${merchantId}'`);
    }
    console.log('cleanup done');
  } catch (e) {
    console.error('cleanup failed:', e.message);
  }
}
