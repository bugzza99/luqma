-- A shop's money is read by the shop and the platform, not by whoever holds the app (A6).
--
-- `merchants` was granted to `anon` and `authenticated` whole, with a row policy and no
-- column restriction, so the key inside every APK read every shop's wallet, what it owes,
-- what it is on hold and the rate it negotiated:
-- `GET /rest/v1/merchants?select=name,commission_owed,wallet_balance,revenue_value`.
-- A competitor, or a customer, could see which shop is in debt and on what terms.
--
-- Three pieces:
--   * SELECT is granted per column. What a customer's screen draws stays readable; the
--     money, the terms, the plan and the owner's account id do not.
--   * One boolean does the customer's job for the money: whether a prepaid shop has the
--     credit for one more order. The phone asked that from the wallet columns to grey a
--     shop out rather than let a refused order be placed. It is generated from the same
--     formula `place_order_priced` uses, so it cannot disagree with it.
--   * `merchant_money(ids)` answers the hidden columns to the shop's owner, to staff who
--     administer shops and to the server's own key, and to nobody else — rows outside
--     that are simply absent.
--
-- ORDER OF RELEASE: an APK built before this change selects `*` from merchants and is
-- refused outright once it lands. Production takes this migration only after every
-- phone runs a build that names its columns. It is numbered last on purpose (it was
-- written as 20261101220000 and applied to luqma-test under that number, then renamed
-- and the history repaired) so everything before it can reach production first; push
-- the rest with this file set aside, and this one alone once the phones are updated.
--
-- Functions that run as their owner (every money path) are untouched: they never read
-- through these grants. Writes are untouched too; the column guards still decide them.

alter table public.merchants
  add column takes_prepaid_orders boolean
    generated always as (
      revenue_model <> 'prepaid'
      or wallet_balance - wallet_held >= revenue_value
    ) stored;

revoke select on public.merchants from anon, authenticated;
grant select (
  id, city_id, type, name, zone_id, phone, status, opening_hours, paused_until,
  logo_media_id, cover_media_id, delivers_self, delivery_fee_override, min_order,
  rating_avg, rating_count, created_at, updated_at, prep_minutes, description,
  landmark_id, landmark_name, street, lat, lng, takes_prepaid_orders
) on public.merchants to anon, authenticated;

create or replace function public.merchant_money(p_ids uuid[])
returns table (
  id uuid,
  owner_uid uuid,
  plan_id text,
  plan_expires_at timestamptz,
  revenue_model text,
  revenue_value integer,
  wallet_balance integer,
  wallet_held integer,
  commission_owed integer,
  commission_custom boolean
)
language sql
stable
security definer
set search_path = ''
as $fn$
  select m.id, m.owner_uid, m.plan_id, m.plan_expires_at, m.revenue_model,
         m.revenue_value, m.wallet_balance, m.wallet_held, m.commission_owed,
         m.commission_custom
    from public.merchants m
   where m.id = any(p_ids)
     and (public.is_admin()
          or public.is_merchant_owner(m.id)
          -- The server's own key, which already reads every column of the table.
          or coalesce(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '')
             = 'service_role');
$fn$;

revoke all on function public.merchant_money(uuid[]) from public, anon;
grant execute on function public.merchant_money(uuid[]) to authenticated, service_role;

-- `guard_columns` compares every column of NEW against OLD, and in a BEFORE trigger a
-- stored generated column is not computed yet — so `takes_prepaid_orders` read as
-- "changed" on every update and an owner could save nothing. A generated column is the
-- server's by construction; the guard now leaves generated columns out. Patched in place,
-- anchor exactly once.
do $migrate$
declare
  v_def text;
  v_old constant text := '   where v is distinct from (to_jsonb(old) -> changes.k);';
begin
  select pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), chr(13), '') into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'guard_columns';

  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'guard_columns has drifted; re-read it before patching.';
  end if;

  execute replace(v_def, v_old, '   where v is distinct from (to_jsonb(old) -> changes.k)
     and changes.k not in (
           select a.attname from pg_catalog.pg_attribute a
            where a.attrelid = tg_relid and a.attgenerated <> '''');');
end;
$migrate$;
