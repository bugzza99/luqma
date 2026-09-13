-- Who attached a courier is the server's to say, not the client's.
--
-- `courier_merchants.attached_by` is a plain nullable column, and `owner_manages_own_roster`
-- lets an owner or an admin write the row directly. So a direct write could put anybody's
-- uid there — a shop owner recording that the platform admin attached the rider, or an
-- admin crediting a colleague. `attach_courier_by_phone` already stamps `auth.uid()`
-- itself; the direct path had nothing doing the same.
--
-- The rule is the one `record_commission_payment` and `review_staff_application` follow:
-- **the actor is `auth.uid()`, never a parameter**, because a record that can be lied to is
-- not evidence. And it is enforced here rather than by trusting every repository to leave
-- the field alone, which is exactly the trust a row written by a phone has not earned.
--
-- The timestamp gets the same treatment: `attached_at` was a client clock on this path,
-- and "when was this rider given platform work" is a question somebody asks after money has
-- gone missing.
create or replace function public.stamp_courier_attachment()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $fn$
begin
  -- Server functions that already declare themselves keep what they wrote. Everything
  -- else — a phone — is overwritten with who actually made the request, and when.
  if coalesce(current_setting('app.server_mode', true), '') <> 'on' then
    -- Only an attachment is stamped. A detach is also an update, and overwriting
    -- `attached_by` with whoever switched the rider off would record the wrong person
    -- under a column that says who switched them on.
    if tg_op = 'INSERT'
       or (new.is_active and not coalesce(old.is_active, false)) then
      new.attached_by := auth.uid();
      new.attached_at := now();
    else
      new.attached_by := old.attached_by;
      new.attached_at := old.attached_at;
    end if;
  end if;
  return new;
end;
$fn$;

drop trigger if exists courier_merchants_stamp on public.courier_merchants;
create trigger courier_merchants_stamp
  before insert or update on public.courier_merchants
  for each row execute function public.stamp_courier_attachment();
