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

  // A10. Dismissal took the whole account: `set-staff-active` banned the GoTrue user, so
  // a dismissed courier could no longer sign into CustomerApp, order, delete the account
  // or register the number again. The owner decided (2026-09-23) that a dismissal takes
  // the staff powers and leaves the person a customer. So the database ends the person's
  // sessions — the staff app has to sign in again and meets the no-access wall — and the
  // Edge Function no longer bans.
  it("a dismissal ends that person's sessions and nobody else's", async () => {
    const courier = '00000000-0000-0000-0000-0000000000c7';
    const bystander = '00000000-0000-0000-0000-0000000000c8';
    await db.query('insert into auth.users (id) values ($1), ($2)', [courier, bystander]);
    await db.query(
      "insert into staff (uid, scope, role) values ($1, 'platform', 'courier')", [courier]);
    await db.query(
      'insert into auth.sessions (user_id) values ($1), ($1), ($2)', [courier, bystander]);

    await db.query('select set_staff_active($1, false, $2)', [courier, second]);

    const left = async (uid) => (await db.query(
      'select count(*)::int n from auth.sessions where user_id = $1', [uid])).rows[0].n;
    assert.equal(await left(courier), 0);
    assert.equal(await left(bystander), 1);
    const account = await db.query('select id from auth.users where id = $1', [courier]);
    assert.equal(account.rows.length, 1, 'the account itself stays');
  });

  it('bringing somebody back ends nothing', async () => {
    const courier = '00000000-0000-0000-0000-0000000000c9';
    await db.query('insert into auth.users (id) values ($1)', [courier]);
    await db.query(
      "insert into staff (uid, scope, role, is_active) values ($1, 'platform', 'courier', false)",
      [courier]);
    await db.query('insert into auth.sessions (user_id) values ($1)', [courier]);

    await db.query('select set_staff_active($1, true, $2)', [courier, second]);

    const n = (await db.query(
      'select count(*)::int n from auth.sessions where user_id = $1', [courier])).rows[0].n;
    assert.equal(n, 1);
  });
});
