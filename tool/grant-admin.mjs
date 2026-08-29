/**
 * Makes one email a platform admin of the linked project.
 *
 * Creates the account if it is not there, and either way stamps the `staff` row that
 * `custom_access_token_hook` copies into the token. The claim is what every policy reads,
 * and only this side can issue it — which is the property the whole boundary rests on.
 *
 * **It never sets a password.** A real person's account belongs to that person, so a new
 * account is invited: Supabase emails a link, they choose the password, and it is never
 * anywhere else. An existing account keeps whatever password it already has.
 *
 *   SUPABASE_ACCESS_TOKEN=... node tool/grant-admin.mjs someone@example.com
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const email = process.argv[2];
if (!email) {
  console.error('usage: node tool/grant-admin.mjs <email>');
  process.exit(1);
}

const here = dirname(fileURLToPath(import.meta.url));
const ref = readFileSync(join(here, '..', 'supabase', '.temp', 'project-ref'), 'utf8').trim();
const token = process.env.SUPABASE_ACCESS_TOKEN;
if (!token) {
  console.error('SUPABASE_ACCESS_TOKEN is not set');
  process.exit(1);
}

const PROJECT = `https://${ref}.supabase.co`;

const keys = await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys`, {
  headers: { Authorization: `Bearer ${token}` },
}).then((r) => r.json());
const serviceKey = keys.find((k) => k.id === 'service_role').api_key;

const auth = (path, init = {}) =>
  fetch(`${PROJECT}/auth/v1${path}`, {
    ...init,
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  }).then(async (r) => ({ ok: r.ok, body: await r.json() }));

async function sql(query) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`${res.status} ${JSON.stringify(body)}`);
  return body;
}

// Already there?
const found = await auth(`/admin/users?filter=${encodeURIComponent(email)}`);
let user = (found.body.users ?? []).find((u) => u.email?.toLowerCase() === email.toLowerCase());
let invited = false;

if (!user) {
  const res = await auth('/admin/generate_link', {
    method: 'POST',
    body: JSON.stringify({ type: 'invite', email }),
  });
  if (!res.ok) throw new Error(`could not invite ${email}: ${JSON.stringify(res.body)}`);
  user = res.body.user ?? res.body;
  invited = true;
  console.log(`invited ${email}`);
  if (res.body.action_link) {
    console.log('\nthe link that sets their password:\n');
    console.log(res.body.action_link);
  }
} else {
  console.log(`${email} already has an account`);
}

await sql(`
  select set_config('app.server_mode', 'on', false);
  insert into public.staff (uid, scope, role, is_active)
  values ('${user.id}', 'platform', 'admin', true)
  on conflict (uid) do update
    set scope = 'platform', role = 'admin', merchant_id = null, is_active = true;
`);

const check = await sql(`
  select public.custom_access_token_hook(
           jsonb_build_object('user_id', '${user.id}', 'claims', '{}'::jsonb)
         ) -> 'claims' -> 'app_metadata' as claims
`);

console.log(`\nclaims the token will carry: ${JSON.stringify(check.at(-1)?.[0]?.claims)}`);
if (invited) {
  console.log('\nThe account has no password until that link is used.');
}
