-- Slice P1: what a plan gives a shop, server half.
--
-- The owner's decisions (2026-09-17):
-- 1. A plan can give: show first (boostRank), a «موثّق» badge (verifiedBadge),
--    N free banners a month (homeBannerSlots, counts homeBanner and categoryBanner together),
--    N free marketing pushes a month (monthlyPromotionCount, channel push).
--    The admin sets them per plan.
-- 2. Starting values: basic -> all off / 0; premium -> boostRank true, verifiedBadge true,
--    homeBannerSlots 1, monthlyPromotionCount 1. Keep any other keys in features as they are.
-- 3. Among several boosted shops the usual list order applies (nothing to build server-side).
-- 4. A shop without a plan (or past its quota) can still request; those are paid,
--    price agreed with the admin — they are just not «ضمن الباقة».

-- ------------------------------------------------------------------ A. Perks customers can see

create or replace function public.merchant_perks()
returns table(
  merchant_id uuid,
  boost       boolean,
  verified    boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    m.id as merchant_id,
    coalesce((p.features ->> 'boostRank')::boolean, false) as boost,
    coalesce((p.features ->> 'verifiedBadge')::boolean, false) as verified
  from public.merchants m
  join public.plans p on p.id = m.plan_id
 where m.status = 'approved'
   and m.plan_id is not null
   and m.plan_expires_at > now()
   and (
     coalesce((p.features ->> 'boostRank')::boolean, false) = true
     or coalesce((p.features ->> 'verifiedBadge')::boolean, false) = true
   )
 order by m.name asc;
$$;

revoke all on function public.merchant_perks() from public;
grant execute on function public.merchant_perks() to anon, authenticated, service_role;

-- ------------------------------------------------------------------ B. Free banners and pushes

alter table public.promotions
  add column if not exists included_in_plan boolean not null default false;

create or replace function public.promotions_apply_plan_quota()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plan_id         text;
  v_plan_expires_at timestamptz;
  v_features        jsonb;
  v_quota           integer := 0;
  v_used            integer := 0;
  v_now             timestamptz;
  v_start_of_month  timestamptz;
  v_end_of_month    timestamptz;
begin
  -- Admins or trusted server_mode may insert rows with arbitrary included_in_plan
  if public.is_admin() or coalesce(pg_catalog.current_setting('app.server_mode', true), '') = 'on' then
    return new;
  end if;

  -- Only homeBanner, categoryBanner, and push can qualify for quota inclusion
  if new.channel not in ('homeBanner', 'categoryBanner', 'push') then
    new.included_in_plan := false;
    return new;
  end if;

  -- One shop at a time: two requests arriving together would both count the same used
  -- slots and both be given the last one (found in review). Transaction-scoped, so it is
  -- released with the insert.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.merchant_id::text, 0));

  -- Verify merchant's active plan
  select m.plan_id, m.plan_expires_at, p.features
    into v_plan_id, v_plan_expires_at, v_features
    from public.merchants m
    left join public.plans p on p.id = m.plan_id
   where m.id = new.merchant_id;

  if v_plan_id is null or v_plan_expires_at is null or v_plan_expires_at <= now() then
    new.included_in_plan := false;
    return new;
  end if;

  if new.channel in ('homeBanner', 'categoryBanner') then
    v_quota := coalesce((v_features ->> 'homeBannerSlots')::integer, 0);
  elsif new.channel = 'push' then
    v_quota := coalesce((v_features ->> 'monthlyPromotionCount')::integer, 0);
  end if;

  if v_quota <= 0 then
    new.included_in_plan := false;
    return new;
  end if;

  -- The server's clock, and the row's stamp with it. A client that sends `created_at` two
  -- months back would otherwise land in an empty month and be given a free placement
  -- every time (found in review).
  v_now := now();
  new.created_at := v_now;
  v_start_of_month := (date_trunc('month', v_now at time zone 'Africa/Cairo'))::timestamp at time zone 'Africa/Cairo';
  v_end_of_month   := (date_trunc('month', v_now at time zone 'Africa/Cairo') + interval '1 month')::timestamp at time zone 'Africa/Cairo';

  if new.channel in ('homeBanner', 'categoryBanner') then
    select count(*)::integer into v_used
      from public.promotions
     where merchant_id = new.merchant_id
       and channel in ('homeBanner', 'categoryBanner')
       and included_in_plan = true
       and status <> 'rejected'
       and created_at >= v_start_of_month
       and created_at < v_end_of_month;
  elsif new.channel = 'push' then
    select count(*)::integer into v_used
      from public.promotions
     where merchant_id = new.merchant_id
       and channel = 'push'
       and included_in_plan = true
       and status <> 'rejected'
       and created_at >= v_start_of_month
       and created_at < v_end_of_month;
  end if;

  if v_used < v_quota then
    new.included_in_plan := true;
  else
    new.included_in_plan := false;
  end if;

  return new;
end;
$$;

create or replace function public.promotions_guard_included_in_plan()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (public.is_admin() or coalesce(pg_catalog.current_setting('app.server_mode', true), '') = 'on') then
    new.included_in_plan := old.included_in_plan;
    -- The month a placement counts against is the server's answer, not something an edit
    -- can move.
    new.created_at := old.created_at;

    -- Banners and pushes are counted separately, so an included banner edited into a push
    -- would arrive inside the push quota without ever being counted against it — two free
    -- pushes on a plan that gives one (found in review). Changing what kind of placement it
    -- is makes it an ordinary paid request again; asking for a new one spends a slot
    -- through the insert path, where the quota is actually checked.
    if old.included_in_plan and new.channel is distinct from old.channel then
      new.included_in_plan := false;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists promotions_before_insert_plan_quota on public.promotions;
create trigger promotions_before_insert_plan_quota
  before insert on public.promotions
  for each row execute function public.promotions_apply_plan_quota();

drop trigger if exists promotions_guard_included_in_plan on public.promotions;
create trigger promotions_guard_included_in_plan
  before update on public.promotions
  for each row execute function public.promotions_guard_included_in_plan();

-- ------------------------------------------------------------------ plan_allowance

create or replace function public.plan_allowance(p_merchant_id uuid)
returns table(
  banners_included int,
  banners_used     int,
  pushes_included  int,
  pushes_used      int,
  boost            boolean,
  verified         boolean,
  plan_active      boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_prior_mode      text;
  v_plan_id         text;
  v_plan_expires_at timestamptz;
  v_features        jsonb;
  v_active          boolean;
  v_start_of_month  timestamptz;
  v_end_of_month    timestamptz;
  v_banners_inc     int := 0;
  v_banners_used    int := 0;
  v_pushes_inc      int := 0;
  v_pushes_used     int := 0;
  v_boost           boolean := false;
  v_verified        boolean := false;
begin
  if auth.uid() is null then
    raise exception 'sign in to view plan allowance' using errcode = '42501';
  end if;

  if not (
    public.is_admin()
    or public.is_merchant_owner(p_merchant_id)
    or exists (
      select 1 from public.staff
       where uid = auth.uid()
         and merchant_id = p_merchant_id
         and role = 'owner'
         and is_active
    )
  ) then
    raise exception 'only the shop owner or an admin can view plan allowance' using errcode = '42501';
  end if;

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);

  select m.plan_id, m.plan_expires_at, p.features
    into v_plan_id, v_plan_expires_at, v_features
    from public.merchants m
    left join public.plans p on p.id = m.plan_id
   where m.id = p_merchant_id;

  v_active := (v_plan_id is not null and v_plan_expires_at is not null and v_plan_expires_at > now());

  if v_active then
    v_banners_inc := coalesce((v_features ->> 'homeBannerSlots')::int, 0);
    v_pushes_inc  := coalesce((v_features ->> 'monthlyPromotionCount')::int, 0);
    v_boost       := coalesce((v_features ->> 'boostRank')::boolean, false);
    v_verified    := coalesce((v_features ->> 'verifiedBadge')::boolean, false);
  end if;

  v_start_of_month := (date_trunc('month', now() at time zone 'Africa/Cairo'))::timestamp at time zone 'Africa/Cairo';
  v_end_of_month   := (date_trunc('month', now() at time zone 'Africa/Cairo') + interval '1 month')::timestamp at time zone 'Africa/Cairo';

  select count(*)::int into v_banners_used
    from public.promotions
   where merchant_id = p_merchant_id
     and channel in ('homeBanner', 'categoryBanner')
     and included_in_plan = true
     and status <> 'rejected'
     and created_at >= v_start_of_month
     and created_at < v_end_of_month;

  select count(*)::int into v_pushes_used
    from public.promotions
   where merchant_id = p_merchant_id
     and channel = 'push'
     and included_in_plan = true
     and status <> 'rejected'
     and created_at >= v_start_of_month
     and created_at < v_end_of_month;

  return query select
    v_banners_inc,
    v_banners_used,
    v_pushes_inc,
    v_pushes_used,
    v_boost,
    v_verified,
    v_active;
end;
$$;

revoke all on function public.plan_allowance(uuid) from public, anon;
grant execute on function public.plan_allowance(uuid) to authenticated, service_role;

-- ------------------------------------------------------------------ C. Starting values

update public.plans
   set features = features || jsonb_build_object(
     'boostRank', false,
     'verifiedBadge', false,
     'homeBannerSlots', 0,
     'monthlyPromotionCount', 0
   )
 where id = 'basic';

update public.plans
   set features = features || jsonb_build_object(
     'boostRank', true,
     'verifiedBadge', true,
     'homeBannerSlots', 1,
     'monthlyPromotionCount', 1
   )
 where id = 'premium';
