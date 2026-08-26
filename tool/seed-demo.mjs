/**
 * Three accounts and one shop, so the apps can actually be opened.
 *
 * The cloud project carries the schema, the policies and Edku's zones — and nothing
 * else. An admin with no merchant sees an empty list, a customer with no menu has
 * nothing to order, and neither proves anything. This makes the smallest world in which
 * every screen has something to show.
 *
 * Idempotent: re-running corrects rather than duplicates, because the passwords below
 * are meant to be handed to a person and a person mistypes them.
 *
 *   SUPABASE_ACCESS_TOKEN=... node tool/seed-demo.mjs
 *
 * Deliberately not a migration. A migration is schema and applies everywhere; this is
 * demonstration data for one project, run by hand when somebody needs something to open.
 *
 * **The passwords below are in the repository, and that is only acceptable while the
 * project has no real data in it.** Before the first merchant is onboarded: delete these
 * three accounts, or change their passwords and take them out of this file. An account
 * whose password is in git is an account anybody with the repository has.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const ref = readFileSync(join(here, '..', 'supabase', '.temp', 'project-ref'), 'utf8').trim();
const token = process.env.SUPABASE_ACCESS_TOKEN;
if (!token) {
  console.error('SUPABASE_ACCESS_TOKEN is not set');
  process.exit(1);
}

const PROJECT = `https://${ref}.supabase.co`;

/** One statement against the project, over the Management API. */
async function sql(query) {
  // Writes here touch columns the guards reserve for the server — `owner_uid`, and the
  // merchant row itself. Declaring server mode is the same thing `place_order` and the
  // billing functions do; the guard refusing this script until it did is the guard
  // working.
  query = `select set_config('app.server_mode', 'on', false);
${query}`;
  const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`${res.status} ${JSON.stringify(body)}`);
  return body;
}

// The service key is read from the project rather than pasted, so this script carries no
// secret of its own.
const keys = await fetch(`https://api.supabase.com/v1/projects/${ref}/api-keys`, {
  headers: { Authorization: `Bearer ${token}` },
}).then((r) => r.json());
const serviceKey = keys.find((k) => k.id === 'service_role').api_key;

/** Creates an account, or returns the one already there. */
async function account(email, password, meta = {}) {
  const made = await fetch(`${PROJECT}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      email, password, email_confirm: true, user_metadata: meta,
    }),
  }).then((r) => r.json());

  if (made.id) return made.id;

  // Already exists — find it and reset the password, so a re-run always leaves the
  // credentials below true.
  const found = await fetch(
    `${PROJECT}/auth/v1/admin/users?filter=${encodeURIComponent(email)}`,
    { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } },
  ).then((r) => r.json());

  const user = (found.users ?? []).find((u) => u.email === email);
  if (!user) throw new Error(`could not create or find ${email}: ${JSON.stringify(made)}`);

  await fetch(`${PROJECT}/auth/v1/admin/users/${user.id}`, {
    method: 'PUT',
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ password, email_confirm: true }),
  });
  return user.id;
}

const PASSWORD = 'luqma2026';
// The customer signs in with a phone number, not an address: CustomerApp has no email
// field at all. The address below is only what that number folds into — see
// `Phone.toAccountEmail` — and nobody ever types it.
const CUSTOMER_PHONE = '01000000001';
const people = {
  admin: 'admin@luqma.app',
  owner: 'merchant@luqma.app',
  customer: `${CUSTOMER_PHONE}@phone.luqma.app`,
};

console.log(`seeding ${PROJECT}\n`);

const adminId = await account(people.admin, PASSWORD);
const ownerId = await account(people.owner, PASSWORD);
// The metadata is what `ensure_user_profile` copies onto the profile row, and that row
// is where `place_order` reads the number the courier calls.
const customerId = await account(people.customer, PASSWORD, {
  name: 'العميل', phone: CUSTOMER_PHONE,
});
console.log('  accounts    3');

// `ensure_user_profile` already made the users rows; this only fills in what a person
// would have typed at their first checkout.
await sql(`
  update public.users set name = 'العميل', phone = '${CUSTOMER_PHONE}'
   where id = '${customerId}';

  insert into public.staff (uid, scope, role, name, phone)
  values ('${adminId}', 'platform', 'admin', 'الأدمن', '01000000000')
  on conflict (uid) do update set scope = 'platform', role = 'admin', is_active = true;
`);

// One shop, open every day, delivering to every zone in the city — the point is that
// every screen has something on it, not that the data is realistic.
const shop = await sql(`
  with z as (select id from public.zones where city_id = 'edku' order by sort_order limit 1),
  -- Guarded by name rather than by ON CONFLICT: there is no unique index on a
  -- merchant's name, and there should not be — two shops in a city may share one. So the
  -- absence is checked here, where "the demo shop" is a thing this script owns.
  m as (
    insert into public.merchants
      (city_id, type, name, zone_id, phone, status, delivers_self, min_order,
       opening_hours, revenue_model, revenue_value)
    select 'edku', 'restaurant', 'مطعم البحر', z.id, '01000000002', 'approved', true, 0,
           (select jsonb_agg(jsonb_build_object('weekday', d, 'openMinute', 0,
                                                'closeMinute', 1439))
              from generate_series(0, 6) as d),
           'commission', 1000
      from z
     where not exists (select 1 from public.merchants
                        where city_id = 'edku' and name = 'مطعم البحر')
    returning id
  )
  select coalesce((select id from m),
                  (select id from public.merchants
                    where city_id = 'edku' and name = 'مطعم البحر' limit 1)) as id;
`);

const merchantId = shop.at(-1)?.[0]?.id ?? shop[0]?.id;
if (!merchantId) throw new Error(`no merchant id in ${JSON.stringify(shop)}`);

await sql(`
  -- The owner acts for this shop. Their claim is what MerchantApp reads.
  insert into public.staff (uid, scope, role, merchant_id, name, phone)
  values ('${ownerId}', 'merchant', 'owner', '${merchantId}', 'صاحب المطعم', '01000000002')
  on conflict (uid) do update
    set scope = 'merchant', role = 'owner', merchant_id = '${merchantId}',
        is_active = true;

  update public.merchants set owner_uid = '${ownerId}' where id = '${merchantId}';

  -- Delivering everywhere in Edku, so no address the customer picks is refused.
  insert into public.merchant_served_zones (merchant_id, zone_id)
  select '${merchantId}', id from public.zones where city_id = 'edku'
  on conflict do nothing;

  insert into public.menu_categories (merchant_id, name, sort_order)
  select '${merchantId}', v.name, v.ord
    from (values ('أطباق رئيسية', 0), ('مشروبات', 1)) as v(name, ord)
   where not exists (select 1 from public.menu_categories
                      where merchant_id = '${merchantId}');
`);

await sql(`
  insert into public.menu_items (merchant_id, category_id, name, description, price, sort_order)
  select '${merchantId}',
         (select id from public.menu_categories
           where merchant_id = '${merchantId}' and name = v.cat),
         v.name, v.note, v.price, v.ord
    from (values
      ('أطباق رئيسية', 'سمك مشوي',   'صيد اليوم، مشوي على الفحم', 12000, 0),
      ('أطباق رئيسية', 'جمبري مقلي', 'بالتوم والليمون',            18000, 1),
      ('أطباق رئيسية', 'كفتة سمك',   'مع الأرز الصيادية',           9500,  2),
      ('مشروبات',      'عصير ليمون', null,                          2500,  0),
      ('مشروبات',      'مياه معدنية', null,                         1000,  1)
    ) as v(cat, name, note, price, ord)
   where not exists (select 1 from public.menu_items where merchant_id = '${merchantId}');
`);

const counts = await sql(`
  select (select count(*) from public.merchants where city_id = 'edku') as merchants,
         (select count(*) from public.menu_items) as items,
         (select count(*) from public.staff) as staff
`);

console.log('  shop        مطعم البحر');
console.log(`  menu        ${counts.at(-1)?.[0]?.items ?? '?'} items`);
console.log(`\ndone — sign in with any of:\n`);
console.log(`  admin     ${people.admin}      ${PASSWORD}   AdminApp`);
console.log(`  merchant  ${people.owner}   ${PASSWORD}   MerchantApp`);
console.log(`  customer  ${CUSTOMER_PHONE}         ${PASSWORD}   CustomerApp — the number, not an address`);
