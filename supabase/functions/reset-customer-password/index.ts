// deno-lint-ignore-file
import { createClient } from 'jsr:@supabase/supabase-js@2';

/**
 * Gives a customer a new password, because there is nowhere to send them a link.
 *
 * A customer's account is keyed on their phone number folded into a synthetic address
 * (`01…@phone.luqma.app`) that has no mailbox, and OTP is off — so the ordinary "reset by
 * email" and "reset by SMS" paths both lead nowhere. Somebody who forgets their password
 * calls the number on حول لقمة, and an admin does this.
 *
 * The password is generated here rather than typed by the admin: an admin choosing one
 * picks the same weak password for everybody, and this way what gets read down the phone
 * is at least random. It is returned once and never stored anywhere in readable form.
 *
 * Same door policy as `create-staff-account`: the caller must carry a real GoTrue JWT
 * whose `staff` row says platform admin and active, checked before the service role is
 * ever spent.
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  });
}

/**
 * Ten characters a person can read down a phone line without spelling anything out.
 *
 * No `l`/`1`/`O`/`0` and no symbols: this password is spoken aloud, and every character
 * that has to be disambiguated ("zero or the letter O?") is a failed call-back.
 */
function readablePassword(): string {
  const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(10));
  return Array.from(bytes, (b) => alphabet[b % alphabet.length]).join('');
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;

  // Who is calling? Verified by GoTrue itself, not decoded in here — a forged claim set
  // never reaches this line's happy path.
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'unauthorized' }, 401);

  const anon = createClient(url, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: userError } = await anon.auth.getUser(token);
  if (userError || !userData.user) return json({ error: 'unauthorized' }, 401);

  const service = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Read our own table with the service key: RLS would answer a different question for a
  // client than the one being asked here.
  const { data: caller, error: callerError } = await service
    .from('staff')
    .select('scope, role, is_active')
    .eq('uid', userData.user.id)
    .maybeSingle();
  if (callerError || !caller || caller.scope !== 'platform' ||
      caller.role !== 'admin' || !caller.is_active) {
    return json({ error: 'forbidden' }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: 'badRequest' }, 400);
  }

  const uid = typeof body.uid === 'string' ? body.uid.trim() : '';
  if (!uid) return json({ error: 'badRequest' }, 400);

  // Customers only. A merchant or courier password is reset by whoever manages staff,
  // through the staff screen — and an admin resetting another *admin* here would turn a
  // support call into a way to take the platform.
  const { data: staffRow } = await service
    .from('staff')
    .select('uid')
    .eq('uid', uid)
    .maybeSingle();
  if (staffRow) return json({ error: 'notACustomer' }, 400);

  const { data: profile } = await service
    .from('users')
    .select('id')
    .eq('id', uid)
    .maybeSingle();
  if (!profile) return json({ error: 'noSuchCustomer' }, 404);

  const password = readablePassword();
  const { error: updateError } = await service.auth.admin.updateUserById(uid, { password });
  if (updateError) return json({ error: 'resetFailed' }, 500);

  // Who did it, and to whom. Not the password — an audit log that carries credentials is
  // a place to steal them from.
  await service.from('audit_log').insert({
    actor: userData.user.id,
    action: 'customer.password_reset',
    detail: { customer: uid },
  });

  return json({ password });
});
