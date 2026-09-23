-- A reopened order holds its prepaid fee again.
--
-- `hold_prepaid_credit` takes the fee when an order is placed and releases it on the first
-- move into delivered, cancelled or rejected. An admin can move an order back out of those
-- — reopening a delivery that came back, or a cancellation made by mistake — and nothing
-- took the hold again. Delivering it a second time released a hold that no longer
-- existed, out of some other live order's share, and `greatest(…, 0)` hid the drift until
-- the shop was open on credit it did not have.
--
-- Reopening now takes the hold again. Unconditionally: the order already exists and an
-- admin decided it is live, so a thin wallet is not a reason to refuse that; the shop's
-- next *new* order meets the ordinary check against what is free.
--
-- Patched in place; each anchor must match exactly once.

do $migrate$
declare
  v_def text;
  v_old_decl constant text := '  v_prior text;';
  v_old_branch constant text := '    v_hold := -public.prepaid_hold_for(new);
  else
    return new;
  end if;';
  v_old_where constant text := '       where id = new.merchant_id
         and ((plan_id is not null and plan_expires_at > now())';
begin
  select pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), chr(13), '') into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'hold_prepaid_credit';

  if (length(v_def) - length(replace(v_def, v_old_decl, ''))) / length(v_old_decl) <> 1
     or (length(v_def) - length(replace(v_def, v_old_branch, ''))) / length(v_old_branch) <> 1
     or (length(v_def) - length(replace(v_def, v_old_where, ''))) / length(v_old_where) <> 1 then
    raise exception 'hold_prepaid_credit has drifted; re-read it before patching.';
  end if;

  v_def := replace(v_def, v_old_decl, v_old_decl || '
  v_reopened boolean := false;');
  v_def := replace(v_def, v_old_branch, '    v_hold := -public.prepaid_hold_for(new);
  elsif old.status in (''delivered'', ''cancelled'', ''rejected'')
        and new.status not in (''delivered'', ''cancelled'', ''rejected'') then
    -- Reopened by an admin: the hold released on the way out is taken again.
    v_reopened := true;
    v_hold := public.prepaid_hold_for(new);
  else
    return new;
  end if;');
  v_def := replace(v_def, v_old_where, '       where id = new.merchant_id
         and (v_reopened
              or (plan_id is not null and plan_expires_at > now())');

  execute v_def;
end;
$migrate$;
