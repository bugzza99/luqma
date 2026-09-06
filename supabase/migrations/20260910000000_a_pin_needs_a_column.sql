-- The pin the models have always carried, and the database never could.
--
-- `Landmark` and `Address` in Dart have had `lat` and `lng` since Phase 1, and
-- `docs/09-geography-and-maps.md` specifies both: landmarks are drawn as Luqma's own
-- marker layer over the branded map, and an address may carry an optional pin. Neither
-- column has ever existed. `SupabaseAddressRepository._saved` lists the fields it may
-- write and leaves the two out with a comment saying that sending a key no column has
-- would fail the write — honest about the gap, and the gap stayed.
--
-- So the map layer is not a missing screen on top of working data. There is nowhere to
-- put a coordinate, which is why it is the first thing to fix.
--
-- Nullable everywhere and required nowhere. Edku is addressed by zone and landmark and
-- words, deliberately — the map is the supporting layer, not the primary one — so an
-- address with no pin stays as valid as it is today, and the thirty landmarks already
-- entered keep working while somebody places them one at a time.
alter table public.landmarks
  add column lat double precision,
  add column lng double precision;

alter table public.addresses
  add column lat double precision,
  add column lng double precision;

-- A coordinate that is not on Earth is a typo, and the cheapest place to refuse it is
-- here. A transposed pair — Edku is near 31.3 N, 30.3 E, and the two are easy to swap —
-- still lands inside these bounds, so this catches the malformed rather than the merely
-- wrong. What catches the wrong one is a person looking at the marker.
--
-- `(lat is null) = (lng is null)` rather than the obvious
-- `(lat is null and lng is null) or (…between…)`. The obvious form is wrong, and quietly:
-- with lat = 5 and lng null the first branch is false and the second is
-- `true and null` = null, so the whole check evaluates to null — which Postgres treats as
-- **satisfied**. Half a pin went in without complaint. `is null` always yields a boolean,
-- so comparing the two can never be null and the pairing is genuinely enforced.
alter table public.landmarks
  add constraint landmarks_pin_is_on_earth check (
    (lat is null) = (lng is null)
    and (lat is null or (lat between -90 and 90 and lng between -180 and 180))
  );

alter table public.addresses
  add constraint addresses_pin_is_on_earth check (
    (lat is null) = (lng is null)
    and (lat is null or (lat between -90 and 90 and lng between -180 and 180))
  );

-- Both halves or neither. A latitude with no longitude is not a partial pin, it is a
-- value nothing can draw, and it would reach the courier's screen as a marker in the
-- Gulf of Guinea rather than as no marker at all.
comment on column public.addresses.lat is
  'Optional pin. Null unless the customer dropped one; paired with lng by a check.';
comment on column public.landmarks.lat is
  'Optional pin, placed by an admin. The marker layer draws only landmarks that have one.';

-- ------------------------------------------------- the column guards learn the new names

-- `addresses` has no column guard of its own — a customer owns their address row and RLS
-- already limits them to it — so nothing to widen there. `landmarks` is admin-written and
-- likewise carries no per-column guard. Recorded here because the absence is the kind of
-- thing that reads as an oversight later: it was checked.
