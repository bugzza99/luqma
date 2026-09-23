-- «اليوم» on the owner's screen is Edku's today (E7), and the unanswered-order queue carries
-- the shop's phone (D6).
--
-- E7. `admin_today` and `admin_statistics` cut days, weeks and months with
-- `date_trunc(..., now())`, which on hosted Postgres is UTC — two or three hours behind
-- Edku. Everything between Edku's midnight and that hour (Ramadan's suhoor orders, the
-- late-night rush) was counted in the previous day, and at 1am the owner's «اليوم» showed
-- yesterday. The rest of the schema already reasons in Cairo time — `meal_is_reservable`,
-- the day keys, `record_app_open` — so these two now do as well, through one helper.
--
-- D6. The sheet for an order nobody answered offered «كلّم المحل» only if a separate read
-- of the shop had already finished, which on that sheet it never had: an auto-dispose
-- stream read once with nobody listening. The queue is built by joining the shop anyway,
-- so it carries the shop's phone and the sheet reads it from the item it was opened on.
--
-- Both functions are patched in place from their current bodies, carriage returns stripped
-- first: a function created from a Windows checkout keeps CRLF in its source.

create or replace function public.cairo_start_of(p_unit text)
returns timestamptz
language sql
stable
set search_path = ''
as $fn$
  select pg_catalog.date_trunc(p_unit, pg_catalog.now() at time zone 'Africa/Cairo')
           at time zone 'Africa/Cairo';
$fn$;

comment on function public.cairo_start_of(text) is
  'The start of the current day, week or month in Edku, as an instant. What «اليوم», '
  '«الأسبوع» and «الشهر» mean on the owner''s screens.';

do $migrate$
declare
  v_def text;
begin
  select pg_catalog.pg_get_functiondef('public.admin_today()'::regprocedure) into v_def;
  v_def := replace(v_def, chr(13), '');
  if (length(v_def) - length(replace(v_def, 'date_trunc(''day'', now())', '')))
     / length('date_trunc(''day'', now())') <> 3
     or position('''merchantName'', m.name)' in v_def) = 0 then
    raise exception 'admin_today has drifted; re-read it before moving it to Cairo time';
  end if;
  v_def := replace(v_def, 'date_trunc(''day'', now())', 'public.cairo_start_of(''day'')');
  v_def := replace(v_def, '''merchantName'', m.name)',
                          '''merchantName'', m.name, ''merchantPhone'', m.phone)');
  execute v_def;

  select pg_catalog.pg_get_functiondef('public.admin_statistics()'::regprocedure) into v_def;
  v_def := replace(v_def, chr(13), '');
  if (length(v_def) - length(replace(v_def, 'date_trunc(''week'', now())', '')))
     / length('date_trunc(''week'', now())') <> 2
     or (length(v_def) - length(replace(v_def, 'date_trunc(''month'', now())', '')))
     / length('date_trunc(''month'', now())') <> 2 then
    raise exception 'admin_statistics has drifted; re-read it before moving it to Cairo time';
  end if;
  v_def := replace(v_def, 'date_trunc(''week'', now())', 'public.cairo_start_of(''week'')');
  v_def := replace(v_def, 'date_trunc(''month'', now())', 'public.cairo_start_of(''month'')');
  execute v_def;
end;
$migrate$;
