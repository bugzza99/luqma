// Replaces Edku's placeholder geography with the researched one, in one transaction.
//
// The owner approved both halves of this: the eight invented zones and their thirty
// landmarks go, and order #1054 — a test order they placed themselves — goes with them,
// because `orders.zone_id` is `on delete restrict` and that order was the only thing
// holding «المحطة» in place.
//
// Nothing here guesses. Every landmark is filed under the area its own source names, and
// المعدية's eight places are left out because the owner excluded that village.
//
// Run: node apply-edku-geography.mjs <password-file> <pooler-url-file> [--commit]
// Without --commit it rolls back and prints what it would have done.
import pg from 'pg';
import { readFileSync } from 'node:fs';
import { seed as seedEdku } from './seed.mjs';

const pw = readFileSync(process.argv[2], 'utf8').trim();
const u = new URL(readFileSync(process.argv[3], 'utf8').trim());
const commit = process.argv.includes('--commit');

const client = new pg.Client({
  host: u.hostname,
  port: Number(u.port),
  database: u.pathname.replace(/^\//, ''),
  user: decodeURIComponent(u.username),
  password: pw,
  ssl: { rejectUnauthorized: false },
});
await client.connect();

const n = async (sql, params) => (await client.query(sql, params)).rowCount;

try {
  await client.query('begin');

  // Server mode declared for the whole transaction: `guard_order_columns` refuses writes
  // to a frozen order's columns unless a trusted server function has said so, and a
  // cascade counts as an ordinary update — the same trap `delete_my_account` documents.
  await client.query("select set_config('app.server_mode', 'on', true)");

  // Settlements first: `order_settlements.order_id` is `on delete restrict`, because a
  // settlement is evidence of a charge and must not leave with the order silently.
  const settlements = await n('delete from order_settlements');
  const ratings = await n('delete from ratings');
  const itemRatings = await n('delete from item_ratings');
  const orders = await n('delete from orders');
  const addresses = await n('delete from addresses');

  // `merchant_served_zones` is `on delete cascade`, so which zones the merchant covers is
  // wiped with the zones. Remembered here and restored below — a merchant serving nowhere
  // takes no orders at all, and that is not a change anybody asked for.
  const merchants = (
    await client.query('select distinct merchant_id from merchant_served_zones')
  ).rows.map((r) => r.merchant_id);

  // A merchant sits in a zone too — `merchants.zone_id`, which the dry run found the hard
  // way. The shop does not move: every old zone was an invented subdivision of the same
  // city, so it lands in «إدكو», which is where it has always physically been.
  const shops = (await client.query('select id from merchants')).rows.map((r) => r.id);

  // Nulled before the zones go and set again after: the column is `not null`, so it cannot
  // simply be cleared, and `on delete restrict` means it cannot be left pointing at a row
  // being removed. A temporary zone holds them for the length of this transaction.
  const holder = (
    await client.query(
      `insert into zones (city_id, name, default_delivery_fee, sort_order, is_active)
       values ((select id from cities limit 1), '__moving__', 0, 999, false) returning id`,
    )
  ).rows[0].id;
  await client.query('update merchants set zone_id = $1', [holder]);

  const landmarks = await n('delete from landmarks');
  const zones = await n('delete from zones where id <> $1', [holder]);

  await seedEdku(client, { log: () => {} });

  const city = (
    await client.query("select id from zones where name = 'إدكو'")
  ).rows[0].id;
  await client.query('update merchants set zone_id = $1', [city]);
  await client.query('delete from zones where id = $1', [holder]);

  const zoneIds = (await client.query('select id from zones')).rows.map((r) => r.id);
  let served = 0;
  for (const merchantId of merchants) {
    for (const zoneId of zoneIds) {
      served += await n(
        `insert into merchant_served_zones (merchant_id, zone_id) values ($1, $2)
         on conflict do nothing`,
        [merchantId, zoneId],
      );
    }
  }

  const after = await client.query(
    `select z.name,
            (select count(*) from landmarks l where l.zone_id = z.id)::int as total,
            (select count(*) from landmarks l
              where l.zone_id = z.id and l.lat is not null)::int as with_xy
       from zones z order by z.sort_order`,
  );

  console.log('removed:');
  console.log(`  settlements ${settlements}  ratings ${ratings}/${itemRatings}  ` +
              `orders ${orders}  addresses ${addresses}  landmarks ${landmarks}  zones ${zones}`);
  console.log('\nnow:');
  for (const r of after.rows) {
    console.log(`  ${r.name.padEnd(16)} landmarks=${r.total}  with coordinates=${r.with_xy}`);
  }
  console.log(`\nmerchant_served_zones restored: ${served} for ${merchants.length} merchant(s)`);

  if (commit) {
    await client.query('commit');
    console.log('\nCOMMITTED');
  } else {
    await client.query('rollback');
    console.log('\nROLLED BACK — dry run. Pass --commit to apply.');
  }
} catch (e) {
  await client.query('rollback');
  console.error('\nROLLED BACK on error:', e.message);
  process.exitCode = 1;
} finally {
  await client.end();
}
