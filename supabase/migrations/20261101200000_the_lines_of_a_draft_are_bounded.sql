-- Every line of a draft is a whole number of a dish, with a bounded note and a bounded
-- list of extras.
--
-- `check_draft_bounds` cast `quantity` with `::int`, so «1.5» escaped as 22P02 — an error
-- the phone has no sentence for — and nothing bounded a line's own `note` or `optionIds`,
-- which `place_order_priced` copies onto the order at whatever length arrived. The
-- order's note and the complaint are bounded; a line was the one free text left that a
-- hand-written request could fill with a megabyte, on a row every admin, merchant and
-- courier screen then reads. The app caps a line note at 120; 500 leaves room.
--
-- The function is small and wholly replaced. Its existing rules keep their sentences and
-- codes (the phone maps two of them); what is new is refused as a bad request, 22023.

create or replace function public.check_draft_bounds(p_draft jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_line jsonb;
  v_id   text;
begin
  if p_draft -> 'items' is not null
     and jsonb_typeof(p_draft -> 'items') <> 'array' then
    raise exception 'the items of an order are a list' using errcode = '22023';
  end if;

  -- One basket, one shop, one trip. Fifty lines is a party order; a thousand is a script.
  if jsonb_array_length(coalesce(p_draft -> 'items', '[]'::jsonb)) > 50 then
    raise exception 'too many different items in one order' using errcode = 'P0001';
  end if;

  for v_line in select * from jsonb_array_elements(coalesce(p_draft -> 'items', '[]'::jsonb))
  loop
    if jsonb_typeof(v_line) <> 'object' then
      raise exception 'a line of an order is an object' using errcode = '22023';
    end if;

    -- A whole number, read before it is cast: «1.5» or «two» is the caller's mistake
    -- and says so, rather than arriving as `invalid input syntax for type integer`.
    if v_line ->> 'quantity' is not null and v_line ->> 'quantity' !~ '^[0-9]+$' then
      raise exception 'a line quantity is a whole number' using errcode = '22023';
    end if;

    -- Well under what overflows the subtotal even at the priciest dish in the city, and
    -- far past anything a kitchen would cook for one order. The length is asked first so
    -- a number past what an int holds gets this sentence rather than an overflow.
    if char_length(v_line ->> 'quantity') > 6
       or coalesce((v_line ->> 'quantity')::int, 0) > 200 then
      raise exception 'that is more of one dish than anybody can order'
        using errcode = 'P0001';
    end if;

    -- A malformed id is the caller's mistake, and saying so beats `invalid input syntax
    -- for type uuid` arriving at somebody's phone.
    v_id := v_line ->> 'itemId';
    if v_id is null or v_id !~ '^[0-9a-fA-F-]{36}$' then
      raise exception 'a line names no dish' using errcode = 'P0001';
    end if;

    if char_length(v_line ->> 'note') > 500 then
      raise exception 'a line note is at most 500 characters' using errcode = '22023';
    end if;

    if v_line -> 'optionIds' is not null and jsonb_typeof(v_line -> 'optionIds') <> 'null'
       and (jsonb_typeof(v_line -> 'optionIds') <> 'array'
            or jsonb_array_length(v_line -> 'optionIds') > 30
            or exists (
                 select 1 from jsonb_array_elements(v_line -> 'optionIds') o
                  where jsonb_typeof(o) <> 'string' or char_length(o #>> '{}') > 64)) then
      raise exception 'the extras on a line are at most 30 short ids' using errcode = '22023';
    end if;
  end loop;

  -- The note is a sentence for the courier — "the bell is broken, knock" — not a payload.
  -- It is rendered on a phone held in the street; a hundred thousand characters of it is
  -- a screen nobody can scroll past to reach the address.
  if length(coalesce(p_draft ->> 'note', '')) > 500 then
    raise exception 'the note is too long' using errcode = 'P0001';
  end if;
end;
$function$;
