-- One order's worth of prepaid credit funds one order, even when two arrive at once (A7).
--
-- `place_order_priced` reads the merchant row without a lock and refuses a prepaid shop
-- whose free credit (`wallet_balance - wallet_held`) is under one fee. `hold_prepaid_credit`
-- then adds the fee to `wallet_held` without asking again. Two customers pressing «اطلب»
-- in the same instant both read the same free credit, both passed, both were held, and
-- delivering both left the wallet one fee below zero — the outcome `20260913000000` exists
-- to prevent, reached through concurrency instead of sequence.
--
-- The fix is where the money is taken: the hold is a conditional update, and it refuses
-- what the free credit cannot cover. The UPDATE takes the merchant row's lock, so the
-- second of two simultaneous placements waits for the first, re-reads the row, finds the
-- credit spoken for, and raises the same refusal the placement check would have — rolling
-- its whole order back with it. An active plan is exempt here as it is at placement.
--
-- Patched in place from the current body; the anchor must match exactly once.

do $migrate$
declare
  v_def text;
  v_anchor constant text :=
'    update public.merchants
       set wallet_held = greatest(wallet_held + v_hold, 0)
     where id = new.merchant_id;';
begin
  select pg_catalog.pg_get_functiondef('public.hold_prepaid_credit()'::regprocedure)
    into v_def;
  if (length(v_def) - length(replace(v_def, v_anchor, ''))) / length(v_anchor) <> 1 then
    raise exception 'hold_prepaid_credit has drifted; re-read it before making the hold conditional';
  end if;

  execute replace(v_def, v_anchor,
'    if v_hold > 0 then
      -- Taken only if it is there, under the row lock this update holds: the second of
      -- two simultaneous orders waits here, re-reads the row, and is refused (A7).
      update public.merchants
         set wallet_held = wallet_held + v_hold
       where id = new.merchant_id
         and ((plan_id is not null and plan_expires_at > now())
              or wallet_balance - wallet_held >= v_hold);
      if not found then
        raise exception ''merchant not accepting orders'' using errcode = ''P0001'';
      end if;
    else
      update public.merchants
         set wallet_held = greatest(wallet_held + v_hold, 0)
       where id = new.merchant_id;
    end if;');
end;
$migrate$;
