import { Client } from 'pg';

import { seed } from './seed.mjs';

/**
 * Runs the seed against whatever Postgres you point it at.
 *
 * Defaults to the local stack `supabase start` brings up. Point `DATABASE_URL` at the
 * real project when it exists — the seed itself is idempotent, which is the whole reason
 * it is safe to run against something with data already in it.
 */
const url = process.env.DATABASE_URL
  // 55322, not the Supabase default 54322: Windows reserves 54084-54683 for Hyper-V on
  // this machine, so the whole stack sits 1000 above. See supabase/config.toml.
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

const client = new Client({ connectionString: url });
await client.connect();

try {
  console.log(`seeding ${url.replace(/:[^:@]*@/, ':***@')}\n`);
  const counts = await seed(client, { log: (line) => console.log(line) });
  console.log(`\ndone — ${counts.zones} zones, ${counts.landmarks} landmarks, ` +
              `${counts.plans} plans`);
} finally {
  await client.end();
}
