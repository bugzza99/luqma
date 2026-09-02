import { readFileSync } from 'node:fs';
import pg from 'pg';

const { Client } = pg;

// The cleanup is intentionally unable to run against production. The SQL deletes only
// Luqma-owned test rows, but a typo in a connection string is not a release safeguard.
const dedicatedTestProject = 'letdxuiypazbcfxbafab';
const projectRef = process.env.LUQMA_TEST_PROJECT_REF;
const connectionString = process.env.DATABASE_URL;

if (projectRef !== dedicatedTestProject) {
  console.error(
    `Refusing cleanup: LUQMA_TEST_PROJECT_REF must be ${dedicatedTestProject}, got ` +
      `${projectRef || '(empty)'}`,
  );
  process.exit(2);
}

if (!connectionString) {
  console.error('DATABASE_URL is required');
  process.exit(2);
}

const sql = readFileSync(
  new URL('../../tool/cleanup-cloud-test-residue.sql', import.meta.url),
  'utf8',
);
const statements = sql
  .split('-->>')
  .map((statement) => statement.trim())
  .filter(Boolean);

const db = new Client({ connectionString, statement_timeout: 120_000 });

try {
  await db.connect();
  await db.query('begin');
  for (const statement of statements) await db.query(statement);
  await db.query('commit');

  const residue = await db.query(`
    select
      (select count(*)::int from public.cities
        where id like 'live-%'
           or id in ('admin-test-city', 'jobs-test-city', 'rls-test-city')
           or id ~ '^(collect|img|settle|money|rbf)-[0-9]+$') as cities,
      (select count(*)::int from auth.users) as users,
      (select count(*)::int from public.config
        where key like 'live\\_test\\_%' escape '\\') as config_rows,
      (select count(*)::int from public.plans
        where id in ('money-basic', 'jobs-test-plan')) as test_plans,
      (select count(*)::int from public.media) as media_rows,
      (select count(*)::int from storage.objects where bucket_id = 'media') as media_objects
  `);
  const counts = residue.rows[0];
  console.log(`cloud test cleanup complete: ${JSON.stringify(counts)}`);
  if (Object.values(counts).some((count) => Number(count) !== 0)) process.exitCode = 1;
} catch (error) {
  await db.query('rollback').catch(() => {});
  console.error(`cloud test cleanup failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  await db.end().catch(() => {});
}
