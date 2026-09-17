// deno-lint-ignore-file
import { createClient } from 'jsr:@supabase/supabase-js@2';

/**
 * Sets a new password for a customer, merchant owner or courier, chosen by the admin.
 *
 * A customer's account is keyed on their phone number folded into a synthetic address
 * (`01…@phone.luqma.app`) that has no mailbox, and OTP is off — so the ordinary "reset by
 * email" and "reset by SMS" paths both lead nowhere. Somebody who forgets their password
 * calls the number on حول لقمة, and an admin sets a password they choose so they can tell
 * the person a password they can remember. It is still never stored or logged anywhere
 * in readable form.
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
    const parsed = await req.json();
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return json({ error: 'badRequest' }, 400);
    }
    body = parsed as Record<string, unknown>;
  } catch {
    return json({ error: 'badRequest' }, 400);
  }

  const uid = typeof body.uid === 'string' ? body.uid.trim() : '';
  if (!uid) return json({ error: 'badRequest' }, 400);

  const password = typeof body.password === 'string' ? body.password.trim() : '';
  if (!password || password.length < 8 || password.length > 72) {
    return json({ error: 'badPassword' }, 400);
  }

  // Allowed targets: a customer (a users row and no staff row) or a staff row with
  // scope = 'merchant' (owners and couriers). A scope = 'platform' staff row is still
  // refused with 400 {error:'notAllowed'} — resetting another admin must stay impossible.
  // A uid with neither → 404 {error:'noSuchAccount'}.
  //
  // A failed lookup is a refusal, never "no staff row". Found in review: with the error
  // discarded, a timeout here let a platform admin's password be reset as a customer's.
  const { data: staffRow, error: staffError } = await service
    .from('staff')
    .select('scope, role')
    .eq('uid', uid)
    .maybeSingle();
  if (staffError) return json({ error: 'lookupFailed' }, 500);

  let kind: 'customer' | 'owner' | 'courier';

  if (staffRow) {
    if (staffRow.scope === 'platform') {
      return json({ error: 'notAllowed' }, 400);
    }
    if (staffRow.scope === 'merchant' && (staffRow.role === 'owner' || staffRow.role === 'courier')) {
      kind = staffRow.role;
    } else {
      return json({ error: 'notAllowed' }, 400);
    }
  } else {
    const { data: profile, error: profileError } = await service
      .from('users')
      .select('id')
      .eq('id', uid)
      .maybeSingle();
    if (profileError) return json({ error: 'lookupFailed' }, 500);
    if (!profile) return json({ error: 'noSuchAccount' }, 404);
    kind = 'customer';
  }

  const { error: updateError } = await service.auth.admin.updateUserById(uid, { password });
  if (updateError) return json({ error: 'resetFailed' }, 500);

  // The audit row: action: 'account.password_set', detail: { target: uid, kind: 'customer'|'owner'|'courier' }. Never the password.
  const { error: auditError } = await service.from('audit_log').insert({
    actor: userData.user.id,
    action: 'account.password_set',
    detail: { target: uid, kind },
  });

  // The password has already changed, so this is not a failure to report as one — but a
  // change nobody can find in the log is worth saying out loud. Never the password.
  if (auditError) {
    console.error(`password set for ${kind} ${uid} but the audit row failed: ${auditError.message}`);
    return json({ ok: true, audited: false });
  }

  return json({ ok: true });
});
