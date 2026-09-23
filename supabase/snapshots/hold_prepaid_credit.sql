-- SNAPSHOT of public.hold_prepaid_credit as it runs — written by snapshot-functions.mjs.
-- Documentation only: never applied. Change it with a migration.

CREATE OR REPLACE FUNCTION public.hold_prepaid_credit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  v_hold  integer;
  v_prior text;
  v_reopened boolean := false;
begin
  if tg_op = 'INSERT' then
    v_hold := public.prepaid_hold_for(new);
  elsif old.status not in ('delivered', 'cancelled', 'rejected')
        and new.status in ('delivered', 'cancelled', 'rejected') then
    -- Released once, on the first move out of a live state.
    v_hold := -public.prepaid_hold_for(new);
  elsif old.status in ('delivered', 'cancelled', 'rejected')
        and new.status not in ('delivered', 'cancelled', 'rejected') then
    -- Reopened by an admin: the hold released on the way out is taken again.
    v_reopened := true;
    v_hold := public.prepaid_hold_for(new);
  else
    return new;
  end if;

  if v_hold <> 0 then
    v_prior := coalesce(current_setting('app.server_mode', true), '');
    perform set_config('app.server_mode', 'on', true);
    if v_hold > 0 then
      -- Taken only if it is there, under the row lock this update holds: the second of
      -- two simultaneous orders waits here, re-reads the row, and is refused (A7).
      update public.merchants
         set wallet_held = wallet_held + v_hold
       where id = new.merchant_id
         and (v_reopened
              or (plan_id is not null and plan_expires_at > now())
              or wallet_balance - wallet_held >= v_hold);
      if not found then
        raise exception 'merchant not accepting orders' using errcode = 'P0001';
      end if;
    else
      update public.merchants
         set wallet_held = greatest(wallet_held + v_hold, 0)
       where id = new.merchant_id;
    end if;
    perform set_config('app.server_mode', v_prior, true);
  end if;
  return new;
end;
$function$;
