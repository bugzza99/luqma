-- One number, one spelling — the SQL half of `Phone.normalize`.
--
-- A second copy of a normalisation is how two spellings of one number become two
-- accounts, and `CLAUDE.md` records what that cost the last time: an admin searching
-- `٠١٠…` for a row stored as `010…`, finding nobody, and telling a customer on the
-- telephone that they had no account. This is deliberately the *same* two rules as the
-- Dart — fold the Arabic-Indic digits, drop spaces and hyphens — and nothing more, so the
-- two cannot disagree about anything else.
create or replace function public.normalise_phone(p_raw text)
returns text
language sql
immutable
set search_path = ''
as $fn$
  select regexp_replace(
           translate(btrim(coalesce(p_raw, '')),
                     '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
                     '01234567890123456789'),
           '[\s-]', '', 'g');
$fn$;

-- A shop can attach a courier, and cannot go looking through the couriers.
--
-- `courier_merchants` gave a shop a roster and no way to add to it. The owner cannot find
-- the rider either: `read_staff` shows them their own account and the staff already
-- attached to their shop, so a courier who works for the fish place is invisible to the
-- koshari place — which is correct, and is also the whole difficulty. The two are the same
-- rider and the shop has their number written on a piece of paper.
--
-- So: the owner types a number they already have, and this attaches whoever it belongs to.
-- It is deliberately **not** a search. There is no listing, no partial match, no "did you
-- mean"; an owner learns nothing they did not already know except whether the number they
-- typed belongs to a courier on this platform — which they find out by attaching anyway.
--
-- **What it will not do**: attach an owner, an admin, a moderator or an inactive account,
-- create anybody, or touch the platform row. Creating accounts stays with
-- `create-staff-account`, and the platform's own riders are the admin's to staff.
create or replace function public.attach_courier_by_phone(
  p_merchant_id uuid,
  p_phone       text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_actor uuid := auth.uid();
  v_staff public.staff;
  v_row   public.courier_merchants;
begin
  if v_actor is null
     or not (public.is_merchant_owner(p_merchant_id) or public.is_admin()) then
    raise exception 'only this shop''s owner attaches its couriers'
      using errcode = '42501';
  end if;

  -- Normalised the way every other phone lookup in this product is, because an Arabic
  -- keyboard produces ٠١٠… where the account was made with 010… — the mistake that once
  -- told a customer on the telephone that they had no account.
  select * into v_staff
    from public.staff
   where role = 'courier'
     and is_active
     and public.normalise_phone(phone) = public.normalise_phone(p_phone);

  if not found then
    raise exception 'no active courier has that number' using errcode = 'P0002';
  end if;

  -- Idempotent, and it re-activates rather than duplicating: a rider detached in March and
  -- brought back in June is the same row, and the roster should say so.
  insert into public.courier_merchants (courier_uid, merchant_id, attached_by)
  values (v_staff.uid, p_merchant_id, v_actor)
  on conflict (courier_uid, merchant_id) where merchant_id is not null
  do update set is_active = true, attached_by = v_actor, attached_at = now()
  returning * into v_row;

  return jsonb_build_object(
    'attachment', to_jsonb(v_row),
    -- The name only, and only once the number matched. Enough to confirm the right person
    -- was added; not a directory.
    'name', v_staff.name
  );
end;
$fn$;

revoke execute on function public.attach_courier_by_phone(uuid, text) from public, anon;
grant execute on function public.attach_courier_by_phone(uuid, text)
  to authenticated, service_role;
