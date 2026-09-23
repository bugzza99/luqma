-- SNAPSHOT of public.place_order as it runs — written by snapshot-functions.mjs.
-- Documentation only: never applied. Change it with a migration.

CREATE OR REPLACE FUNCTION public.place_order(p_draft jsonb, p_client_order_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_code text;
  v_order jsonb;
  v_existing public.orders;
  v_prior_mode text;
begin
  if auth.uid() is null then
    raise exception 'sign in to place an order' using errcode = '42501';
  end if;

  if exists (select 1 from public.users where id = auth.uid() and is_blocked) then
    raise exception 'this account cannot place orders' using errcode = '42501';
  end if;

  -- A retry after the first request committed is the cheap path: return the row exactly
  -- as `place_order_priced` did, before checking the draft or touching a coupon.
  if p_client_order_id is not null then
    select o.* into v_existing
      from public.orders o
     where o.customer_uid = auth.uid()
       and o.client_order_id = p_client_order_id;
    if found then
      return to_jsonb(v_existing);
    end if;
  end if;

  perform public.check_draft_bounds(p_draft);

  -- Only when a code was actually offered: an ordinary order must not queue behind
  -- anything, and with no code there is nothing to hold still.
  v_code := nullif(btrim(p_draft ->> 'couponCode'), '');
  if v_code is not null then
    perform 1
       from public.coupons c
       join public.merchants m on m.id = (p_draft ->> 'merchantId')::uuid
      where c.city_id = m.city_id
        and c.code = upper(translate(v_code, U&'\0660\0661\0662\0663\0664\0665\0666\0667\0668\0669', '0123456789'))
      for update of c;
  end if;

  -- A concurrent request carrying a coupon may have waited on the row above. Once the
  -- lock is ours its winner is visible, so do not ask the priced half to reject the same
  -- customer's now-used coupon before idempotency gets a chance to answer.
  if p_client_order_id is not null then
    select o.* into v_existing
      from public.orders o
     where o.customer_uid = auth.uid()
       and o.client_order_id = p_client_order_id;
    if found then
      return to_jsonb(v_existing);
    end if;
  end if;

  -- `place_order_priced` declares `app.server_mode` and does not put it back, and that
  -- setting is transaction-local rather than function-local: it stands for the rest of
  -- whoever's transaction called it, with every column guard stood down behind it.
  --
  -- The rule is already written for `apply_order_settlement`, which restores it; this
  -- older function never did, and it is why a customer could rewrite `client_order_id`
  -- immediately after placing — the guard that refuses it had been switched off by the
  -- placement itself. PostgREST gives each RPC its own transaction, so nothing reachable
  -- from a phone can currently exploit it, which is exactly why it survived.
  --
  -- Restored here rather than inside the priced half, which is 360 lines of money
  -- arithmetic with several exits; the wrapper is the only entry a client can reach.
  -- A function-level `SET` would be the right tool and hosted Supabase refuses it:
  -- `permission denied to set parameter "app.server_mode"`.
  v_prior_mode := coalesce(current_setting('app.server_mode', true), '');

  if p_client_order_id is null then
    v_order := public.place_order_priced(p_draft);
    perform set_config('app.server_mode', v_prior_mode, true);
    return v_order;
  end if;

  -- The index, not either read above, settles two requests that arrive together. Every
  -- statement in this block is a subtransaction: if attaching the id loses the unique
  -- race, the order and every effect made by `place_order_priced` roll back with it.
  begin
    v_order := public.place_order_priced(p_draft);

    update public.orders
       set client_order_id = p_client_order_id
     where id = (v_order ->> 'id')::uuid
    returning * into v_existing;

    perform set_config('app.server_mode', v_prior_mode, true);
    return to_jsonb(v_existing);
  exception
    when unique_violation then
      -- Nothing to restore on this path: the block above is a subtransaction, so its
      -- rollback already undid the setting along with the order.
      select o.* into v_existing
        from public.orders o
       where o.customer_uid = auth.uid()
         and o.client_order_id = p_client_order_id;
      if found then
        return to_jsonb(v_existing);
      end if;
      -- A different unique boundary failed. It is not an idempotent retry, so preserve
      -- the original error instead of disguising it as one.
      raise;
  end;
end;
$function$;
