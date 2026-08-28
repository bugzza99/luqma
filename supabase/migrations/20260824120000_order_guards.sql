-- The server-side mirror of `Merchant.acceptsOrdersAt`.
--
-- Until now only the phone asked whether a merchant was open, which meant an order sent
-- around the app - by a stale client, a modified one, or a hand-written request - was
-- priced, accepted and dispatched while the kitchen was shut or the prepaid wallet had
-- run dry. With cash, the phone's opinion is a courtesy; this function is the rule.
--
-- Every clause mirrors the Dart exactly:
--   status approved, pause expired, prepaid wallet covers one more fee,
--   and at least one opening window covering `now`.
--
-- Hours read in `Africa/Cairo`: the windows are minutes-from-midnight typed by people
-- in Edku, and the device clocks that compare against them run Cairo time. A server in
-- UTC must not turn a kitchen's 11pm closing into 9pm.
create or replace function public.merchant_open_at(
  p_opening_hours jsonb,
  p_at            timestamptz
)
returns boolean
language plpgsql
immutable
as $$
declare
  v_local     timestamp := p_at at time zone 'Africa/Cairo';
  v_minute    integer   := extract(hour from v_local)::int * 60
                           + extract(minute from v_local)::int;
  v_dow       integer   := extract(dow from v_local)::int;              -- Sunday = 0
  v_today     integer   := case when v_dow = 0 then 7 else v_dow end;   -- Monday = 1 … Sunday = 7, as DateTime.weekday counts
  v_yesterday integer   := case when v_today = 1 then 7 else v_today - 1 end;
  w           jsonb;
  v_open      integer;
  v_close     integer;
begin
  for w in select * from jsonb_array_elements(p_opening_hours) loop
    v_open  := coalesce((w ->> 'openMinute')::int, -1);
    v_close := coalesce((w ->> 'closeMinute')::int, -1);
    continue when v_open < 0 or v_close < 0;

    if v_close > v_open then
      -- A window inside one day.
      if (w ->> 'weekday')::int = v_today
         and v_minute >= v_open and v_minute < v_close then
        return true;
      end if;
    else
      -- An overnight window covers two calendar days: the evening of its own weekday,
      -- and the small hours of the day after. Checking only the clock would also
      -- reopen the merchant on the *morning* of its own weekday, hours before it
      -- ever opened.
      if ((w ->> 'weekday')::int = v_today and v_minute >= v_open)
         or ((w ->> 'weekday')::int = v_yesterday and v_minute < v_close) then
        return true;
      end if;
    end if;
  end loop;

  return false;
end;
$$;
