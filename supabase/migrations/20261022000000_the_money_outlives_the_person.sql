-- H-06 and M-05: a financial record outlives the person or the shop it is about.
--
-- The owner's rule, settled 2026-09-20: «الدين يفضل، والشخص هو اللي يروح». The product
-- already works that way for orders — `orders.customer_uid` is nullable and `on delete
-- set null`, the frozen contact fields are scrubbed, and the money stays, because the
-- merchant's statement and the platform's own accounts are built from those rows.
--
-- The money tables never got the same treatment, and ended up with **three different
-- answers to one question**, none of them the rule above:
--
--   * `courier_commission_payments.courier_uid` → `staff` ON DELETE **RESTRICT**, and
--     `payment_receipts.courier_uid` → `staff` ON DELETE **SET NULL** under a CHECK that
--     demands it be NOT NULL. So a courier who has ever paid, or been charged, cannot be
--     deleted at all: one constraint refuses outright and the other nulls a column into a
--     CHECK violation. `admin_delete_account` is a documented feature that simply did not
--     work for that whole class of account.
--   * `payment_receipts.merchant_id` and `subscriptions.merchant_id` → **CASCADE**.
--     Deleting a shop silently took its idempotency keys and its paid subscription terms
--     with it — the receipts that exist precisely so one payment cannot be recorded twice.
--   * `commission_payments.merchant_id` → **RESTRICT**, so the same shop could not be
--     deleted anyway. The three constraints disagreed about whether deletion was possible
--     *and* about what it should cost.
--
-- One rule from here: **the row survives, the subject is nulled, and a name frozen at
-- write time keeps it readable.** A statement of payments whose payer is a null uuid is a
-- statement nobody can act on; a name is what the owner asks for on the telephone.
--
-- The name is stamped by a trigger rather than by the four functions that write these
-- tables, spread across six migrations. A rule that every writer has to remember is a
-- rule the next writer forgets.

-- ------------------------------------------------------------------ the frozen names

alter table public.courier_commission_payments
  add column if not exists courier_name text;
alter table public.commission_payments
  add column if not exists merchant_name text;
alter table public.subscriptions
  add column if not exists merchant_name text;
alter table public.payment_receipts
  add column if not exists subject_name text;

comment on column public.courier_commission_payments.courier_name is
  'Who this was collected from, as they were called at the time. Kept so the row still '
  'reads after the account is gone.';
comment on column public.payment_receipts.subject_name is
  'The shop or the courier this receipt is for, frozen at write time.';

-- Existing rows get a name from whoever they still point at. Anything already orphaned
-- stays null, which is honest: nobody recorded the name at the time.
update public.courier_commission_payments p
   set courier_name = s.name
  from public.staff s
 where s.uid = p.courier_uid and p.courier_name is null;

update public.commission_payments p
   set merchant_name = m.name
  from public.merchants m
 where m.id = p.merchant_id and p.merchant_name is null;

update public.subscriptions x
   set merchant_name = m.name
  from public.merchants m
 where m.id = x.merchant_id and x.merchant_name is null;

update public.payment_receipts r
   set subject_name = coalesce(
     (select m.name from public.merchants m where m.id = r.merchant_id),
     (select s.name from public.staff s where s.uid = r.courier_uid))
 where r.subject_name is null;

-- ------------------------------------------------------------------ stamping them

create or replace function public.stamp_payment_subject_name()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  -- `security definer` because the trigger runs as whoever ran the statement, and a
  -- courier paying their own commission has no right to read another `staff` row. The
  -- same trap the settlement and the rating refresh each fell into.
  case tg_table_name
    when 'courier_commission_payments' then
      if new.courier_name is null then
        select s.name into new.courier_name
          from public.staff s where s.uid = new.courier_uid;
      end if;
    when 'commission_payments' then
      if new.merchant_name is null then
        select m.name into new.merchant_name
          from public.merchants m where m.id = new.merchant_id;
      end if;
    when 'subscriptions' then
      if new.merchant_name is null then
        select m.name into new.merchant_name
          from public.merchants m where m.id = new.merchant_id;
      end if;
    when 'payment_receipts' then
      if new.subject_name is null then
        new.subject_name := coalesce(
          (select m.name from public.merchants m where m.id = new.merchant_id),
          (select s.name from public.staff s where s.uid = new.courier_uid));
      end if;
    else
      null;
  end case;
  return new;
end;
$fn$;

revoke all on function public.stamp_payment_subject_name() from public, anon, authenticated;

drop trigger if exists stamp_courier_payment_name on public.courier_commission_payments;
create trigger stamp_courier_payment_name
  before insert on public.courier_commission_payments
  for each row execute function public.stamp_payment_subject_name();

drop trigger if exists stamp_commission_payment_name on public.commission_payments;
create trigger stamp_commission_payment_name
  before insert on public.commission_payments
  for each row execute function public.stamp_payment_subject_name();

drop trigger if exists stamp_subscription_name on public.subscriptions;
create trigger stamp_subscription_name
  before insert on public.subscriptions
  for each row execute function public.stamp_payment_subject_name();

drop trigger if exists stamp_receipt_subject_name on public.payment_receipts;
create trigger stamp_receipt_subject_name
  before insert on public.payment_receipts
  for each row execute function public.stamp_payment_subject_name();

-- ------------------------------------------------------------------ one rule on deletion

-- `on delete set null` and `not null` cannot both be true, and the column was declared
-- not-null back when a payment was assumed to outlive nobody. The name carries the
-- meaning now, so the id is allowed to become the absence it already is.
alter table public.courier_commission_payments alter column courier_uid drop not null;
alter table public.commission_payments alter column merchant_id drop not null;
alter table public.subscriptions alter column merchant_id drop not null;


alter table public.courier_commission_payments
  drop constraint if exists courier_commission_payments_courier_uid_fkey;
alter table public.courier_commission_payments
  add constraint courier_commission_payments_courier_uid_fkey
  foreign key (courier_uid) references public.staff (uid) on delete set null;

alter table public.commission_payments
  drop constraint if exists commission_payments_merchant_id_fkey;
alter table public.commission_payments
  add constraint commission_payments_merchant_id_fkey
  foreign key (merchant_id) references public.merchants (id) on delete set null;

alter table public.subscriptions
  drop constraint if exists subscriptions_merchant_id_fkey;
alter table public.subscriptions
  add constraint subscriptions_merchant_id_fkey
  foreign key (merchant_id) references public.merchants (id) on delete set null;

alter table public.payment_receipts
  drop constraint if exists payment_receipts_merchant_id_fkey;
alter table public.payment_receipts
  add constraint payment_receipts_merchant_id_fkey
  foreign key (merchant_id) references public.merchants (id) on delete set null;

-- The CHECK that made deletion impossible, rewritten so it still says something true.
--
-- What it was really for is that a receipt names **one** subject and never both. Demanding
-- the id be present as well turned "the shop is gone" into "this row is illegal". It now
-- asks for one *or the other* form of the answer: the id while the subject exists, the
-- frozen name once it does not.
alter table public.payment_receipts
  drop constraint if exists payment_receipts_subject_check;
alter table public.payment_receipts
  add constraint payment_receipts_subject_check check (
    case kind
      when 'courierCommission'
        then merchant_id is null
             and (courier_uid is not null or subject_name is not null)
      else courier_uid is null
             and (merchant_id is not null or subject_name is not null)
    end
  );

-- ------------------------------------------------------------------ and the balance goes

-- A deleted courier's running total lives on their `staff` row and goes with it, which is
-- right: there is nobody left to collect from. The ledger keeps what was charged and what
-- was paid, which is what a dispute is settled from.
--
-- `courier_settlements.courier_uid` and `courier_settlements.order_id` are already
-- `on delete set null` and `on delete restrict` respectively, and both are correct: the
-- person may go, the order may not.
comment on table public.courier_commission_payments is
  'Cash the owner collected from a courier. Survives the courier: the id is nulled and '
  'courier_name is what the row is read by afterwards.';
