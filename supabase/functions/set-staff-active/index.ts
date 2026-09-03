// deno-lint-ignore-file
import { createClient } from 'jsr:@supabase/supabase-js@2';

/**
 * Changes whether a staff account may act, and closes its way back in when dismissed.
 *
 * The caller must carry a real GoTrue JWT whose `staff` row says platform admin and
 * active. Claims are deliberately insufficient here: this function exists because an
 * already-issued claim set can outlive the employment decision that issued it.
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

  // GoTrue verifies the signature and expiry. Decoding locally would let a forged admin
  // claim reach the service role, which is the credential this boundary exists to keep.
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.replace(/^Bearer\s+/i, '');
  if (!token) return json({ error: 'unauthorized' }, 401);

  const anon = createClient(url, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: userError } = await anon.auth.getUser(token);
  if (userError || !userData.user) return json({ error: 'unauthorized' }, 401);
  const callerUid = userData.user.id;

  const service = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // The table is current and the token is historical. A dismissed admin can still hold
  // a correctly signed admin token, so only the row answers whether it may be spent now.
  const { data: caller, error: callerError } = await service
    .from('staff')
    .select('scope, role, is_active')
    .eq('uid', callerUid)
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
  const active = body.active;
  if (!uid || typeof active !== 'boolean') return json({ error: 'badRequest' }, 400);

  const { data: target, error: targetError } = await service
    .from('staff')
    .select('uid')
    .eq('uid', uid)
    .maybeSingle();
  if (targetError) return json({ error: 'updateFailed' }, 500);
  if (!target) return json({ error: 'notFound' }, 404);

  // The RPC keeps the last-admin check, the update and the audit entry in one locked
  // transaction. A count followed by an update here would let two admins dismiss each
  // other between the two HTTP requests.
  const { error: updateError } = await service.rpc('set_staff_active', {
    p_uid: uid,
    p_active: active,
    p_actor: callerUid,
  });
  if (updateError) {
    if (updateError.code === '23514') return json({ error: 'lastAdmin' }, 409);
    if (updateError.code === 'P0002') return json({ error: 'notFound' }, 404);
    if (updateError.code === '42501') return json({ error: 'forbidden' }, 403);
    return json({ error: 'updateFailed' }, 500);
  }

  // GoTrue's admin sign-out needs the target's access JWT; it has no user-id logout API,
  // and this function never possesses another person's bearer token. The service-role
  // ban is the strongest user-id control available: it blocks sign-in and refresh, and
  // current GoTrue rejects a banned token when Auth validates it. It still cannot recall
  // a stateless access JWT already accepted by PostgREST, which is why the database reads
  // staff.is_active on every sensitive staff predicate.
  const { error: authError } = await service.auth.admin.updateUserById(uid, {
    ban_duration: active ? 'none' : '876000h',
  });
  if (authError) return json({ error: active ? 'enableFailed' : 'revokeFailed' }, 500);

  return json({ uid, active });
});
