import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { freshDatabase } from './harness.mjs';

const actor = '00000000-0000-0000-0000-0000000000ad';
const second = '00000000-0000-0000-0000-0000000000ae';

let db;

before(async () => {
  db = await freshDatabase();
});

after(() => db?.close());

describe('changing staff access', () => {
  // With nobody left able to open AdminApp, the product has no path back to this screen.
  it('refuses to deactivate the last active platform admin', async () => {
    await assert.rejects(
      db.query('select set_staff_active($1, false, $1)', [actor]),
      /last active platform admin/,
    );

    const row = await db.query('select is_active from staff where uid = $1', [actor]);
    assert.equal(row.rows[0].is_active, true);
  });

  it('allows one admin to leave when another remains, and records who did it', async () => {
    await db.query('insert into auth.users (id) values ($1)', [second]);
    await db.query(
      "insert into staff (uid, scope, role) values ($1, 'platform', 'admin')",
      [second],
    );

    await db.query('select set_staff_active($1, false, $1)', [actor]);

    const row = await db.query('select is_active from staff where uid = $1', [actor]);
    assert.equal(row.rows[0].is_active, false);
    const audit = await db.query(
      "select actor, detail from audit_log where action = 'staff.active_changed'",
    );
    assert.equal(audit.rows[0].actor, actor);
    assert.equal(audit.rows[0].detail.uid, actor);
    assert.equal(audit.rows[0].detail.active, false);
  });
});
