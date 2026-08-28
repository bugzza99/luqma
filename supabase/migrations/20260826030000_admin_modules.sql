-- The remaining admin modules' server half: config and plans.
--
-- Both are writes the client must not make directly. The `config` table is read by every
-- phone in the city, so a write to it is a write to the whole city at once; and `plans`
-- is what every merchant's subscription is priced against. Each goes through a
-- SECURITY DEFINER function that checks `is_admin()` inside rather than leaning on
-- grants alone, and stamps an audit row — a config or price change is recorded like
-- every other admin mutation, not a silent upsert.

-- ---------------------------------------------------------------- config

-- Upserts any number of keys in one call, then records the whole change. Keys absent
-- from `p_values` are left alone; keys present replace their value. The value is typed
-- jsonb already, so a boolean arrives a boolean and an integer an integer.
create or replace function public.admin_set_config(
  p_values jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  kv record;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin may change config' using errcode = '42501';
  end if;

  for kv in select * from jsonb_each(p_values) loop
    insert into public.config (key, value, updated_at)
      values (kv.key, kv.value, now())
    on conflict (key) do update
      set value = excluded.value,
          updated_at = now();
  end loop;

  insert into public.audit_log (action, actor, detail)
    values ('config.set', v_actor, p_values);
end;
$$;
revoke execute on function public.admin_set_config(jsonb) from public, anon;
grant execute on function public.admin_set_config(jsonb) to authenticated;

-- ---------------------------------------------------------------- plans

-- Creates or replaces one plan. A plan is keyed by a fixed id ('free', 'basic'), so
-- saving an existing id replaces it rather than colliding with it.
create or replace function public.admin_set_plan(
  p_id            text,
  p_name          text,
  p_price_monthly integer,
  p_features      jsonb,
  p_sort_order    integer,
  p_is_active     boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin may edit plans' using errcode = '42501';
  end if;

  if p_price_monthly < 0 then
    raise exception 'a plan price must be non-negative' using errcode = 'check_violation';
  end if;

  insert into public.plans
    (id, name, price_monthly, features, sort_order, is_active, updated_at)
  values
    (p_id, p_name, p_price_monthly, p_features, p_sort_order, p_is_active, now())
  on conflict (id) do update
    set name = excluded.name,
        price_monthly = excluded.price_monthly,
        features = excluded.features,
        sort_order = excluded.sort_order,
        is_active = excluded.is_active,
        updated_at = now();

  insert into public.audit_log (action, actor, detail)
    values ('plan.set', v_actor,
            jsonb_build_object('planId', p_id, 'priceMonthly', p_price_monthly));
end;
$$;
revoke execute on function public.admin_set_plan(text, text, integer, jsonb, integer, boolean)
  from public, anon;
grant execute on function public.admin_set_plan(text, text, integer, jsonb, integer, boolean)
  to authenticated;
