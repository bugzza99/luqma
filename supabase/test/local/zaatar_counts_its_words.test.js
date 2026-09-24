import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { freshDatabase } from './harness.mjs';
import { MAX_MESSAGE_CHARS, createHandler } from '../../functions/zaatar/handler.js';
import {
  CONTEXT_WORDS,
  INTENT_WORDS,
  PRECEDENCE,
  PREFIXES,
  SUFFIXES,
  TOPICS,
  classifyLocally,
  reduceToExcerpt,
} from '../../functions/zaatar/excerpt.js';

/** The one classification specification, as data. The Dart side reads this same file. */
const CORPUS = JSON.parse(
  readFileSync(new URL('../../../data/zaatar_corpus.json', import.meta.url), 'utf8'),
);

const CUSTOMER_1 = '00000000-0000-0000-0000-0000000000c1';
const CUSTOMER_2 = '00000000-0000-0000-0000-0000000000c2';

describe('zaatar counts its words abuse limit', () => {
  let db;

  const as = (uid, claims = {}) => db.exec(`
    create or replace function auth.uid() returns uuid language sql stable
      as $fn$ select ${uid ? `'${uid}'::uuid` : 'null::uuid'} $fn$;
    create or replace function auth.jwt() returns jsonb language sql stable
      as $fn$ select '${JSON.stringify({ app_metadata: claims })}'::jsonb $fn$;`);

  const role = async (r, fn) => {
    await db.exec(`set role ${r}`);
    try {
      return await fn();
    } finally {
      await db.exec('reset role');
    }
  };

  before(async () => {
    db = await freshDatabase();
    await db.exec(`
      insert into auth.users (id) values ('${CUSTOMER_1}'), ('${CUSTOMER_2}');
      grant usage on schema auth to anon, authenticated;
    `);
  });

  after(async () => {
    await db?.close();
  });

  it('refuses direct client read and write on zaatar_usage table', async () => {
    await as(CUSTOMER_1);
    await assert.rejects(
      role('authenticated', () => db.query('select * from public.zaatar_usage')),
      /permission denied/i,
    );
    await assert.rejects(
      role('authenticated', () =>
        db.query(
          'insert into public.zaatar_usage (uid, day, count) values ($1, current_date, 1)',
          [CUSTOMER_1],
        ),
      ),
      /permission denied/i,
    );
    await assert.rejects(
      role('anon', () => db.query('select * from public.zaatar_usage')),
      /permission denied/i,
    );
  });

  it('refuses unauthenticated callers executing zaatar_take_turn', async () => {
    await as(null);
    await assert.rejects(
      role('anon', () => db.query('select public.zaatar_take_turn()')),
      /permission denied/i,
    );
  });

  it('allows 40 turns per customer per day and returns false on the 41st', async () => {
    await as(CUSTOMER_1);

    for (let i = 1; i <= 40; i++) {
      const res = await role('authenticated', () =>
        db.query('select public.zaatar_take_turn() as allowed'),
      );
      assert.equal(res.rows[0].allowed, true, `turn ${i} should be allowed`);
    }

    const turn41 = await role('authenticated', () =>
      db.query('select public.zaatar_take_turn() as allowed'),
    );
    assert.equal(turn41.rows[0].allowed, false, 'turn 41 must return false');

    const turn42 = await role('authenticated', () =>
      db.query('select public.zaatar_take_turn() as allowed'),
    );
    assert.equal(turn42.rows[0].allowed, false, 'turn 42 must return false');
  });

  it('tracks turns separately for different customers', async () => {
    await as(CUSTOMER_2);

    const res = await role('authenticated', () =>
      db.query('select public.zaatar_take_turn() as allowed'),
    );
    assert.equal(res.rows[0].allowed, true, 'first turn for customer 2 should be allowed');

    const check = await db.query(
      'select count from public.zaatar_usage where uid = $1',
      [CUSTOMER_2],
    );
    assert.equal(check.rows.length, 1);
    assert.equal(check.rows[0].count, 1);
  });

  // A counter nobody reads after the day it counts, kept for ever on a 500 MB tier, is
  // the `push_outbox` lesson again. The nightly cron calls this; PGlite has no pg_cron,
  // so what is proved here is the statement the job runs.
  it('prunes turn counts older than sixty days and keeps the rest', async () => {
    await db.exec(`
      insert into public.zaatar_usage (uid, day, count) values
        ('${CUSTOMER_1}', (now() at time zone 'Africa/Cairo')::date - 400, 7),
        ('${CUSTOMER_1}', (now() at time zone 'Africa/Cairo')::date - 61, 3),
        ('${CUSTOMER_1}', (now() at time zone 'Africa/Cairo')::date - 59, 2)
      on conflict (uid, day) do nothing;
    `);

    const removed = await db.query('select public.prune_zaatar_usage() as removed');
    assert.equal(removed.rows[0].removed, 2, 'both rows past sixty days, and only those');

    const left = await db.query(
      `select day from public.zaatar_usage
        where uid = $1 and day < (now() at time zone 'Africa/Cairo')::date - 60`,
      [CUSTOMER_1],
    );
    assert.equal(left.rows.length, 0);

    const recent = await db.query(
      `select count(*)::int as rows from public.zaatar_usage
        where uid = $1 and day >= (now() at time zone 'Africa/Cairo')::date - 60`,
      [CUSTOMER_1],
    );
    assert.ok(recent.rows[0].rows >= 2, 'yesterday and today are still counted');
  });

  it('refuses a client calling the prune itself', async () => {
    await as(CUSTOMER_1);
    await assert.rejects(
      role('authenticated', () => db.query('select public.prune_zaatar_usage()')),
      /permission denied/i,
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────────────────
// The handler itself.
//
// These drive `createHandler` — the function that actually runs in production — rather
// than a payload assembled in the test. That is the point: the previous version of this
// feature referenced three helpers that did not exist, so every single response threw,
// and the only test of the outbound payload built that payload itself and therefore
// passed. A test that constructs what it then asserts about proves nothing about the
// thing deployed.
// ─────────────────────────────────────────────────────────────────────────────────────

/** A uuid, because `orders.id` is one and the handler refuses anything that is not. */
const ORDER_ID = '00000000-0000-0000-0000-00000000dd01';

const ORDER = Object.freeze({
  id: ORDER_ID,
  customer_uid: CUSTOMER_1,
  status: 'outForDelivery',
  delivery_by: 'merchant',
  items: [{ name: 'كشري' }, { name: 'عصير' }],
});

/** A Supabase client that honours the two `eq` filters the handler relies on. */
function fakeSupabase(options = {}) {
  const { uid = CUSTOMER_1, order = ORDER } = options;
  // Read by key rather than by a default parameter, because `undefined` is one of the
  // answers being tested — a function that returns nothing — and a default would quietly
  // turn it into the granted turn this is asking about.
  const turnAllowed = 'turnAllowed' in options ? options.turnAllowed : true;
  const seen = { rpcCalls: 0, filters: [] };

  const createClient = () => ({
    auth: {
      getUser: async (token) =>
        token === 'good-token'
          ? { data: { user: { id: uid } }, error: null }
          : { data: null, error: { message: 'invalid JWT' } },
    },
    from: () => {
      const filters = {};
      const builder = {
        select: () => builder,
        eq: (column, value) => {
          filters[column] = value;
          return builder;
        },
        maybeSingle: async () => {
          seen.filters.push({ ...filters });
          const match =
            order &&
            order.id === filters.id &&
            order.customer_uid === filters.customer_uid;
          return { data: match ? order : null, error: null };
        },
      };
      return builder;
    },
    rpc: async () => {
      seen.rpcCalls += 1;
      return { data: turnAllowed, error: null };
    },
  });

  return { createClient, seen };
}

/** A Gemini stand-in that records every outbound body. */
function fakeGemini(respond) {
  const bodies = [];
  const fetchImpl = async (url, init) => {
    bodies.push(String(init?.body ?? ''));
    return respond(url, init);
  };
  return { fetchImpl, bodies };
}

function geminiReplying(intent) {
  return () =>
    new Response(
      JSON.stringify({
        candidates: [{ content: { parts: [{ text: JSON.stringify({ intent }) }] } }],
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );
}

const ENV = {
  SUPABASE_URL: 'https://example.supabase.co',
  SUPABASE_ANON_KEY: 'anon-key',
  GEMINI_API_KEY: 'gemini-key',
};

function ask(handler, { token = 'good-token', body = {}, method = 'POST' } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  return handler(
    new Request('https://edge.local/zaatar', {
      method,
      headers,
      body: method === 'POST' ? JSON.stringify(body) : undefined,
    }),
  );
}

function build({ supabase = fakeSupabase(), gemini = fakeGemini(geminiReplying('late')), env = ENV } = {}) {
  const handler = createHandler({
    env: (name) => env[name],
    createClient: supabase.createClient,
    fetch: gemini.fetchImpl,
  });
  return { handler, supabase, gemini };
}

/** A message with two intent families in it: the only kind that reaches the model. */
const AMBIGUOUS = 'الطلب اتأخر وعاوز ألغي';
// Without a model it reads as the family first in PRECEDENCE (2026-09-24). It used to read
// as «حاجة تانية», and «حاجة تانية» sent every such customer to a person.
const AMBIGUOUS_LOCALLY = 'cancel';

describe('zaatar the handler', () => {
  it('answers OPTIONS with the CORS headers instead of throwing', async () => {
    const { handler } = build();
    const res = await ask(handler, { method: 'OPTIONS', token: null });

    assert.equal(res.status, 200);
    assert.equal(res.headers.get('Access-Control-Allow-Origin'), '*');
    assert.match(res.headers.get('Access-Control-Allow-Headers'), /authorization/);
  });

  it('refuses a request with no bearer token', async () => {
    const { handler, supabase } = build();
    const res = await ask(handler, { token: null, body: { orderId: ORDER_ID, message: 'فين' } });

    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: 'unauthorized' });
    assert.equal(supabase.seen.filters.length, 0, 'no order may be read without a caller');
  });

  it('refuses a token GoTrue does not recognise', async () => {
    const { handler } = build();
    const res = await ask(handler, {
      token: 'forged',
      body: { orderId: ORDER_ID, message: 'فين الطلب' },
    });

    assert.equal(res.status, 401);
    assert.deepEqual(await res.json(), { error: 'unauthorized' });
  });

  it('refuses a request with no order id or no message', async () => {
    const { handler } = build();
    assert.equal((await ask(handler, { body: { message: 'فين' } })).status, 400);
    assert.equal((await ask(handler, { body: { orderId: ORDER_ID } })).status, 400);
    assert.equal((await ask(handler, { body: { orderId: ORDER_ID, message: '   ' } })).status, 400);
  });

  it('refuses another customer order id and never answers about it', async () => {
    const { handler, supabase } = build({ supabase: fakeSupabase({ uid: CUSTOMER_2 }) });
    const res = await ask(handler, {
      body: { orderId: ORDER_ID, message: 'فين الطلب' },
    });

    assert.equal(res.status, 404);
    assert.deepEqual(await res.json(), { error: 'notFound' });
    assert.deepEqual(
      supabase.seen.filters,
      [{ id: ORDER_ID, customer_uid: CUSTOMER_2 }],
      'the caller uid must be part of the query, not merely checked afterwards',
    );
  });

  it('reads a plain question itself and spends no turn on it', async () => {
    const { handler, supabase, gemini } = build();
    const res = await ask(handler, {
      body: { orderId: ORDER_ID, message: 'الطلب اتأخر ليه؟' },
    });

    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { intent: 'late', source: 'local' });
    assert.equal(gemini.bodies.length, 0, 'no model call');
    assert.equal(supabase.seen.rpcCalls, 0, 'no turn taken');
  });

  it('sends a name and an address to nobody', async () => {
    const { handler, gemini } = build();
    const res = await ask(handler, {
      body: {
        orderId: ORDER_ID,
        message: `${AMBIGUOUS}، أنا محمد حسن من شارع البحر جنب مسجد النور`,
      },
    });

    assert.equal(res.status, 200);
    assert.equal(gemini.bodies.length, 1, 'this one is ambiguous, so it does go out');

    const sent = gemini.bodies[0];
    for (const personal of ['محمد', 'حسن', 'شارع', 'البحر', 'مسجد', 'النور']) {
      assert.ok(!sent.includes(personal), `«${personal}» must not leave the function`);
    }
    // And what did go is the allowlisted words and the three facts, nothing else.
    assert.ok(sent.includes('اتاخر'));
    assert.ok(sent.includes('outForDelivery'));
    assert.ok(!sent.includes('كشري'), 'item names are not sent either');
  });

  it('answers a message that is only a name and an address locally', async () => {
    const { handler, gemini, supabase } = build();
    const res = await ask(handler, {
      body: { orderId: ORDER_ID, message: 'deliver to ahmed ali, 12 el bahr, edku' },
    });

    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { intent: 'other', source: 'local' });
    assert.equal(gemini.bodies.length, 0, 'nothing in it can be reduced safely');
    assert.equal(supabase.seen.rpcCalls, 0);
  });

  it('strips Arabic-Indic digits rather than forwarding them', async () => {
    const { handler, gemini } = build();
    const res = await ask(handler, {
      body: { orderId: ORDER_ID, message: `${AMBIGUOUS} ورقمي ٠١٠١٢٣٤٥٦٧٨` },
    });

    assert.equal(res.status, 200);
    assert.equal(gemini.bodies.length, 1);
    const sent = gemini.bodies[0];
    assert.ok(!sent.includes('٠١٠'), 'not as typed');
    assert.ok(!sent.includes('0101'), 'and not normalised either');
    assert.ok(!/\d{5,}/.test(sent), 'no long run of digits at all');
  });

  it('keeps the local reading when the model fails', async () => {
    const failing = fakeGemini(() => {
      throw new Error('upstream is down');
    });
    const { handler } = build({ gemini: failing });
    const res = await ask(handler, {
      body: { orderId: ORDER_ID, message: AMBIGUOUS },
    });

    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { intent: AMBIGUOUS_LOCALLY, source: 'local' });
  });

  it('keeps the local reading when the model answers with something else', async () => {
    const odd = fakeGemini(
      () =>
        new Response(
          JSON.stringify({
            candidates: [{ content: { parts: [{ text: '{"intent":"refundEverything"}' }] } }],
          }),
          { status: 200 },
        ),
    );
    const { handler } = build({ gemini: odd });
    const res = await ask(handler, { body: { orderId: ORDER_ID, message: AMBIGUOUS } });

    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { intent: AMBIGUOUS_LOCALLY, source: 'local' });
  });

  it('takes the chosen intent when the model answers properly', async () => {
    const { handler, supabase } = build({ gemini: fakeGemini(geminiReplying('cancel')) });
    const res = await ask(handler, { body: { orderId: ORDER_ID, message: AMBIGUOUS } });

    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { intent: 'cancel', source: 'model' });
    assert.equal(supabase.seen.rpcCalls, 1, 'exactly one turn for one model call');
  });

  it('stops calling the model once the daily limit is spent, and still answers', async () => {
    const { handler, gemini } = build({
      supabase: fakeSupabase({ turnAllowed: false }),
    });
    const res = await ask(handler, { body: { orderId: ORDER_ID, message: AMBIGUOUS } });

    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { intent: AMBIGUOUS_LOCALLY, source: 'local' });
    assert.equal(gemini.bodies.length, 0, 'the limit is refused before the model, not after');
  });

  // The quota used to be skipped on an explicit `false` alone, so a reply carrying
  // anything else — a null from a shape change in PostgREST, a future `void` — read as
  // permission and the cap became unlimited without a single test failing.
  it('treats a quota reply that is not a plain yes as a no', async () => {
    for (const answer of [null, undefined, 'true', 0]) {
      const { handler, gemini } = build({
        supabase: fakeSupabase({ turnAllowed: answer }),
      });
      const res = await ask(handler, { body: { orderId: ORDER_ID, message: AMBIGUOUS } });

      assert.equal(res.status, 200);
      assert.deepEqual(await res.json(), { intent: AMBIGUOUS_LOCALLY, source: 'local' });
      assert.equal(
        gemini.bodies.length,
        0,
        `«${String(answer)}» is not a granted turn and must not buy a model call`,
      );
    }
  });

  it('answers locally rather than failing when no model is configured', async () => {
    const { handler, gemini } = build({
      env: { SUPABASE_URL: ENV.SUPABASE_URL, SUPABASE_ANON_KEY: ENV.SUPABASE_ANON_KEY },
    });
    const res = await ask(handler, { body: { orderId: ORDER_ID, message: AMBIGUOUS } });

    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { intent: AMBIGUOUS_LOCALLY, source: 'local' });
    assert.equal(gemini.bodies.length, 0);
  });

  it('fails safe to a fallback the app can answer around', async () => {
    const handler = createHandler({
      env: () => {
        throw new Error('the environment is on fire');
      },
      createClient: () => {},
    });
    const res = await ask(handler, { body: { orderId: ORDER_ID, message: AMBIGUOUS } });

    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { fallback: true });
  });
});

describe('zaatar the excerpt is an allowlist', () => {
  it('lets no unknown word through, whatever it is', () => {
    assert.equal(reduceToExcerpt('وصل الطلب لمحمد حسن عند مسجد النور'), 'وصل الطلب');
    assert.equal(reduceToExcerpt('deliver to ahmed ali, 12 el bahr, edku'), '');
    assert.equal(reduceToExcerpt('01012345678'), '');
    assert.equal(reduceToExcerpt('ahmed@example.com https://x.test/y'), '');
  });

  it('folds the spellings of one word onto one entry', () => {
    assert.equal(reduceToExcerpt('إلغاء'), reduceToExcerpt('الغاء'));
    assert.equal(classifyLocally('عايز إلغاء').topic, 'cancel');
    assert.equal(classifyLocally('عايز الغاء').topic, 'cancel');
  });

  it('caps what can leave however long the message is', () => {
    const long = Array(80).fill('الطلب المطعم المندوب الاكل بارد وحش مشكله شكوي اسف ساعه دقيقه يوم كمان').join(' ');
    assert.ok(reduceToExcerpt(long).split(' ').length <= 12);
  });

  it('calls one family decisive and two families a question for the model', () => {
    assert.deepEqual(classifyLocally('الطلب اتأخر جداً'), { topic: 'late', decisive: true });
    assert.deepEqual(classifyLocally('الطلب اتأخر وعاوز ألغي'), {
      topic: 'cancel',
      decisive: false,
    });
    assert.deepEqual(classifyLocally('السلام عليكم'), { topic: 'hello', decisive: true });
  });

  // `token in INTENT_WORDS` walks the prototype chain, so every object in JavaScript
  // already "has" these three. They were vocabulary nobody wrote, and the second of the
  // two boundaries this file exists to hold.
  it('does not treat an inherited property as a word', () => {
    assert.equal(reduceToExcerpt('constructor الغي ناقص'), 'الغي ناقص');
    assert.equal(reduceToExcerpt('constructor'), '');
    assert.equal(reduceToExcerpt('toString hasOwnProperty valueOf'), '');
  });

  it('nor as a topic', () => {
    // Before `Object.hasOwn` this answered with the `Object` constructor as the topic:
    // truthy, so «decisive», and a function, so `JSON.stringify` dropped the key and the
    // phone received a reply with no intent in it at all.
    assert.deepEqual(classifyLocally('constructor'), { topic: 'other', decisive: false });
    assert.deepEqual(classifyLocally('constructor الغي'), { topic: 'cancel', decisive: true });
    assert.deepEqual(classifyLocally('constructor الغي ناقص'), {
      topic: 'cancel',
      decisive: false,
    });
  });

  it('never answers with a topic outside HelpTopic', () => {
    for (const message of CORPUS.cases.map((c) => c.message)) {
      const { topic } = classifyLocally(message);
      assert.ok(
        TOPICS.includes(topic),
        `«${message}» produced ${String(topic)}`,
      );
    }
  });
});

// ─────────────────────────────────────────────────────────────────────────────────────
// Parity with the phone.
//
// `ZaatarClassifier` in `packages/luqma_core` is the specification and this function is
// its port, because a phone with no connection still has to read the message. They were
// written independently once and disagreed: «السعر» was money here and «حاجة تانية»
// there, «لسه عاوز ألغي» was cancel here and «اتأخر» there — so the answer a customer
// read depended on which failure they had hit.
//
// `data/zaatar_corpus.json` is what both are run against. The Dart half of this is
// `packages/luqma_core/test/zaatar_classifier_test.dart`, reading the same file.
// ─────────────────────────────────────────────────────────────────────────────────────

describe('zaatar one classification specification', () => {
  it('reads every message in the shared corpus the way the corpus says', () => {
    for (const { message, topic, decisive, note } of CORPUS.cases) {
      assert.deepEqual(
        classifyLocally(message),
        { topic, decisive },
        `«${message}»${note ? ` — ${note}` : ''}`,
      );
    }
  });

  it('carries exactly the affixes and the precedence in the shared corpus', () => {
    assert.deepEqual([...PREFIXES], CORPUS.prefixes);
    assert.deepEqual([...SUFFIXES], CORPUS.suffixes);
    assert.deepEqual([...PRECEDENCE], CORPUS.precedence);
  });

  // A stem found inside a word is sent as the vocabulary's own spelling, never as what
  // the customer typed: the excerpt stays an allowlist.
  it('sends the vocabulary word a stem found, not the word typed', () => {
    assert.equal(reduceToExcerpt('الأكل لسه موصلش'), 'الاكل لسه وصل');
  });

  it('carries exactly the vocabulary in the shared corpus', () => {
    assert.deepEqual({ ...INTENT_WORDS }, CORPUS.intentWords);
    assert.deepEqual([...CONTEXT_WORDS].sort(), [...CORPUS.contextWords].sort());
  });
});

// ─────────────────────────────────────────────────────────────────────────────────────
// What the handler will read at all. Everything below the body read — normalising,
// tokenising, the order query, the quota — costs memory or a round trip proportional to
// what the caller sent, and the app's own 500-character field is not a limit on anybody
// who is not using the app.
// ─────────────────────────────────────────────────────────────────────────────────────

describe('zaatar the handler bounds what it reads', () => {
  it('refuses a body larger than the cap without parsing it', async () => {
    const { handler, supabase, gemini } = build();
    const res = await ask(handler, {
      body: { orderId: ORDER_ID, message: 'ا'.repeat(20000) },
    });

    assert.equal(res.status, 413);
    assert.deepEqual(await res.json(), { error: 'tooLarge' });
    assert.equal(supabase.seen.filters.length, 0, 'no order read');
    assert.equal(gemini.bodies.length, 0);
  });

  it('refuses a message past the field limit even inside a small body', async () => {
    const { handler, supabase } = build();
    const res = await ask(handler, {
      body: { orderId: ORDER_ID, message: 'a'.repeat(MAX_MESSAGE_CHARS + 1) },
    });

    assert.equal(res.status, 400);
    assert.deepEqual(await res.json(), { error: 'tooLong' });
    assert.equal(supabase.seen.filters.length, 0, 'refused before the query');
  });

  it('accepts a message exactly at the field limit', async () => {
    const { handler } = build();
    const res = await ask(handler, {
      body: { orderId: ORDER_ID, message: `فين الطلب ${'a'.repeat(MAX_MESSAGE_CHARS - 11)}` },
    });

    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { intent: 'late', source: 'local' });
  });

  it('refuses an order id that is not a uuid before querying anything', async () => {
    const { handler, supabase } = build();
    const res = await ask(handler, {
      body: { orderId: 'order-1; drop table orders', message: 'فين الطلب' },
    });

    assert.equal(res.status, 400);
    assert.deepEqual(await res.json(), { error: 'badRequest' });
    assert.equal(supabase.seen.filters.length, 0, 'the database is never asked');
  });
});
