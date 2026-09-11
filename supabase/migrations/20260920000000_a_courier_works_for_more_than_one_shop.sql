-- A courier in Edku works for several shops, and the schema could only hold one.
--
-- `staff.merchant_id` is a scalar and the access-token hook copies it into the JWT as a
-- single `merchant_id` claim, which `belongs_to_merchant` and `is_courier_for` both read.
-- Three shops do not fit in that field. So a rider who delivers for the fish place and
-- the koshari place either had two accounts, or one shop lost the capacity — and the
-- September design pack proposed the join table for exactly that reason.
--
-- **Only the courier relationship becomes many-to-many.** An owner stays bound to one
-- merchant, so `is_merchant_owner` — the predicate that guards prices, acceptance and the
-- money — is not touched by any of this. Widening the one that guards reads is a much
-- smaller blast radius than widening the one that guards writes.
--
-- **And the attachment is read from the table, not from the token.** A claim would be
-- faster and would be wrong the moment it mattered: a merchant attaches a rider at eight
-- in the evening and the rider's token already says otherwise, so they see nothing until
-- they sign out and back in — on the shift they were attached for. The predicates already
-- read `staff` for `is_active_staff()`, so this is one more read on a path that was
-- already going to the table. `CLAUDE.md` records the same lesson from the other end: a
-- dismissal is a boundary change rather than a claim change.

create table courier_merchants (
  id           uuid primary key default gen_random_uuid(),
  courier_uid  uuid not null references public.staff (uid) on delete cascade,
  -- Null is the platform: home kitchens, and the merchants that do not deliver for
  -- themselves. A courier may hold shop rows and the platform row at once, which is the
  -- arrangement the design asked for and the one the old exclusive `scope` could not say.
  merchant_id  uuid references public.merchants on delete cascade,
  is_active    boolean not null default true,
  attached_at  timestamptz not null default now(),
  attached_by  uuid references auth.users on delete set null
);

comment on table courier_merchants is
  'Which shops a courier carries for. Null merchant_id is the platform. The authority on '
  'courier access — the merchant_id claim on the token speaks only for owners.';

-- A primary key cannot carry the platform row, because its merchant is null. Two partial
-- indexes say the same thing without pretending null is a value.
create unique index courier_merchants_one_per_shop
  on courier_merchants (courier_uid, merchant_id) where merchant_id is not null;
create unique index courier_merchants_one_platform
  on courier_merchants (courier_uid) where merchant_id is null;
create index courier_merchants_merchant_idx
  on courier_merchants (merchant_id) where is_active;

-- ---------------------------------------------------------------- what is there already

-- Every courier that exists keeps exactly the reach they have today. A migration that
-- widened a boundary and narrowed an existing account at the same time would be two
-- changes wearing one commit message.
insert into courier_merchants (courier_uid, merchant_id)
select uid, merchant_id from public.staff
 where role = 'courier' and scope = 'merchant' and merchant_id is not null
on conflict do nothing;

insert into courier_merchants (courier_uid, merchant_id)
select uid, null from public.staff
 where role = 'courier' and scope = 'platform'
on conflict do nothing;

-- ---------------------------------------------------------------- the predicates

-- One place to ask the question, so the four callers below cannot drift apart.
create or replace function public.courier_carries(m uuid) returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
      from public.courier_merchants cm
      join public.staff s on s.uid = cm.courier_uid
     where cm.courier_uid = (select auth.uid())
       and cm.is_active
       and s.is_active
       and s.role = 'courier'
       and (
         -- A named shop, or the platform when the caller asked about the platform.
         (m is not null and cm.merchant_id = m)
         or (m is null and cm.merchant_id is null)
       )
  );
$fn$;

-- `security definer` for the same reason `is_active_staff` needs it: a courier has no
-- read policy that would let them see another courier's attachment rows, and a predicate
-- that returns false because RLS filtered its own lookup is a predicate that fails open
-- in the wrong direction — silently, and only for the accounts it is about.
revoke execute on function public.courier_carries(uuid) from public, anon;
grant execute on function public.courier_carries(uuid) to authenticated, service_role;

-- Reads widen. The owner path is the claim exactly as before; the courier path asks the
-- table. Everything that reads a merchant's menu, hours, orders and shop row goes through
-- this, which is what a rider needs to do their job and nothing more.
create or replace function public.belongs_to_merchant(m uuid) returns boolean
language sql stable as $fn$
  select m is not null
     and public.is_active_staff()
     and (public.claim('merchant_id')::uuid = m or public.courier_carries(m));
$fn$;

create or replace function public.is_courier_for(m uuid) returns boolean
language sql stable as $fn$
  select m is not null and public.courier_carries(m);
$fn$;

-- Platform coverage is a row now rather than an exclusive scope, so a courier can carry
-- the home kitchens and two shops at once. The old shape — `scope = 'platform'` — is still
-- honoured, because the rows above were written from it and an account created before this
-- migration must not lose the platform the day it runs.
create or replace function public.is_platform_courier() returns boolean
language sql stable as $fn$
  select public.is_active_staff()
     and public.staff_role() = 'courier'
     and (public.staff_scope() = 'platform' or public.courier_carries(null));
$fn$;

-- ---------------------------------------------------------------- who may read it

alter table courier_merchants enable row level security;
alter table courier_merchants force row level security;
grant select on courier_merchants to authenticated;

-- A courier sees their own attachments — the merchant app draws them a list of the shops
-- they carry for. An owner sees the roster of their own shop. An admin sees everything.
create policy read_own_courier_merchants on courier_merchants
  for select to authenticated
  using (
    courier_uid = (select auth.uid())
    or public.is_merchant_owner(merchant_id)
    or public.is_admin()
  );

-- Attaching and detaching is the owner's, for their own shop only, and the admin's for
-- anybody. **Both clauses, and the `using` is what stops a row being moved to another
-- merchant by an owner who may write it.** A platform row (null merchant) is an admin's
-- alone: `is_merchant_owner(null)` is false, which is the answer rather than an accident.
grant insert, update, delete on courier_merchants to authenticated;
create policy owner_manages_own_roster on courier_merchants
  for all to authenticated
  using (public.is_merchant_owner(merchant_id) or public.is_admin())
  with check (public.is_merchant_owner(merchant_id) or public.is_admin());
