import { describe, it } from 'node:test';
import { strictEqual, ok, deepStrictEqual } from 'node:assert';
import { freshDatabase } from './harness.mjs';

/**
 * Four defects a review found in code that had been green for weeks.
 *
 * None of them is exotic. Each is a statement that is correct for the case somebody had
 * in mind and wrong for a case nobody wrote down: one city, a list that is there, a
 * column that is only ever inserted. They are together because they share that shape,
 * not because they share a file.
 */

describe('reordering the home touches one city', () => {
  // `home_sections` is keyed `(key, city_id)` — the same `key` exists once per city, by
  // design. `reorder_home_sections(p_keys)` matched on `key` alone, so arranging Edku's
  // home rearranged every other city's too. Edku is the only city today, which is
  // precisely why this could sit here: there is no second city to notice.
  const setup = async () => {
    const db = await freshDatabase();
    await db.query(`insert into cities (id, name) values ('edku','إدكو'), ('rashid','رشيد')`);
    for (const city of ['edku', 'rashid']) {
      await db.query(
        `insert into home_sections (key, city_id, type, sort_order)
         values ('banner',$1,'adSlot',0), ('kitchens',$1,'dailyMeals',1)`, [city]);
    }
    return db;
  };

  const order = async (db, city) => (await db.query(
    `select key from home_sections where city_id = $1 order by sort_order`, [city]
  )).rows.map((r) => r.key);

  it('the city that was asked for is reordered', async () => {
    const db = await setup();
    await db.query(`select reorder_home_sections(array['kitchens','banner'], 'edku')`);
    deepStrictEqual(await order(db, 'edku'), ['kitchens', 'banner']);
    await db.close();
  });

  it('and no other city moves', async () => {
    const db = await setup();
    await db.query(`select reorder_home_sections(array['kitchens','banner'], 'edku')`);
    deepStrictEqual(await order(db, 'rashid'), ['banner', 'kitchens'],
      'Rashid did not ask to be rearranged');
    await db.close();
  });
});

describe('replacing a menu with nothing', () => {
  // `jsonb_array_elements(null)` returns no rows rather than raising, so
  // `not exists (select 1 from jsonb_array_elements(p_categories) …)` was true of every
  // category the merchant had. A call that forgot its argument deleted the whole menu
  // and reported success.
  const setup = async () => {
    const db = await freshDatabase();
    await db.query(`insert into cities (id,name) values ('edku','إدكو')`);
    const zone = (await db.query(
      `insert into zones (city_id,name,default_delivery_fee) values ('edku','منطقة',1000)
       returning id`)).rows[0].id;
    const merchant = (await db.query(
      `insert into merchants (city_id,type,name,zone_id,phone,status)
       values ('edku','restaurant','مطعم',$1,'0100','approved') returning id`,
      [zone])).rows[0].id;
    await db.query(
      `insert into menu_categories (merchant_id,name,sort_order)
       values ($1,'أطباق',0), ($1,'مشروبات',1)`, [merchant]);
    return { db, merchant };
  };

  const count = async (db, merchant) => Number((await db.query(
    `select count(*) c from menu_categories where merchant_id = $1`, [merchant]
  )).rows[0].c);

  it('a null list is refused, not obeyed', async () => {
    const { db, merchant } = await setup();
    let code = null;
    try {
      await db.query(`select save_menu_categories($1::uuid, null::jsonb)`, [merchant]);
    } catch (e) { code = e.code; }
    strictEqual(code, 'P0001', 'it says what is wrong');
    strictEqual(await count(db, merchant), 2, 'and the menu is still there');
    await db.close();
  });

  it('something that is not a list is refused too', async () => {
    const { db, merchant } = await setup();
    let code = null;
    try {
      await db.query(`select save_menu_categories($1::uuid, '{"id":"x"}'::jsonb)`, [merchant]);
    } catch (e) { code = e.code; }
    strictEqual(code, 'P0001');
    strictEqual(await count(db, merchant), 2);
    await db.close();
  });

  it('an empty list still means empty — that is a real instruction', async () => {
    const { db, merchant } = await setup();
    await db.query(`select save_menu_categories($1::uuid, '[]'::jsonb)`, [merchant]);
    strictEqual(await count(db, merchant), 0,
      'clearing a menu on purpose is different from forgetting the argument');
    await db.close();
  });
});

describe('config carries an updated_at that means something', () => {
  // Every other table with the column got the trigger from one `foreach` list. `config`
  // was left out of that array, so its `updated_at` was the insert time for ever — a
  // column that answers a question wrongly rather than not at all.
  it('changing a value moves updated_at', async () => {
    const db = await freshDatabase();
    await db.query(`insert into config (key, value) values ('min_supported_version','"1.0.0"')`);
    await db.query(`update config set updated_at = now() - interval '1 day' where key = 'min_supported_version'`);
    const before = (await db.query(
      `select updated_at from config where key = 'min_supported_version'`)).rows[0].updated_at;

    await db.query(`update config set value = '"1.1.0"' where key = 'min_supported_version'`);
    const after = (await db.query(
      `select updated_at from config where key = 'min_supported_version'`)).rows[0].updated_at;

    ok(after > before, 'the trigger fired');
    await db.close();
  });
});
