// A connection to luqma-edku that survives the first attempt failing.
//
// Here rather than in  because  is a dependency of this package, and a helper
// that cannot resolve its own driver is a helper that only works from one directory.
//
// The pooler drops or refuses a connection often enough over this link that a one-shot
// `new Client(...).connect()` fails a few times an hour — and a migration script that
// dies on connect looks exactly like one that died halfway through applying something.
// Retrying makes the difference visible: either it connects and does the work, or it
// says it could not connect and did nothing.
import pg from 'pg';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));

/// The password, read from the gitignored file the CLI wrote.
export function password() {
  return fs
    .readFileSync(path.join(here, '.temp', 'db-password.txt'), 'utf8')
    .trim();
}

/// Session mode (5432), never transaction mode: anything that sets a role or holds a
/// transaction open across statements needs the same backend for all of them.
export async function connect({ attempts = 5 } = {}) {
  const url =
    'postgresql://postgres.vqcivwdoekyfqhfmnuos:' +
    encodeURIComponent(password()) +
    '@aws-0-eu-central-1.pooler.supabase.com:5432/postgres';

  for (let i = 1; i <= attempts; i++) {
    const client = new pg.Client({ connectionString: url, connectionTimeoutMillis: 25000 });
    try {
      await client.connect();
      return client;
    } catch (error) {
      await client.end().catch(() => {});
      console.error(`  connect ${i}/${attempts} failed: ${error.code ?? error.message}`);
      if (i < attempts) await new Promise((r) => setTimeout(r, 4000));
    }
  }
  throw new Error('could not reach luqma-edku');
}
