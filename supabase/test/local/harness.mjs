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
    create schema if not exists auth;
    create table auth.users (id uuid primary key default gen_random_uuid());

    -- The token here always says admin, deliberately.
    --
    -- These tests are about constraints, and a constraint can only be tested by a writer
    -- the boundary lets through: the column guards are BEFORE UPDATE triggers, which a
    -- superuser does not bypass, so an anonymous stub would stop every write at the
    -- boundary and no CHECK would ever be reached. Whether the boundary itself holds is a
    -- different question, asked in test/stack against real tokens.
    create or replace function auth.uid() returns uuid
      language sql stable as $fn$ select null::uuid $fn$;
    create or replace function auth.jwt() returns jsonb
      language sql stable as
      $fn$ select '{"app_metadata":{"admin":true}}'::jsonb $fn$;

    -- The three roles the policies grant to. service_role is the server: it bypasses RLS
    -- on the real stack, and here it only needs to exist for the grants to land.
    create role anon;
    create role authenticated;
    create role service_role;
  `);

  // Every migration, in order — the same thing `supabase db reset` does, so one added
  // later is picked up here without anybody remembering to.
  const dir = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'migrations');
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
    await db.exec(readFileSync(join(dir, file), 'utf8'));
  }

  return db;
}
