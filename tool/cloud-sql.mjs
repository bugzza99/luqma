import { readFileSync } from 'node:fs';

/**
 * One SQL statement against the linked cloud project, over the Management API.
 *
 * `supabase db push` carries the schema, but the pooler password is not on this
 * machine, so anything that is not a migration — cleanup, verification, the seed —
 * goes through api.supabase.com with the access token instead. The token comes from
 * SUPABASE_ACCESS_TOKEN; the project ref from supabase/.temp/project-ref.
 *
 * Usage:  node tool/cloud-sql.mjs "select 1"
 *         node tool/cloud-sql.mjs --file path/to/script.sql   (statements split on `-->>`)
 */

const ref = readFileSync(new URL('../supabase/.temp/project-ref', import.meta.url), 'utf8').trim();
const token = process.env.SUPABASE_ACCESS_TOKEN;

if (!token) {
  console.error('SUPABASE_ACCESS_TOKEN is not set');
  process.exit(1);
}

async function run(query) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query }),
  });
  const body = await res.json();
  if (!res.ok) {
    throw new Error(body.message ?? body.error ?? res.statusText);
  }
  return body;
}

const arg = process.argv[2];
const statements =
  arg === '--file'
    ? readFileSync(process.argv[3], 'utf8')
        .split('-->>')
        .map((s) => s.trim())
        .filter(Boolean)
    : [arg];

for (const sql of statements) {
  const rows = await run(sql);
  console.log(`-- ${(sql.length > 60 ? `${sql.slice(0, 60)}...` : sql).replace(/\s+/g, ' ')}`);
  if (Array.isArray(rows)) {
    for (const row of rows) console.log(JSON.stringify(row));
    if (rows.length === 0) console.log('(0 rows)');
  } else {
    console.log(JSON.stringify(rows));
  }
}
