-- A menu starts with four shelves, and the owner hears when a shop asks for an advert.
--
-- The first real shop was approved on 2026-09-18 and opened a menu screen that said
-- «مفيش أقسام» and offered nothing else: the editor only draws its add-category chip above
-- a list that already has one, so an empty menu was a dead end — in the partner app and in
-- AdminApp alike, since both use the same editor. The owner of the shop asked for his menu
-- in four parts; that is also the shape nearly every shop in Edku has, so it is where every
-- restaurant starts now. They are ordinary categories: renamed, reordered or added to from
-- the same editor.
--
-- A home kitchen gets none. It has no standing menu — what it sells is today's meal — and
-- four empty shelves would be the first thing a cook had to delete.

create or replace function public.seed_default_menu_categories(p_merchant_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.menu_categories (merchant_id, name, sort_order)
  select p_merchant_id, shelf.name, shelf.sort_order
    from (values
      ('الوجبات الأساسية', 0),
      ('العروض',           1),
      ('الإضافات',          2),
      ('المشروبات',         3)
    ) as shelf(name, sort_order)
   where not exists (
     select 1 from public.menu_categories where merchant_id = p_merchant_id
   );
$$;

-- Nobody calls this from a phone: the trigger below and the backfill are its only callers.
revoke all on function public.seed_default_menu_categories(uuid) from public, anon, authenticated;

create or replace function public.merchants_start_with_shelves()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.type = 'restaurant' then
    perform public.seed_default_menu_categories(new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists merchants_start_with_shelves on public.merchants;
create trigger merchants_start_with_shelves
  after insert on public.merchants
  for each row execute function public.merchants_start_with_shelves();

-- The shops that already exist with an empty menu — «ابو حاتم» among them. A shop that has
-- any category at all is left exactly as it is.
select public.seed_default_menu_categories(m.id)
  from public.merchants m
 where m.type = 'restaurant'
   and not exists (select 1 from public.menu_categories c where c.merchant_id = m.id);

-- ---------------------------------------------------------- The owner hears about it

-- When each shop last woke the admins about an advert. Nobody reads or writes it but the
-- trigger below: row security on, no policy, no grant.
create table if not exists public.promotion_request_pings (
  merchant_id      uuid primary key references public.merchants on delete cascade,
  last_notified_at timestamptz not null
);
alter table public.promotion_request_pings enable row level security;
alter table public.promotion_request_pings force row level security;
revoke all on public.promotion_request_pings from public, anon, authenticated;

-- A shop asking for a banner or a push to its customers is somebody waiting on an answer,
-- and until now it arrived silently: the request sat in the promotions queue until the
-- owner happened to open it. Only a *request* is announced — an admin's own placement is
-- created approved and there is nobody to tell.
create or replace function public.notify_admins_of_promotion_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin    record;
  v_merchant text;
  v_what     text;
begin
  if new.status <> 'requested' then
    return new;
  end if;

  -- One announcement per shop per ten minutes. A request is a row the shop may write as
  -- often as it likes, and each one fans out to every admin on the queue the order alarms
  -- share — so without this, a shop tapping «اطلب» in a loop would put its adverts ahead of
  -- somebody's unanswered order.
  --
  -- The clock is a row of its own, not the promotions table: a request's `created_at` is
  -- only stamped by the server on some paths, so it can be backdated past a window read
  -- from it; and a window counted over *pending* requests reopens the moment an admin
  -- answers one. The lock makes two requests arriving together one decision.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('promotion-request-push:' || new.merchant_id::text, 0));
  if exists (
    select 1 from public.promotion_request_pings
     where merchant_id = new.merchant_id
       and last_notified_at > now() - interval '10 minutes'
  ) then
    return new;
  end if;

  insert into public.promotion_request_pings (merchant_id, last_notified_at)
  values (new.merchant_id, now())
  on conflict (merchant_id) do update set last_notified_at = excluded.last_notified_at;

  select name into v_merchant from public.merchants where id = new.merchant_id;
  v_what := case new.channel
              when 'push'           then 'إشعار للعملاء'
              when 'homeBanner'     then 'بانر في الرئيسية'
              when 'categoryBanner' then 'بانر في قسم'
              else 'ظهور في الأول'
            end;

  for v_admin in
    select uid from public.staff
     where scope = 'platform' and role = 'admin' and is_active
  loop
    insert into public.push_outbox (uid, title, body, data, channel)
    values (
      v_admin.uid,
      'طلب إعلان جديد',
      coalesce(v_merchant, 'محل') || ' — ' || v_what,
      pg_catalog.jsonb_build_object('kind', 'promotionRequest', 'promotionId', new.id::text),
      -- Not the critical channel: an advert can wait for the owner to look, an unanswered
      -- order cannot, and sharing the alarm teaches somebody to ignore it.
      'orders'
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists promotions_notify_admins on public.promotions;
create trigger promotions_notify_admins
  after insert on public.promotions
  for each row execute function public.notify_admins_of_promotion_request();
