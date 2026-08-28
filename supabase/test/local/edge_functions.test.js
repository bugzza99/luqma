import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { registerHooks } from 'node:module';
import { pathToFileURL } from 'node:url';

// The functions import Supabase through Deno's jsr: loader. Node can strip their
// TypeScript types itself; this hook replaces only that network import so the real
// handlers can be exercised with deterministic clients.
registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier.startsWith('jsr:@supabase/supabase-js@')) {
      return { url: 'mock:luqma-supabase', shortCircuit: true };
    }
    return nextResolve(specifier, context);
  },
  load(url, context, nextLoad) {
    if (url === 'mock:luqma-supabase') {
      return {
        format: 'module',
        shortCircuit: true,
        source: `export const createClient = (...args) =>
          globalThis.__luqmaCreateClient(...args);`,
      };
    }
    return nextLoad(url, context);
  },
});

const originalFetch = globalThis.fetch;
const functionEnv = new Map([
  ['SUPABASE_URL', 'https://example.supabase.co'],
  ['SUPABASE_ANON_KEY', 'anon-key'],
  ['SUPABASE_SERVICE_ROLE_KEY', 'service-key'],
]);

let served;
globalThis.Deno = {
  env: { get: (key) => functionEnv.get(key) },
  serve: (handler) => { served = handler; },
};

async function loadHandler(name) {
  served = undefined;
  const url = pathToFileURL(new URL(`../../functions/${name}/index.ts`, import.meta.url).pathname);
  await import(`${url.href}?unit-test=${name}`);
  assert.equal(typeof served, 'function', `${name} must register a handler`);
  return served;
}

const createStaff = await loadHandler('create-staff-account');
const resetPassword = await loadHandler('reset-customer-password');
const sendPush = await loadHandler('send-push');

afterEach(() => {
  globalThis.fetch = originalFetch;
  globalThis.__luqmaCreateClient = () => {
    throw new Error('unexpected Supabase client');
  };
  functionEnv.delete('LUQMA_CRON_SECRET');
  functionEnv.delete('LUQMA_FCM_SERVICE_ACCOUNT');
});

function request(body, { token = 'caller-token', raw = false, method = 'POST' } = {}) {
  const headers = new Headers();
  if (token !== null) headers.set('Authorization', `Bearer ${token}`);
  if (body !== undefined) headers.set('Content-Type', 'application/json');
  return new Request('https://functions.local/unit-test', {
    method,
    headers,
    body: body === undefined ? undefined : raw ? body : JSON.stringify(body),
  });
}

async function expectJson(response, status, body) {
  assert.equal(response.status, status);
  assert.deepEqual(await response.json(), body);
}

function query(result) {
  return {
    select() { return this; },
    eq() { return this; },
    async maybeSingle() { return result; },
  };
}

function staffClients(options = {}) {
  const calls = { created: [], inserted: [], deleted: [], merchantReads: 0 };
  const caller = options.caller === undefined
    ? { scope: 'platform', role: 'admin', is_active: true }
    : options.caller;

  const anon = {
    auth: {
      getUser: async () => options.userResult ?? {
        data: { user: { id: 'admin-uid' } },
        error: null,
      },
    },
  };
  const service = {
    auth: {
      admin: {
        createUser: async (payload) => {
          calls.created.push(payload);
          return options.createResult ?? {
            data: { user: { id: 'new-staff-uid' } },
            error: null,
          };
        },
        deleteUser: async (uid) => { calls.deleted.push(uid); },
      },
    },
    from(table) {
      if (table === 'staff') {
        return {
          ...query({ data: caller, error: options.callerError ?? null }),
          insert: async (row) => {
            calls.inserted.push(row);
            return { error: options.staffError ?? null };
          },
        };
      }
      if (table === 'merchants') {
        calls.merchantReads++;
        const merchant = Object.hasOwn(options, 'merchant')
          ? options.merchant
          : { id: 'merchant-1' };
        return query({ data: merchant, error: null });
      }
      throw new Error(`unexpected table ${table}`);
    },
  };
  globalThis.__luqmaCreateClient = (_url, key) => key === 'anon-key' ? anon : service;
  return calls;
}

const validStaff = {
  email: ' Cook@Example.COM ',
  password: 'password8',
  name: '  أميرة  ',
  scope: 'merchant',
  role: 'owner',
  merchantId: ' merchant-1 ',
};

describe('create-staff-account', () => {
  it('answers preflight without creating a client', async () => {
    const response = await createStaff(request(undefined, { method: 'OPTIONS', token: null }));

    assert.equal(response.status, 200);
    assert.equal(await response.text(), 'ok');
    assert.equal(response.headers.get('access-control-allow-methods'), 'POST, OPTIONS');
  });

  it('rejects a missing or unverifiable bearer token', async () => {
    await expectJson(await createStaff(request({}, { token: null })), 401, {
      error: 'unauthorized',
    });

    staffClients({ userResult: { data: { user: null }, error: new Error('bad jwt') } });
    await expectJson(await createStaff(request({})), 401, { error: 'unauthorized' });
  });

  it('requires an active platform admin before reading the body', async () => {
    for (const caller of [
      null,
      { scope: 'merchant', role: 'admin', is_active: true },
      { scope: 'platform', role: 'moderator', is_active: true },
      { scope: 'platform', role: 'admin', is_active: false },
    ]) {
      staffClients({ caller });
      await expectJson(await createStaff(request('{', { raw: true })), 403, {
        error: 'forbidden',
      });
    }
  });

  it('rejects malformed JSON and invalid account fields', async () => {
    staffClients();
    await expectJson(await createStaff(request('{', { raw: true })), 400, {
      error: 'badRequest',
    });

    for (const patch of [
      { email: 'not-an-email' },
      { password: 'short' },
      { scope: 'unknown' },
      { role: 'customer' },
    ]) {
      staffClients();
      await expectJson(await createStaff(request({ ...validStaff, ...patch })), 400, {
        error: 'badRequest',
      });
    }
  });

  it('enforces the merchant relationship in both directions', async () => {
    staffClients();
    await expectJson(
      await createStaff(request({ ...validStaff, merchantId: '   ' })),
      400,
      { error: 'badRequest' },
    );

    staffClients();
    await expectJson(
      await createStaff(request({
        ...validStaff,
        scope: 'platform',
        role: 'moderator',
      })),
      400,
      { error: 'badRequest' },
    );
  });

  it('refuses a merchant account whose merchant does not exist', async () => {
    const calls = staffClients({ merchant: null });

    await expectJson(await createStaff(request(validStaff)), 400, {
      error: 'noSuchMerchant',
    });
    assert.equal(calls.created.length, 0);
  });

  it('normalizes fields and creates the auth user before its staff row', async () => {
    const calls = staffClients();

    await expectJson(await createStaff(request(validStaff)), 200, {
      uid: 'new-staff-uid',
    });
    assert.deepEqual(calls.created, [{
      email: 'cook@example.com',
      password: 'password8',
      email_confirm: true,
      user_metadata: { name: 'أميرة' },
    }]);
    assert.deepEqual(calls.inserted, [{
      uid: 'new-staff-uid',
      scope: 'merchant',
      role: 'owner',
      merchant_id: 'merchant-1',
    }]);
  });

  it('maps duplicate emails to conflict without inserting staff', async () => {
    const calls = staffClients({
      createResult: { data: {}, error: new Error('User already registered') },
    });

    await expectJson(await createStaff(request(validStaff)), 409, { error: 'emailTaken' });
    assert.equal(calls.inserted.length, 0);
  });

  it('rolls back the auth user when the staff insert fails', async () => {
    const calls = staffClients({ staffError: new Error('constraint failed') });

    await expectJson(await createStaff(request(validStaff)), 500, { error: 'createFailed' });
    assert.deepEqual(calls.deleted, ['new-staff-uid']);
  });
});

function resetClients(options = {}) {
  const calls = { updates: [], audits: [] };
  const staffResults = [
    { data: options.caller === undefined
      ? { scope: 'platform', role: 'admin', is_active: true }
      : options.caller, error: null },
    { data: options.targetStaff ?? null, error: null },
  ];
  const anon = {
    auth: {
      getUser: async () => options.userResult ?? {
        data: { user: { id: 'admin-uid' } }, error: null,
      },
    },
  };
  const service = {
    auth: {
      admin: {
        updateUserById: async (uid, payload) => {
          calls.updates.push({ uid, ...payload });
          return { error: options.updateError ?? null };
        },
      },
    },
    from(table) {
      if (table === 'staff') {
        return {
          select() { return this; },
          eq() { return this; },
          async maybeSingle() { return staffResults.shift(); },
        };
      }
      if (table === 'users') {
        return query({ data: options.profile === undefined ? { id: 'customer-uid' } : options.profile });
      }
      if (table === 'audit_log') {
        return { insert: async (row) => { calls.audits.push(row); return { error: null }; } };
      }
      throw new Error(`unexpected table ${table}`);
    },
  };
  globalThis.__luqmaCreateClient = (_url, key) => key === 'anon-key' ? anon : service;
  return calls;
}

describe('reset-customer-password', () => {
  it('rejects missing authentication and non-admin callers', async () => {
    await expectJson(await resetPassword(request({}, { token: null })), 401, {
      error: 'unauthorized',
    });

    resetClients({ caller: { scope: 'platform', role: 'moderator', is_active: true } });
    await expectJson(await resetPassword(request({ uid: 'customer-uid' })), 403, {
      error: 'forbidden',
    });
  });

  it('rejects malformed bodies and blank customer ids', async () => {
    resetClients();
    await expectJson(await resetPassword(request('{', { raw: true })), 400, {
      error: 'badRequest',
    });

    resetClients();
    await expectJson(await resetPassword(request({ uid: '  ' })), 400, {
      error: 'badRequest',
    });
  });

  it('will not reset any staff account', async () => {
    const calls = resetClients({ targetStaff: { uid: 'staff-uid' } });

    await expectJson(await resetPassword(request({ uid: 'staff-uid' })), 400, {
      error: 'notACustomer',
    });
    assert.equal(calls.updates.length, 0);
  });

  it('distinguishes a missing customer from a staff account', async () => {
    const calls = resetClients({ profile: null });

    await expectJson(await resetPassword(request({ uid: 'missing-uid' })), 404, {
      error: 'noSuchCustomer',
    });
    assert.equal(calls.updates.length, 0);
  });

  it('generates a readable password and audits identities but not credentials', async () => {
    const calls = resetClients();

    const response = await resetPassword(request({ uid: '  customer-uid  ' }));
    assert.equal(response.status, 200);
    const { password } = await response.json();
    assert.match(password, /^[abcdefghijkmnpqrstuvwxyz23456789]{10}$/);
    assert.deepEqual(calls.updates, [{ uid: 'customer-uid', password }]);
    assert.deepEqual(calls.audits, [{
      actor: 'admin-uid',
      action: 'customer.password_reset',
      detail: { customer: 'customer-uid' },
    }]);
    assert.equal(JSON.stringify(calls.audits).includes(password), false);
  });

  it('does not write a success audit when Auth rejects the reset', async () => {
    const calls = resetClients({ updateError: new Error('auth unavailable') });

    await expectJson(await resetPassword(request({ uid: 'customer-uid' })), 500, {
      error: 'resetFailed',
    });
    assert.equal(calls.audits.length, 0);
  });
});

function pushClient(claimResult) {
  const calls = [];
  const service = {
    rpc: async (name, args) => {
      calls.push({ name, args });
      if (name === 'claim_push_batch') return claimResult;
      return { data: null, error: null };
    },
  };
  globalThis.__luqmaCreateClient = () => service;
  return calls;
}

async function serviceAccount() {
  const keys = await crypto.subtle.generateKey(
    { name: 'RSASSA-PKCS1-v1_5', modulusLength: 1024, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' },
    true,
    ['sign', 'verify'],
  );
  const bytes = Buffer.from(await crypto.subtle.exportKey('pkcs8', keys.privateKey));
  const base64 = bytes.toString('base64').match(/.{1,64}/g).join('\n');
  return {
    client_email: 'push@example.iam.gserviceaccount.com',
    private_key: `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----\n`,
    project_id: 'luqma-test',
  };
}

describe('send-push', () => {
  it('keeps the service role behind the exact configured cron secret', async () => {
    functionEnv.set('LUQMA_CRON_SECRET', 'right-secret');

    for (const supplied of [null, 'wrong-secret']) {
      const headers = supplied ? { 'x-cron-secret': supplied } : {};
      await expectJson(
        await sendPush(new Request('https://functions.local/send-push', { method: 'POST', headers })),
        403,
        { error: 'forbidden' },
      );
    }
  });

  it('fails plainly when FCM credentials are not configured', async () => {
    functionEnv.set('LUQMA_CRON_SECRET', 'secret');
    pushClient({ data: [], error: null });

    await expectJson(
      await sendPush(new Request('https://functions.local/send-push', {
        headers: { 'x-cron-secret': 'secret' },
      })),
      500,
      { error: 'LUQMA_FCM_SERVICE_ACCOUNT is not set' },
    );
  });

  it('reports claim failures and handles an empty outbox without contacting Google', async () => {
    functionEnv.set('LUQMA_CRON_SECRET', 'secret');
    functionEnv.set('LUQMA_FCM_SERVICE_ACCOUNT', '{}');
    pushClient({ data: null, error: { message: 'database unavailable' } });
    await expectJson(
      await sendPush(new Request('https://functions.local/send-push', {
        headers: { 'x-cron-secret': 'secret' },
      })),
      500,
      { error: 'database unavailable' },
    );

    const calls = pushClient({ data: [], error: null });
    await expectJson(
      await sendPush(new Request('https://functions.local/send-push', {
        headers: { 'x-cron-secret': 'secret' },
      })),
      200,
      { sent: 0 },
    );
    assert.deepEqual(calls, [{ name: 'claim_push_batch', args: { p_limit: 20 } }]);
  });

  it('settles tokenless rows, stringifies data, and removes only dead FCM tokens', async () => {
    functionEnv.set('LUQMA_CRON_SECRET', 'secret');
    functionEnv.set('LUQMA_FCM_SERVICE_ACCOUNT', JSON.stringify(await serviceAccount()));
    const calls = pushClient({
      data: [
        { id: 'empty', tokens: [], title: 'No device', body: '', channel: 'orders' },
        {
          id: 'mixed',
          tokens: ['live-token', 'dead-token', 'temporary-token'],
          title: 'New order',
          body: 'Ready',
          channel: 'orders_critical',
          data: { orderId: 42, urgent: true },
        },
      ],
      error: null,
    });
    const fcmBodies = [];
    globalThis.fetch = async (url, options) => {
      if (url === 'https://oauth2.googleapis.com/token') {
        return new Response(JSON.stringify({ access_token: 'google-token' }), { status: 200 });
      }
      const payload = JSON.parse(options.body);
      fcmBodies.push(payload);
      if (payload.message.token === 'live-token') return new Response('{}', { status: 200 });
      if (payload.message.token === 'dead-token') {
        return new Response(JSON.stringify({
          error: { details: [{ errorCode: 'UNREGISTERED' }] },
        }), { status: 404 });
      }
      return new Response(JSON.stringify({ error: { status: 'UNAVAILABLE' } }), { status: 503 });
    };

    await expectJson(
      await sendPush(new Request('https://functions.local/send-push', {
        headers: { 'x-cron-secret': 'secret' },
      })),
      200,
      { sent: 1, claimed: 2 },
    );
    assert.deepEqual(calls.slice(1), [
      { name: 'settle_push', args: { p_id: 'empty', p_error: 'no tokens' } },
      {
        name: 'settle_push',
        args: { p_id: 'mixed', p_error: null, p_dead_tokens: ['dead-token'] },
      },
    ]);
    assert.deepEqual(fcmBodies[0].message.data, {
      title: 'New order',
      body: 'Ready',
      channel: 'orders_critical',
      orderId: '42',
      urgent: 'true',
    });
    assert.equal('notification' in fcmBodies[0].message, false);
    assert.deepEqual(fcmBodies[0].message.android, { priority: 'HIGH', ttl: '3600s' });
  });

  it('records a failed delivery when no token accepts the message', async () => {
    functionEnv.set('LUQMA_CRON_SECRET', 'secret');
    functionEnv.set('LUQMA_FCM_SERVICE_ACCOUNT', JSON.stringify(await serviceAccount()));
    const calls = pushClient({
      data: [{
        id: 'failed', tokens: ['bad-token'], title: 'Title', body: 'Body', channel: 'orders', data: {},
      }],
      error: null,
    });
    globalThis.fetch = async (url) => url === 'https://oauth2.googleapis.com/token'
      ? new Response(JSON.stringify({ access_token: 'google-token' }), { status: 200 })
      : new Response(JSON.stringify({ error: { status: 'INVALID_ARGUMENT' } }), { status: 400 });

    await expectJson(
      await sendPush(new Request('https://functions.local/send-push', {
        headers: { 'x-cron-secret': 'secret' },
      })),
      200,
      { sent: 0, claimed: 1 },
    );
    assert.deepEqual(calls.at(-1), {
      name: 'settle_push',
      args: {
        p_id: 'failed',
        p_error: 'no token accepted it',
        p_dead_tokens: ['bad-token'],
      },
    });
  });
});
