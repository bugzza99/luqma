import { describe, it } from 'node:test';
import { deepStrictEqual } from 'node:assert';
import { freshDatabase } from './harness.mjs';

/**
 * Every table in `public` denies by default, and denies its owner too.
 *
 * The schema's opening loop does `enable` and `force` together over a fixed list of
 * names, under a comment saying new tables start denied and are opened deliberately.
 * Seven tables added in later migrations got `enable` alone, because the list is a list
 * and nothing read it back. That is the whole failure mode this file exists to end: the
 * invariant was written in a comment, and a comment is not a reader.
 *
 * `force` is the half that is easy to skip because skipping it looks harmless — a phone
 * connects as `anon` or `authenticated` and is never the owner, so nothing visibly
 * breaks. What breaks later is a `security definer` function, which runs as the owner and
 * would quietly bypass RLS on exactly the tables that missed it.
 *
 * Asserting over *every* table rather than a list means table thirty-one is covered the
 * day it is written, by a test nobody has to remember to update.
 */
describe('row level security', () => {
  it('is enabled and forced on every table in public', async () => {
    const db = await freshDatabase();

    const { rows } = await db.query(`
      select c.relname as table_name
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public'
         and c.relkind = 'r'
         and not (c.relrowsecurity and c.relforcerowsecurity)
       order by c.relname`);

    deepStrictEqual(
      rows.map((r) => r.table_name),
      [],
      'these tables have row level security missing or unforced',
    );
  });
});
