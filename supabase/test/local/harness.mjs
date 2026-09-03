import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';

/**
 * A database that the real migrations have been applied to, with no Docker.
 *
 * PGlite is Postgres compiled to WebAssembly — the same planner, the same constraint
 * machinery, and the same DDL parser as the server. What it does not have is the part
 * Supabase adds: the `auth` schema, `auth.uid()`, `auth.jwt()`, and the `anon` and
 * `authenticated` roles the policies grant to.
 *
 * Those are stubbed below, and stubbed *thinly* on purpose: enough for the migrations to
 * apply unchanged, and no more. Anything that depends on what a token actually says is a
 * question about the boundary, and belongs in `test/stack/`, against the real thing.
 */
export async function freshDatabase() {
  const db = await new PGlite();

  await db.exec(`
    -- Storage lives in its own container, not in the migrations, so PGlite has no
    -- trace of it. Stubbed for the same reason auth is: the migrations that create the
    -- media bucket and its policies are real schema and must apply here unchanged,
    -- and without these two tables every one of them fails with "relation does not
    -- exist" -- which reads as a broken migration rather than a missing stub.
    create schema if not exists storage;
    create table storage.buckets (
      id text primary key,
      name text not null,
      public boolean not null default false,
      file_size_limit bigint,
      allowed_mime_types text[]
    );
    create table storage.objects (
      id uuid primary key default gen_random_uuid(),
      bucket_id text references storage.buckets,
      name text not null,
      owner uuid,
      created_at timestamptz not null default now()
    );

    create schema if not exists auth;
    -- raw_user_meta_data is here because ensure_user_profile reads it: a customer signs
    -- up with their name and phone in the signup metadata, and the trigger copies both
    -- onto the profile row. A stub without the column makes every insert into auth.users
    -- fail with "record new has no field", which reads as a schema problem rather than
    -- as a missing stub column.
    create table auth.users (
      id uuid primary key default gen_random_uuid(),
      raw_user_meta_data jsonb not null default '{}'::jsonb
    );

    -- The token here always says admin, deliberately. The fixed uid gets a matching
    -- active staff row after the migrations land, because claims alone are no longer an
    -- administrator and weakening that rule for PGlite would make the harness lie.
    --
    -- These tests are about constraints, and a constraint can only be tested by a writer
    -- the boundary lets through: the column guards are BEFORE UPDATE triggers, which a
    -- superuser does not bypass, so an anonymous stub would stop every write at the
    -- boundary and no CHECK would ever be reached. Whether the boundary itself holds is a
    -- different question, asked in test/stack against real tokens.
    create or replace function auth.uid() returns uuid
      language sql stable as
      $fn$ select '00000000-0000-0000-0000-0000000000ad'::uuid $fn$;
    create or replace function auth.jwt() returns jsonb
      language sql stable as
      $fn$ select '{"app_metadata":{"admin":true}}'::jsonb $fn$;

    -- The three roles the policies grant to. service_role is the server: it bypasses RLS
    -- on the real stack, and here it only needs to exist for the grants to land.
    create role anon;
    create role authenticated;
    create role service_role;

    -- The role GoTrue speaks as when it calls the access-token hook on sign-in.
    -- Nothing here ever signs in, but the grant to it must still land for the
    -- migrations to apply unchanged.
    create role supabase_auth_admin;
  `);

  // Every migration, in order — the same thing `supabase db reset` does, so one added
  // later is picked up here without anybody remembering to.
  const dir = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'migrations');
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
    await db.exec(readFileSync(join(dir, file), 'utf8'));
  }

  await db.exec(`
    insert into auth.users (id)
    values ('00000000-0000-0000-0000-0000000000ad')
    on conflict (id) do nothing;
    insert into staff (uid, scope, role)
    values ('00000000-0000-0000-0000-0000000000ad', 'platform', 'admin')
    on conflict (uid) do nothing;
  `);

  return db;
}
