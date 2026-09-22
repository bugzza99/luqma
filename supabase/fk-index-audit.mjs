// Foreign keys with no index that starts with their columns.
//
//     node supabase/fk-index-audit.mjs prod      (or: test)
//
// Lives beside `seed.mjs` because `pg` resolves from `supabase/node_modules`, and reads
// the credentials in `supabase/.temp`.
//
// `supabase db lint` does not answer this — it lints PL/pgSQL bodies, not indexes — so the
// catalogue is asked directly. Postgres indexes the *referenced* side of a foreign key
// automatically and never the referencing side, so deleting a parent row scans the child
// table whole to enforce the key.
//
// An index whose leading columns match the key counts: `(merchant_id, status, placed_at)`
// serves a lookup by `merchant_id` alone, which is why the merchants-list count in M-12
// needed no new index, and a measured plan proved it.
//
// **This prints a list to argue with, not a list to apply.** Indexing all twenty-one would
// be a write on every insert for ever, mostly on tables that hold tens of rows for the
// life of a city. The rule `20261028000000` settled: index the key when the child grows
// without bound and the parent is deleted by a path somebody is waiting on.
import pg from 'pg';
import { readFileSync } from 'node:fs';
const root = new URL('.', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const which = process.argv[2] === 'test' ? 'test' : 'prod';
const u = new URL(readFileSync(`${root}/.temp/pooler-url`, 'utf8').trim());
const cfg = which === 'test'
  ? { host: 'aws-0-eu-central-1.pooler.supabase.com', port: 5432,
      user: 'postgres.' + readFileSync(`${root}/.temp/test-project-ref`, 'utf8').trim(),
      password: readFileSync(`${root}/.temp/test-db-password.txt`, 'utf8').trim() }
  : { host: u.hostname, port: +u.port, user: decodeURIComponent(u.username),
      password: readFileSync(`${root}/.temp/db-password.txt`, 'utf8').trim() };

const c = new pg.Client({ ...cfg, database: 'postgres', ssl: { rejectUnauthorized: false } });
await c.connect();

const { rows } = await c.query(`
  with fk as (
    select con.conname,
           cl.relname as tbl,
           con.conkey,
           con.confrelid::regclass::text as refs,
           cl.oid as reloid,
           (select array_agg(att.attname order by k.ord)
              from unnest(con.conkey) with ordinality k(attnum, ord)
              join pg_attribute att on att.attrelid = cl.oid and att.attnum = k.attnum
           ) as cols
      from pg_constraint con
      join pg_class cl on cl.oid = con.conrelid
      join pg_namespace n on n.oid = cl.relnamespace
     where con.contype = 'f' and n.nspname = 'public'
  )
  select fk.conname, fk.tbl, fk.cols, fk.refs,
         coalesce(pg_catalog.pg_total_relation_size(fk.reloid), 0) as bytes,
         (select coalesce(sum(s.n_live_tup), 0) from pg_stat_user_tables s
           where s.relid = fk.reloid) as live_rows
    from fk
   where not exists (
     select 1 from pg_index i
      where i.indrelid = fk.reloid
        and (i.indkey::int2[])[0:array_length(fk.conkey,1)-1] = fk.conkey
   )
   order by live_rows desc, fk.tbl`);

console.log(`${which} — foreign keys with no covering index: ${rows.length}\n`);
for (const r of rows) {
  console.log(`  ${r.tbl}.(${String(r.cols).replace(/[{}]/g,"")}) -> ${r.refs}   rows=${r.live_rows}`);
}
await c.end();
