// deno-lint-ignore-file
import { createClient } from 'jsr:@supabase/supabase-js@2';

/**
 * Drains `push_outbox` and hands each row to FCM.
 *
 * The order never waits for this. `place_order` writes a row in its own transaction and
 * returns; this runs afterwards, on a schedule, and can be slow or broken without any
 * customer losing an order. That separation is the whole design — a notification arriving
 * late is a bad evening, an order failing is money gone.
 *
 * Called by pg_cron every minute, and by nothing else: it holds the service role, so the
 * only caller allowed is one that knows the cron secret.
 */

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

/** A Google access token, minted from the service account with a signed JWT. */
async function accessToken(sa: { client_email: string; private_key: string }) {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claims = {
    iss: sa.client_email,
    scope: FCM_SCOPE,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const b64 = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const unsigned = `${b64(header)}.${b64(claims)}`;

  // The PEM as it comes out of the JSON key, with its newlines un-escaped.
  const pem = sa.private_key.replace(/\\n/g, '\n');
  const der = Uint8Array.from(
    atob(pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s/g, '')),
    (c) => c.charCodeAt(0),
  );
  const key = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  );
  const signed = `${unsigned}.${btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: signed,
    }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`token: ${JSON.stringify(body)}`);
  return body.access_token as string;
}

/** The codes FCM uses for a token that will never work again. */
const DEAD = ['UNREGISTERED', 'INVALID_ARGUMENT', 'SENDER_ID_MISMATCH'];

Deno.serve(async (req: Request) => {
  // The only caller is pg_cron. Without this the service role sits behind a public URL.
  const secret = Deno.env.get('LUQMA_CRON_SECRET');
  if (!secret || req.headers.get('x-cron-secret') !== secret) {
    return new Response(JSON.stringify({ error: 'forbidden' }), { status: 403 });
  }

  const service = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  const saJson = Deno.env.get('LUQMA_FCM_SERVICE_ACCOUNT');
  if (!saJson) {
    // Said plainly: without the key this function cannot do anything at all, and a
    // silent no-op here reads as "notifications are broken" for weeks.
    return new Response(
      JSON.stringify({ error: 'LUQMA_FCM_SERVICE_ACCOUNT is not set' }),
      { status: 500 },
    );
  }
  const sa = JSON.parse(saJson);

  const { data: batch, error } = await service.rpc('claim_push_batch', { p_limit: 20 });
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
  if (!batch?.length) {
    return new Response(JSON.stringify({ sent: 0 }), { status: 200 });
  }

  const token = await accessToken(sa);
  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

  let sent = 0;
  for (const row of batch) {
    const tokens: string[] = row.tokens ?? [];
    if (tokens.length === 0) {
      // Nobody has this app installed. Settled rather than retried: five attempts
      // against an account with no phone is five minutes of nothing.
      await service.rpc('settle_push', { p_id: row.id, p_error: 'no tokens' });
      continue;
    }

    const dead: string[] = [];
    let delivered = false;

    for (const to of tokens) {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: to,
            // `data` only, no `notification` block: with a notification payload Android
            // draws the alert itself and the app never runs, so the looping alarm on the
            // orders_critical channel would never play. The app builds it instead.
            data: {
              title: row.title,
              body: row.body,
              channel: row.channel,
              ...Object.fromEntries(
                Object.entries(row.data ?? {}).map(([k, v]) => [k, String(v)]),
              ),
            },
            android: {
              priority: 'HIGH',
              // Woken even in Doze. This is the notification the shop's evening depends
              // on, and a phone on a shelf is a phone Android has put to sleep.
              ttl: '3600s',
            },
          },
        }),
      });

      if (res.ok) {
        delivered = true;
        continue;
      }

      const body = await res.json().catch(() => ({}));
      const status = body?.error?.details?.[0]?.errorCode ?? body?.error?.status ?? '';
      if (DEAD.includes(status)) dead.push(to);
    }

    await service.rpc('settle_push', {
      p_id: row.id,
      p_error: delivered ? null : 'no token accepted it',
      p_dead_tokens: dead,
    });
    if (delivered) sent++;
  }

  return new Response(JSON.stringify({ sent, claimed: batch.length }), { status: 200 });
});
