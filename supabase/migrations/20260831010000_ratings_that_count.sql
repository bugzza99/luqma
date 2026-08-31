-- Ratings that reach a number, a rating for the food itself, and what a shop says it is.
--
-- `merchants.rating_avg` and `rating_count` have existed since the first schema and
-- **nothing has ever written them**. The customer rates, the row lands in `ratings`, the
-- merchant reads the individual comments on their shop screen — and the figure on the
-- customer's card stays 0.0 for ever, however many people rate. Every card in the city
-- shows the same zero, which reads as "nobody has rated this" rather than as a column
-- nobody fills in. That is the answer to "where is the rating": it is collected, stored,
-- and never counted.

-- ---------------------------------------------------------------------------
-- What the customers said about the shop
-- ---------------------------------------------------------------------------

-- Recomputed from the rows rather than nudged.
--
-- An incremental average (`avg = (avg*n + stars) / (n+1)`) is one rounding error per
-- rating, compounding, and it has no way back once it drifts. Edku is one city: the
-- aggregate over a merchant's ratings is a handful of rows behind an index, and it is
-- right by construction every time it runs.
create or replace function public.refresh_merchant_rating(p_merchant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_prior text;
begin
  -- `merchants.rating_avg` is deliberately absent from `merchants_guard_columns`, and a
  -- `security definer` owner does not satisfy that guard — it asks whether a trusted
  -- server function has *declared itself*. Restored afterwards, because this runs inside
  -- the caller's transaction and leaving it on would stand every guard down for whatever
  -- that transaction did next.
  v_prior := coalesce(current_setting('app.server_mode', true), '');
  perform set_config('app.server_mode', 'on', true);

  update public.merchants m
     set rating_avg = coalesce(agg.avg_stars, 0),
         rating_count = coalesce(agg.n, 0)
    from (
      select round(avg(stars)::numeric, 2) avg_stars, count(*)::int n
        from public.ratings
       where merchant_id = p_merchant_id
    ) agg
   where m.id = p_merchant_id;

  perform set_config('app.server_mode', v_prior, true);
end;
$$;

revoke all on function public.refresh_merchant_rating(uuid) from anon, authenticated;

create or replace function public.on_rating_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The trigger runs as whoever ran the statement — the customer — and calls a function
  -- revoked from `authenticated`. Without `security definer` here too, rating a shop
  -- fails outright with "permission denied for function", which is the same trap the
  -- delivery settlement fell into.
  perform public.refresh_merchant_rating(coalesce(new.merchant_id, old.merchant_id));
  return coalesce(new, old);
end;
$$;

create trigger ratings_refresh_merchant
  after insert or update or delete on ratings
  for each row execute function public.on_rating_changed();

-- Every rating already in the table, counted at last.
select public.refresh_merchant_rating(id) from merchants;

-- ---------------------------------------------------------------------------
-- What they said about the food
-- ---------------------------------------------------------------------------

alter table menu_items
  add column rating_avg numeric(3,2) not null default 0
    check (rating_avg between 0 and 5),
  add column rating_count integer not null default 0
    check (rating_count >= 0);

-- One row per dish per order, so "did this person eat this" is answerable.
--
-- Keyed on the pair rather than given its own id: a customer rating the same dish on the
-- same order twice is a correction, not a second opinion, and a primary key is a cheaper
-- way to say that than a policy that has to remember to check.
create table item_ratings (
  order_id     uuid not null references orders on delete cascade,
  item_id      uuid not null references menu_items on delete cascade,
  merchant_id  uuid not null references merchants on delete cascade,
  customer_uid uuid not null references auth.users on delete cascade,
  stars        smallint not null check (stars between 1 and 5),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (order_id, item_id)
);

create index item_ratings_item_idx on item_ratings (item_id);

create or replace function public.refresh_item_rating(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.menu_items mi
     set rating_avg = coalesce(agg.avg_stars, 0),
         rating_count = coalesce(agg.n, 0)
    from (
      select round(avg(stars)::numeric, 2) avg_stars, count(*)::int n
        from public.item_ratings
       where item_id = p_item_id
    ) agg
   where mi.id = p_item_id;
end;
$$;

revoke all on function public.refresh_item_rating(uuid) from anon, authenticated;

create or replace function public.on_item_rating_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.refresh_item_rating(coalesce(new.item_id, old.item_id));
  return coalesce(new, old);
end;
$$;

create trigger item_ratings_refresh_item
  after insert or update or delete on item_ratings
  for each row execute function public.on_item_rating_changed();

alter table item_ratings enable row level security;
grant select, insert, update on item_ratings to authenticated;
grant select on item_ratings to anon;

-- Anybody may read them: the stars on a dish are the point of collecting them.
create policy read_item_ratings on item_ratings for select to anon, authenticated
  using (true);

-- Only for food you were actually delivered.
--
-- `using` and `with check` both spelled out, and both name the order: a policy resting on
-- `customer_uid = auth.uid()` alone lets somebody rate a dish from an order that is not
-- theirs by writing their own uid onto it, and one written only as `with check` refuses
-- every correction.
create policy rate_own_delivered_item on item_ratings for insert to authenticated
  with check (
    customer_uid = auth.uid()
    and exists (
      select 1 from public.orders o
       where o.id = order_id
         and o.customer_uid = auth.uid()
         and o.status = 'delivered'
         and o.merchant_id = item_ratings.merchant_id
    )
  );

create policy correct_own_item_rating on item_ratings for update to authenticated
  using (
    customer_uid = auth.uid()
    and exists (
      select 1 from public.orders o
       where o.id = order_id and o.customer_uid = auth.uid()
    )
  )
  with check (
    customer_uid = auth.uid()
    and exists (
      select 1 from public.orders o
       where o.id = order_id
         and o.customer_uid = auth.uid()
         and o.merchant_id = item_ratings.merchant_id
    )
  );

-- ---------------------------------------------------------------------------
-- What a shop says it is
-- ---------------------------------------------------------------------------

-- One line, and the length is enforced here rather than trusted to a text field.
--
-- It sits on a card beside the name and the stars, and a card is a fixed height: three
-- hundred characters of prose does not overflow the box, it silently truncates, and the
-- merchant who wrote it never sees which half was thrown away.
alter table merchants add column description text
  check (description is null or char_length(description) <= 120);

comment on column merchants.description is
  'One line about the shop, shown on its card. Bounded because the card is not.';

-- And the merchant may write it. `merchants_guard_columns` lists what a shop owns about
-- itself; a description they cannot edit is a column only an admin can fill in, which for
-- six hundred merchants is six hundred phone calls.
drop trigger merchants_guard_columns on merchants;
create trigger merchants_guard_columns before update on merchants for each row
  execute function public.guard_columns(
    '{name,phone,description,logo_media_id,cover_media_id,opening_hours,paused_until,min_order,delivery_fee_override}');
