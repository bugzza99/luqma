-- An id cannot tell the cook what to add once the merchant has renamed or deleted
-- the extra. Copy its words and unit price with the dish, without changing the
-- optionIds or the price_line_options call that decides what was charged.
do $migrate$
declare
  v_src text;
  v_pattern text := $pattern$'optionIds', coalesce(line -> 'optionIds', '[]'::jsonb),$pattern$;
begin
  select prosrc into strict v_src from pg_proc
   where oid = 'public.place_order_priced(jsonb)'::regprocedure;

  -- Zero matches means drift; two means replace would edit more than this branch.
  if (length(v_src) - length(replace(v_src, v_pattern, ''))) / length(v_pattern) <> 1 then
    raise exception 'place_order_priced instant line has drifted; expected one optionIds field.';
  end if;
  v_src := replace(v_src, v_pattern, v_pattern || $snapshot$
                    'options', coalesce((
                      select jsonb_agg(jsonb_build_object(
                        'id', o ->> 'id', 'name', o ->> 'name',
                        'price', (o ->> 'price')::int) order by option_ord)
                      from jsonb_array_elements(m.options) with ordinality as chosen(o, option_ord)
                      where jsonb_typeof(line -> 'optionIds') = 'array'
                        and (line -> 'optionIds') ? (o ->> 'id')
                    ), '[]'::jsonb),$snapshot$);

  -- Daily meals have no menu row and no priced extras. Never echo a draft's names
  -- here: that would ask the cook for something the server did not charge for.
  v_pattern := $pattern$'optionsTotal', 0,$pattern$;
  if (length(v_src) - length(replace(v_src, v_pattern, ''))) / length(v_pattern) <> 1 then
    raise exception 'place_order_priced pre-order line has drifted; expected one zero optionsTotal.';
  end if;
  v_src := replace(v_src, v_pattern, v_pattern || $snapshot$
                    'options', '[]'::jsonb,$snapshot$);

  execute format(
    'create or replace function public.place_order_priced(p_draft jsonb) '
    'returns jsonb language plpgsql security definer set search_path = '''' as %L',
    v_src);
end;
$migrate$;
