// Read-only. Any landmark whose name is not Arabic, and the totals per zone.
import pg from 'pg';
import { readFileSync } from 'node:fs';

const pw = readFileSync(process.argv[2], 'utf8').trim();
const u = new URL(readFileSync(process.argv[3], 'utf8').trim());
const client = new pg.Client({
  host: u.hostname,
  port: Number(u.port),
  database: u.pathname.replace(/^\//, ''),
  user: decodeURIComponent(u.username),
  password: pw,
  ssl: { rejectUnauthorized: false },
});
await client.connect();

const { rows } = await client.query(`
  select z.name as zone, l.name, l.lat is not null as has_xy
    from landmarks l join zones z on z.id = l.zone_id
   order by z.sort_order, l.name
`);

const latin = rows.filter((r) => /[A-Za-z]/.test(r.name));
console.log(`landmarks: ${rows.length}, with coordinates: ${rows.filter((r) => r.has_xy).length}`);
console.log(`names containing Latin letters: ${latin.length}`);
for (const r of latin) console.log(`  ${r.zone}  ${r.name}`);

const eshra = rows.filter((r) => r.name.includes('عشرة'));
for (const r of eshra) console.log(`  found: ${r.zone}  ${r.name}`);

await client.end();
