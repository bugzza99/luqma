-- A shop had a zone and a telephone number and no address.
--
-- Fine for eight phases, because a courier belonged to one merchant and knew where it was.
-- Since a rider carries for several shops, the card in their hand names a kitchen they may
-- never have been to — and the only thing the product could tell them was the zone, which
-- in Edku is «إدكو». A city name presented as where to collect is worse than a blank: it
-- looks like information.
--
-- The same shape a customer's address has, because it is the same problem and this city
-- answers it one way: a landmark people say, plus the words, plus an optional pin. The
-- zone is already on the row.
alter table merchants
  add column landmark_id   uuid references public.landmarks on delete set null,
  -- Copied beside the reference for the reason `addresses` copies it: a landmark renamed
  -- next month must not rewrite where somebody was told to go today.
  add column landmark_name text,
  add column street        text,
  add column lat           double precision,
  add column lng           double precision;

-- Both halves or neither, and on Earth. Same check as `addresses` and `landmarks`, and
-- the same reasoning: a latitude with no longitude is not half a pin, it is a marker in
-- the Gulf of Guinea. `(lat is null) = (lng is null)` rather than the obvious form,
-- because the obvious form evaluates to null for half a pin and Postgres treats null as
-- satisfied.
alter table merchants
  add constraint merchants_pin_is_on_earth check (
    (lat is null) = (lng is null)
    and (lat is null or (lat between -90 and 90 and lng between -180 and 180))
  );

comment on column merchants.street is
  'Where the shop is, in words. The zone is on this row already and the landmark is what '
  'people here actually navigate by.';

-- The owner may write all five. A shop that cannot say where it is, is a shop the owner
-- has to telephone about — six hundred times, which is the reasoning the description
-- column was added under.
drop trigger merchants_guard_columns on merchants;
create trigger merchants_guard_columns before update on merchants for each row
  execute function public.guard_columns(
    '{name,phone,description,logo_media_id,cover_media_id,opening_hours,paused_until,min_order,delivery_fee_override,landmark_id,landmark_name,street,lat,lng}');
