-- Bounds on a draft, so an absurd one is refused in a sentence rather than a stack trace.
--
-- Probing `place_order` with values no app would send turned up three refusals that are
-- not refusals at all — they are Postgres errors escaping through a hole in the
-- classification:
--
--   quantity 200000     -> 22003 integer out of range   (v_subtotal is an int4, and
--                                                        12000 * 200000 overflows it)
--   quantity 2147483647 -> 22003 integer out of range
--   itemId "not-a-uuid" -> 22P02 invalid input syntax
--
-- None is classified by `Failure.from`, so each arrives at the customer as
-- `UnknownFailure` and reads "حصل خطأ — جرّب تاني". The order was never going to succeed;
-- what is wrong is that nothing can say why, and nothing in the logs distinguishes it
-- from a genuine fault.
--
-- Nobody taps "+" a hundred and eighty thousand times. But `place_order` is reachable
-- with the anon key, which sits inside every APK, and a boundary that only holds for
-- well-behaved callers is not a boundary.

create or replace function public.check_draft_bounds(p_draft jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_line jsonb;
  v_id   text;
begin
  -- One basket, one shop, one trip. Fifty lines is a party order; a thousand is a script.
  if jsonb_array_length(coalesce(p_draft -> 'items', '[]'::jsonb)) > 50 then
    raise exception 'too many different items in one order' using errcode = 'P0001';
  end if;

  for v_line in select * from jsonb_array_elements(coalesce(p_draft -> 'items', '[]'::jsonb))
  loop
    -- Well under what overflows the subtotal even at the priciest dish in the city, and
    -- far past anything a kitchen would cook for one order.
    if coalesce((v_line ->> 'quantity')::int, 0) > 200 then
      raise exception 'that is more of one dish than anybody can order'
        using errcode = 'P0001';
    end if;

    -- A malformed id is the caller's mistake, and saying so beats `invalid input syntax
    -- for type uuid` arriving at somebody's phone.
    v_id := v_line ->> 'itemId';
    if v_id is null or v_id !~ '^[0-9a-fA-F-]{36}$' then
      raise exception 'a line names no dish' using errcode = 'P0001';
    end if;
  end loop;

  -- The note is a sentence for the courier — "the bell is broken, knock" — not a payload.
  -- It is rendered on a phone held in the street; a hundred thousand characters of it is
  -- a screen nobody can scroll past to reach the address.
  if length(coalesce(p_draft ->> 'note', '')) > 500 then
    raise exception 'the note is too long' using errcode = 'P0001';
  end if;
end;
$$;

comment on function public.check_draft_bounds(jsonb) is
  'Refuses a draft no app would send, in a sentence the product can speak.';

-- The gate is the wrapper, where the other two "is this caller allowed at all" checks
-- already live. Before the pricing function, so an absurd draft never reaches the
-- arithmetic that would overflow on it.
create or replace function public.place_order(p_draft jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if auth.uid() is null then
    raise exception 'sign in to place an order' using errcode = '42501';
  end if;

  if exists (select 1 from public.users where id = auth.uid() and is_blocked) then
    raise exception 'this account cannot place orders' using errcode = '42501';
  end if;

  perform public.check_draft_bounds(p_draft);

  return public.place_order_priced(p_draft);
end;
$fn$;

revoke execute on function public.place_order(jsonb) from public, anon;
