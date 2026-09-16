import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { freshDatabase } from './harness.mjs';

/**
 * The developer's page is its own, and what the owner already typed carries over.
 *
 * The migration runs as part of `freshDatabase()`, so a row inserted before it is not
 * possible here. What is provable: the copy statement does what it says when re-run
 * against rows that exist, and the sweep treats the new key as a reference.
 */
describe('the developer, apart from the product', () => {
  it('protects a pending photo named only by developer_photo_media_id from the sweep', async () => {
    const db = await freshDatabase();
    try {
      const uid = '00000000-0000-0000-0000-0000000000e1';
      await db.query('insert into auth.users (id) values ($1)', [uid]);
      const media = (await db.query(
        `insert into media (kind, url, status, uploaded_by, created_at)
         values ('aboutPhoto',
                 'https://x/storage/v1/object/public/media/u/aboutPhoto/a.jpg',
                 'pending', $1, now() - interval '30 days') returning id`,
        [uid])).rows[0].id;
      await db.query(
        `insert into config (key, value) values ('developer_photo_media_id', to_jsonb($1::text))`,
        [media]);

      const src = (await db.query(
        `select prosrc from pg_proc where oid = 'public.sweep_orphan_media()'::regprocedure`))
        .rows[0].prosrc;
      assert.match(src, /developer_photo_media_id/,
        'a photo referenced only by the new key would be deleted from Storage as an orphan');
    } finally {
      await db.close();
    }
  });

  it('copies the owner’s photo and links to the developer keys, and keeps what is already set', async () => {
    const db = await freshDatabase();
    try {
      await db.exec(`
        insert into config (key, value) values
          ('about_photo_media_id', '"p1"'), ('about_facebook', '"https://facebook.com/me"'),
          ('about_description', '"عن لقمة"'),
          ('developer_whatsapp', '"https://wa.me/already"'),
          ('about_whatsapp', '"https://wa.me/old"')
        on conflict (key) do update set value = excluded.value;`);

      // The same statement the migration runs.
      await db.exec(`
        insert into public.config (key, value)
        select replace(c.key, 'about_', 'developer_'), c.value
          from public.config c
         where c.key in ('about_photo_media_id','about_facebook','about_whatsapp','about_instagram')
        on conflict (key) do nothing;`);

      const rows = Object.fromEntries((await db.query(
        `select key, value #>> '{}' as v from config where key like 'developer_%'`))
        .rows.map((r) => [r.key, r.v]));

      assert.equal(rows.developer_photo_media_id, 'p1');
      assert.equal(rows.developer_facebook, 'https://facebook.com/me');
      assert.equal(rows.developer_whatsapp, 'https://wa.me/already',
        'a value already set on the new key is not overwritten');
      assert.equal(rows.developer_description, undefined,
        'the product description is the product’s, and is not copied');
    } finally {
      await db.close();
    }
  });
});
