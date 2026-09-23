// Writes the current definition of every function that migrations patch in place.
//
// E1. `place_order_priced` and its neighbours are amended by `replace()` on their own
// definition, migration after migration, so the function as it runs exists in full only
// inside the database — a reviewer had to reconstruct it from a chain of anchors. This
// reads each one back with `pg_get_functiondef` and writes it to `snapshots/`, so the
// repository carries what is actually running. Documentation, never applied: migrations
// stay the only thing that changes the schema.
//
//   DATABASE_URL=<luqma-test session pooler> node snapshot-functions.mjs
//
// Run it after pushing a migration that patches one of these, and commit the result.
import pg from 'pg';
import { mkdirSync, writeFileSync } from 'node:fs';

const PATCHED = [
  'place_order', 'place_order_priced', 'check_draft_bounds', 'claim_push_batch',
  'queue_order_status_push', 'guard_columns', 'delete_my_account',
  'admin_delete_account', 'set_staff_active', 'record_commission_payment',
];

const db = new pg.Client({ connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false } });
await db.connect();
const dir = new URL('./snapshots/', import.meta.url);
mkdirSync(dir, { recursive: true });
for (const name of PATCHED) {
  const { rows } = await db.query(
    `select pg_get_functiondef(p.oid) as def, pg_get_function_identity_arguments(p.oid) as args
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = $1 order by 2`, [name]);
  if (rows.length === 0) throw new Error(`no function ${name}`);
  const body = rows.map((r) => r.def.replace(/\r/g, '').trimEnd() + ';').join('\n\n');
  writeFileSync(new URL(`${name}.sql`, dir),
    `-- SNAPSHOT of public.${name} as it runs — written by snapshot-functions.mjs.\n`
    + '-- Documentation only: never applied. Change it with a migration.\n\n' + body + '\n');
  console.log('wrote', name, `(${rows.length})`);
}
await db.end();
