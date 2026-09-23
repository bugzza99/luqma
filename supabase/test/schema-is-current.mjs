import { readdirSync } from 'node:fs';
import pg from 'pg';

// Refuses to let the cloud suites run against a test database that is behind the
// repository.
//
// `luqma-test` fell 34 migrations behind production once, and nothing noticed: the stack
// and live suites went on passing against an old schema for a week, and when it was
// brought up to date they found `hold_prepaid_credit` refusing every prepaid delivery.
// A green suite against a stale schema proves nothing, and reads as proof. So the run
// asks the database which migrations it has before it asks it anything else, and names
// every file it is missing.
//
// Read-only: it runs one select, and it never applies anything — applying migrations is a
// deliberate act (`supabase db push --db-url …`), not a side effect of running tests.

const { Client } = pg;

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error('DATABASE_URL is required');
  process.exit(2);
}

const local = readdirSync(new URL('../migrations/', import.meta.url))
  .filter((name) => name.endsWith('.sql'))
  .sort();
const versionOf = (name) => name.split('_')[0];

const db = new Client({ connectionString, statement_timeout: 60_000 });
let applied;
try {
  await db.connect();
  applied = new Set(
    (await db.query('select version from supabase_migrations.schema_migrations'))
      .rows.map((row) => row.version),
  );
} finally {
  await db.end().catch(() => {});
}

const missing = local.filter((name) => !applied.has(versionOf(name)));

if (missing.length > 0) {
  console.error(
    `The test database is missing ${missing.length} migration(s) this repository has:`,
  );
  for (const name of missing) console.error(`  ${name}`);
  console.error(
    'Push them first (npx supabase db push --db-url <luqma-test session pooler>); ' +
      'the suites would otherwise pass against a schema production does not have.',
  );
  process.exit(1);
}

console.log(`schema is current: all ${local.length} migrations applied`);
