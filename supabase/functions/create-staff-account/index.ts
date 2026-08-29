// deno-lint-ignore-file
import { createClient } from 'jsr:@supabase/supabase-js@2';

/**
 * Creates a staff account — the one act that needs the service role, and therefore the
 * one door that must know exactly who is walking through it.
 *
 * The caller must carry a real GoTrue JWT whose `staff` row says platform admin and
 * active; anything else is refused before the service role is ever spent. What it buys:
 * one Auth user, one staff row. The profile row comes free from the ensure_user_profile
 * trigger, same as every other account.
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

const SCOPES = ['platform', 'merchant'];
const ROLES = ['admin', 'moderator', 'owner', 'courier'];

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;

  // Who is calling? The token is verified by GoTrue itself, not decoded in here — a
  // forged claim set never reaches this line's happy path.
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

  // Is the caller allowed to do this? Read off our own table with the service key,
  // because RLS would answer a different question for a client than we ask here.
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

  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  const password = typeof body.password === 'string' ? body.password : '';
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  const scope = body.scope;
  const role = body.role;
  const merchantId = typeof body.merchantId === 'string' ? body.merchantId.trim() : null;

  if (!email.includes('@') || password.length < 8 || scope === undefined ||
      role === undefined || !SCOPES.includes(scope as string) ||
      !ROLES.includes(role as string)) {
    return json({ error: 'badRequest' }, 400);
  }
  // A merchant-scope account belongs to somebody; a platform account to nobody.
  if (scope === 'merchant' && !merchantId) return json({ error: 'badRequest' }, 400);
  if (scope === 'platform' && merchantId) return json({ error: 'badRequest' }, 400);

  // If the staff row names a merchant, that merchant has to exist — otherwise the
  // account would sign in to nothing.
  if (merchantId !== null) {
    const { data: merchant } = await service
      .from('merchants')
      .select('id')
      .eq('id', merchantId)
      .maybeSingle();
    if (!merchant) return json({ error: 'noSuchMerchant' }, 400);
  }

  const { data: created, error: createError } = await service.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: name ? { name } : {},
  });
  if (createError) {
    const already = createError.message.toLowerCase().includes('already');
    return json({ error: already ? 'emailTaken' : 'createFailed' }, already ? 409 : 500);
  }
  const uid = created.user!.id;

  const { error: staffError } = await service.from('staff').insert({
    uid,
    scope,
    role,
    merchant_id: merchantId,
  });
  if (staffError) {
    // No half-made accounts: an Auth user nobody can reach is worse than none.
    await service.auth.admin.deleteUser(uid);
    return json({ error: 'createFailed' }, 500);
  }

  return json({ uid });
});
