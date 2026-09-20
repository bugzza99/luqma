// «زعتر» — the Deno wiring, and nothing else.
//
// Everything this function decides lives in `handler.js`, which is ordinary JavaScript so
// that `supabase/test/local/zaatar_counts_its_words.test.js` can run the real handler
// under `node --test`. Read the header of that file for what leaves the device and what
// does not; this one only supplies the three things Deno has and Node does not.
//
// Deploy note: this function verifies the caller's JWT itself, through GoTrue, so it is
// deployed the ordinary way — no `--no-verify-jwt`.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { createHandler } from './handler.js';

Deno.serve(
  createHandler({
    env: (name: string) => Deno.env.get(name),
    createClient,
    fetch: globalThis.fetch,
  }),
);
