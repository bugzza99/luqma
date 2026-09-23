import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Client } from 'pg';

/**
 * A8. An upload is counted where it lands.
 *
 * The rate limit counted `public.media` rows, and the bytes go to `storage.objects`
 * first; `media_upload` asked only that the path start with the caller's uid. A script
 * with any account could fill the public bucket without writing a row. The insert
 * policies now count the caller's objects in the last hour.
 *
 * Inserted straight into `storage.objects` as the caller, the way the policy sees an
 * upload through the Storage API. One statement sees the table as it stood when it
 * began, so the allowance is filled in one statement and the next one is refused.
 */

const DB = process.env.DATABASE_URL
  ?? 'postgresql://postgres:postgres@127.0.0.1:55322/postgres';

let db;
const q = (sql, params) => db.query(sql, params);

async function as(uid, fn) {
  await q('begin');
  try {
    await q("select set_config('role','authenticated',true)");
    await q("select set_config('request.jwt.claims',$1,true)",
      [JSON.stringify({ sub: uid, role: 'authenticated', app_metadata: {} })]);
    return await fn();
  } finally {
    await q('rollback');
  }
}

const refused = (error) => {
  assert.equal(error.code, '42501', `expected 42501, got ${error.code}: ${error.message}`);
  return true;
};

describe('an upload is counted where it lands', () => {
  let person, perHour;

  before(async () => {
    db = new Client({ connectionString: DB });
    await db.connect();
    person = (await q(
      "insert into auth.users (id, instance_id, aud, role) values (gen_random_uuid(), "
      + "'00000000-0000-0000-0000-000000000000','authenticated','authenticated') returning id",
    )).rows[0].id;
    perHour = (await q('select public.media_uploads_per_hour() as n')).rows[0].n;
  });

  after(async () => {
    await q('delete from auth.users where id = $1', [person]).catch(() => {});
    await db.end();
  });

  const put = (bucket, count) => q(
    `insert into storage.objects (bucket_id, name, owner_id)
     select $1, $2 || '/' || gen_random_uuid() || '.jpg', $2
       from generate_series(1, $3)`, [bucket, person, count]);

  it('a picture within the hour is taken', () => as(person, () => put('media', 1)));

  it('the one past the hour\'s allowance is refused', () => assert.rejects(
    as(person, async () => { await put('media', perHour); await put('media', 1); }),
    refused));

  it('papers have an allowance of their own', () => assert.rejects(
    as(person, async () => { await put('staff-docs', 12); await put('staff-docs', 1); }),
    refused));

  it('the path still has to be the uploader\'s own', () => assert.rejects(
    as(person, () => q(
      `insert into storage.objects (bucket_id, name, owner_id)
       values ('media', gen_random_uuid() || '/x.jpg', $1)`, [person])),
    refused));
});
