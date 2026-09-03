-- Validate the recognised control-plane contract atomically, then return the exact
-- post-write state to AdminApp. Unknown keys remain available to newer modules.

drop function public.admin_set_config(jsonb);

create function public.admin_set_config(
  p_values jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  kv record;
  v_number integer;
  v_fee_min integer;
  v_fee_max integer;
  v_pair_key text;
  v_result jsonb;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin may change config' using errcode = '42501';
  end if;

  -- Keep in sync with configBounds in
  -- packages/luqma_core/lib/src/config/luqma_config.dart.
  for kv in select * from pg_catalog.jsonb_each(p_values) loop
    if kv.key in (
      'accept_timeout_minutes',
      'marketing_push_per_week',
      'rejection_ban_threshold',
      'min_ratings_to_show',
      'splash_min_millis',
      'delivery_fee_min',
      'delivery_fee_max'
    ) then
      if pg_catalog.jsonb_typeof(kv.value) <> 'number'
         or (kv.value #>> '{}') !~ '^-?[0-9]+$' then
        raise exception 'invalid config value for %', kv.key
          using errcode = 'check_violation';
      end if;

      v_number := (kv.value #>> '{}')::integer;
      if (kv.key = 'accept_timeout_minutes' and v_number not between 1 and 60)
         or (kv.key = 'marketing_push_per_week' and v_number not between 0 and 21)
         or (kv.key = 'rejection_ban_threshold' and v_number not between 1 and 50)
         or (kv.key = 'min_ratings_to_show' and v_number not between 0 and 1000)
         or (kv.key = 'splash_min_millis' and v_number not between 0 and 5000)
         or (kv.key = 'delivery_fee_min' and v_number not between 0 and 100000)
         or (kv.key = 'delivery_fee_max' and v_number not between 0 and 100000) then
        raise exception 'invalid config value for %', kv.key
          using errcode = 'check_violation';
      end if;
    elsif kv.key in (
      'otp_enabled',
      'admob_enabled',
      'public_comments_enabled',
      'online_payment_enabled'
    ) then
      if pg_catalog.jsonb_typeof(kv.value) <> 'boolean' then
        raise exception 'invalid config value for %', kv.key
          using errcode = 'check_violation';
      end if;
    elsif kv.key in (
      'min_supported_version',
      'customer_min_supported_version',
      'merchant_min_supported_version',
      'admin_min_supported_version'
    ) then
      if pg_catalog.jsonb_typeof(kv.value) <> 'null'
         and (
           pg_catalog.jsonb_typeof(kv.value) <> 'string'
           or (kv.value #>> '{}') !~ '^[0-9]+(\.[0-9]+){0,2}$|^$'
         ) then
        raise exception 'invalid config value for %', kv.key
          using errcode = 'check_violation';
      end if;
    elsif kv.key in (
      'support_whatsapp',
      'update_message',
      'customer_update_url',
      'merchant_update_url',
      'admin_update_url'
    ) then
      if pg_catalog.jsonb_typeof(kv.value) not in ('string', 'null') then
        raise exception 'invalid config value for %', kv.key
          using errcode = 'check_violation';
      end if;
    end if;
  end loop;

  if p_values ? 'delivery_fee_min' then
    v_fee_min := ((p_values -> 'delivery_fee_min') #>> '{}')::integer;
  else
    select case
      when pg_catalog.jsonb_typeof(c.value) = 'number'
           and (c.value #>> '{}') ~ '^-?[0-9]+$'
        then (c.value #>> '{}')::integer
      else null
    end
    into v_fee_min
    from public.config as c
    where c.key = 'delivery_fee_min';
  end if;

  if p_values ? 'delivery_fee_max' then
    v_fee_max := ((p_values -> 'delivery_fee_max') #>> '{}')::integer;
  else
    select case
      when pg_catalog.jsonb_typeof(c.value) = 'number'
           and (c.value #>> '{}') ~ '^-?[0-9]+$'
        then (c.value #>> '{}')::integer
      else null
    end
    into v_fee_max
    from public.config as c
    where c.key = 'delivery_fee_max';
  end if;

  if v_fee_min is not null and v_fee_max is not null and v_fee_max < v_fee_min then
    v_pair_key := case
      when p_values ? 'delivery_fee_max' then 'delivery_fee_max'
      else 'delivery_fee_min'
    end;
    raise exception 'invalid config value for %', v_pair_key
      using errcode = 'check_violation';
  end if;

  for kv in select * from pg_catalog.jsonb_each(p_values) loop
    insert into public.config (key, value, updated_at)
      values (kv.key, kv.value, pg_catalog.now())
    on conflict (key) do update
      set value = excluded.value,
          updated_at = pg_catalog.now();
  end loop;

  insert into public.audit_log (action, actor, detail)
    values ('config.set', v_actor, p_values);

  select coalesce(
    pg_catalog.jsonb_object_agg(c.key, c.value),
    '{}'::jsonb
  )
  into v_result
  from public.config as c;

  return v_result;
end;
$$;

revoke execute on function public.admin_set_config(jsonb) from public, anon;
grant execute on function public.admin_set_config(jsonb) to authenticated;
