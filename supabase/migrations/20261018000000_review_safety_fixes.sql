-- Boundaries found by the whole-repository safety review.
--
-- NOT VALID preserves any historical row that needs an operator decision while still
-- enforcing the rule for every new insert and update immediately.

alter table public.staff
  drop constraint if exists staff_role_matches_scope;
alter table public.staff
  add constraint staff_role_matches_scope check (
    (scope = 'platform' and role in ('admin', 'moderator', 'courier'))
    or (scope = 'merchant' and role in ('owner', 'courier'))
  ) not valid;

alter table public.staff_documents
  drop constraint if exists staff_documents_paths_are_distinct;
alter table public.staff_documents
  add constraint staff_documents_paths_are_distinct check (
    id_front_path <> id_back_path
    and id_front_path <> selfie_path
    and id_back_path <> selfie_path
  ) not valid;

-- Owners may remove a failed upload, but not a file currently serving as their verified
-- document. Replacing the row first makes the old object unreferenced and deletable.
drop policy if exists staff_docs_delete on storage.objects;
create policy staff_docs_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'staff-docs'
    and (
      public.is_admin()
      or (
        split_part(name, '/', 1) = (select auth.uid())::text
        and not exists (
          select 1
            from public.staff_documents d
           where d.uid = (select auth.uid())
             and name in (d.id_front_path, d.id_back_path, d.selfie_path)
        )
      )
    )
  );

-- The original sweep started from staff_documents rows, so an auth cascade or document
-- replacement made the only row it knew how to inspect disappear and left the sensitive
-- objects forever. Keep the retention pass, then garbage-collect every unreferenced
-- staff-doc object after the same grace period.
create or replace function public.sweep_staff_documents()
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_removed integer := 0;
  v_uid     uuid;
begin
  for v_uid in select uid from public.staff_documents loop
    perform public.refresh_staff_documents_retention(v_uid);
  end loop;

  perform pg_catalog.set_config('storage.allow_delete_query', 'true', true);

  with due as (
    select uid, id_front_path, id_back_path, selfie_path
      from public.staff_documents
     where purge_after is not null
       and purge_after <= pg_catalog.now()
  ), paths as (
    select d.uid, p as object_name
      from due d, unnest(array[d.id_front_path, d.id_back_path, d.selfie_path]) as p
  ), gone as (
    delete from storage.objects o using paths
     where o.bucket_id = 'staff-docs'
       and o.name = paths.object_name
    returning 1
  )
  delete from public.staff_documents d using due where d.uid = due.uid;

  get diagnostics v_removed = row_count;

  delete from storage.objects o
   where o.bucket_id = 'staff-docs'
     and o.created_at <= pg_catalog.now()
         - pg_catalog.make_interval(days => public.staff_docs_grace_days())
     and not exists (
       select 1
         from public.staff_documents d
        where o.name in (d.id_front_path, d.id_back_path, d.selfie_path)
     );

  return v_removed;
end;
$fn$;

revoke all on function public.sweep_staff_documents()
  from public, anon, authenticated;
grant execute on function public.sweep_staff_documents() to service_role;

alter table public.orders
  drop constraint if exists orders_prep_minutes_check;
alter table public.orders
  add constraint orders_prep_minutes_check
  check (prep_minutes is null or prep_minutes between 3 and 180) not valid;

-- A disabled account, or an account whose role/scope changed, must lose the old token's
-- authority now rather than when its JWT eventually refreshes.
create or replace function public.is_active_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
      from public.staff s
     where s.uid = (select auth.uid())
       and s.is_active
       -- Legacy tokens and a few internal jobs may omit a claim; a claim that is present
       -- must agree with today's row. Real staff tokens issued by the hook carry both.
       and (public.claim('scope') is null or s.scope = public.claim('scope'))
       and (public.claim('role') is null or s.role = public.claim('role'))
       and (
         public.claim('merchant_id') is null
         or s.merchant_id::text = public.claim('merchant_id')
       )
  );
$fn$;

revoke execute on function public.is_active_staff() from public;
grant execute on function public.is_active_staff() to anon, authenticated, service_role;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(public.claim('admin')::boolean, false)
     and exists (
       select 1 from public.staff s
        where s.uid = (select auth.uid())
          and s.scope = 'platform'
          and s.role = 'admin'
          and s.is_active
     );
$fn$;

revoke execute on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated, service_role;

-- Reissue only claims that agree with the current row, and remove any stale custom
-- values before doing so. In particular, merchant/admin is never an admin.
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  claims jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  meta   jsonb := coalesce(claims -> 'app_metadata', '{}'::jsonb)
                  - array['role', 'scope', 'merchant_id', 'admin'];
  s      record;
begin
  select scope, role, merchant_id
    into s
    from public.staff
   where uid = (event ->> 'user_id')::uuid
     and is_active;

  if found then
    meta := meta || jsonb_build_object('role', s.role, 'scope', s.scope);

    if s.merchant_id is not null then
      meta := meta || jsonb_build_object('merchant_id', s.merchant_id);
    end if;

    if s.scope = 'platform' and s.role = 'admin' then
      meta := meta || jsonb_build_object('admin', true);
    end if;
  end if;

  return jsonb_set(event, '{claims,app_metadata}', meta);
end;
$fn$;

revoke execute on function public.custom_access_token_hook(jsonb)
  from public, anon, authenticated;
grant execute on function public.custom_access_token_hook(jsonb)
  to supabase_auth_admin;

-- SECURITY DEFINER helpers are trigger implementation details. PostgreSQL grants
-- function execution to PUBLIC by default, so revoking only named client roles left an
-- indirect grant in place.
revoke all on function public.refresh_merchant_rating(uuid)
  from public, anon, authenticated;
revoke all on function public.refresh_item_rating(uuid)
  from public, anon, authenticated;

-- Clamp the client-controlled limit so one anonymous request cannot turn this shelf
-- helper into an unbounded scan of order snapshots.
create or replace function public.popular_items(p_city_id text, p_limit integer default 12)
returns table (
  id uuid,
  merchant_id uuid,
  merchant_name text,
  category_id uuid,
  name text,
  description text,
  price integer,
  media_id uuid,
  image_url text,
  rating_avg numeric,
  rating_count integer,
  ordered_count bigint
)
language sql
stable
security definer
set search_path = ''
as $fn$
  with counted as (
    select (line ->> 'itemId')::uuid item_id,
           sum((line ->> 'quantity')::int) n
      from public.orders o
      cross join lateral jsonb_array_elements(o.items) line
     where o.city_id = p_city_id
       and o.status = 'delivered'
       and (line ->> 'itemId') is not null
     group by 1
  )
  select mi.id,
         mi.merchant_id,
         m.name,
         mi.category_id,
         mi.name,
         mi.description,
         mi.price,
         mi.media_id,
         case when md.status = 'approved' then md.url end,
         mi.rating_avg,
         mi.rating_count,
         coalesce(c.n, 0)
    from public.menu_items mi
    join public.merchants m on m.id = mi.merchant_id
    left join counted c on c.item_id = mi.id
    left join public.media md on md.id = mi.media_id
   where m.city_id = p_city_id
     and m.status = 'approved'
     and mi.is_available
   order by coalesce(c.n, 0) desc, mi.rating_avg desc, mi.rating_count desc, mi.name
   limit least(greatest(coalesce(p_limit, 12), 1), 50);
$fn$;

revoke all on function public.popular_items(text, integer) from public;
grant execute on function public.popular_items(text, integer) to anon, authenticated;

-- Older courier receipts kept the resulting balance but not the cash amount. Recover
-- that amount from the append-only audit entry so a reused receipt can be proved to name
-- the same payment. Rows with no matching audit evidence stay unverified and are refused
-- by the function below rather than silently accepting a different amount.
with receipt_amounts as (
  select distinct on (detail->>'receipt')
         detail->>'receipt' as receipt_id,
         detail->>'courier' as courier_uid,
         (detail->>'amount')::integer as amount
    from public.audit_log
   where action = 'recordCourierPayment'
     and detail->>'receipt' is not null
     and detail->>'amount' ~ '^[1-9][0-9]*$'
   order by detail->>'receipt', at desc
)
update public.payment_receipts pr
   set result = pr.result || pg_catalog.jsonb_build_object('amount', ra.amount)
  from receipt_amounts ra
 where pr.kind = 'courierCommission'
   and not (pr.result ? 'amount')
   and pr.id::text = ra.receipt_id
   and pr.courier_uid::text = ra.courier_uid;

-- A receipt id is idempotent only for the exact payment it names. Returning a wallet
-- or another courier's stored result would tell the handset that cash was recorded when
-- this courier's balance never moved.
create or replace function public.record_courier_payment(
  p_courier_uid uuid,
  p_amount      integer,
  p_note        text default null,
  p_receipt_id  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_actor       uuid := (select auth.uid());
  v_prior_mode  text;
  v_existing    public.payment_receipts;
  v_existing_amount integer;
  v_remaining   integer;
  v_result      jsonb;
begin
  if v_actor is null or not public.is_admin() then
    raise exception 'only an admin records a collection' using errcode = '42501';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'a payment is a positive amount' using errcode = '22023';
  end if;

  if p_receipt_id is not null then
    select * into v_existing from public.payment_receipts where id = p_receipt_id;
    if found then
      if v_existing.kind <> 'courierCommission'
         or v_existing.courier_uid is distinct from p_courier_uid
         or v_existing.merchant_id is not null then
        raise exception 'receipt belongs to another payment' using errcode = '23505';
      end if;

      if v_existing.result ? 'amount'
         and v_existing.result->>'amount' ~ '^[1-9][0-9]*$' then
        v_existing_amount := (v_existing.result->>'amount')::integer;
      else
        -- A receipt made by the immediately preceding release can still be verified from
        -- the audit row that release wrote in the same transaction.
        select (detail->>'amount')::integer
          into v_existing_amount
          from public.audit_log
         where action = 'recordCourierPayment'
           and detail->>'receipt' = p_receipt_id::text
           and detail->>'courier' = p_courier_uid::text
           and detail->>'amount' ~ '^[1-9][0-9]*$'
         order by at desc
         limit 1;

        if v_existing_amount is not null then
          update public.payment_receipts
             set result = result || pg_catalog.jsonb_build_object(
               'amount', v_existing_amount)
           where id = p_receipt_id;
        end if;
      end if;

      if v_existing_amount is null then
        raise exception 'receipt amount cannot be verified' using errcode = '23505';
      end if;
      if v_existing_amount <> p_amount then
        raise exception 'receipt belongs to another payment' using errcode = '23505';
      end if;
      return v_existing.result;
    end if;
  end if;

  perform 1
    from public.staff
   where uid = p_courier_uid
     and role = 'courier'
   for update;
  if not found then
    raise exception 'no such courier' using errcode = 'P0002';
  end if;

  v_prior_mode := coalesce(pg_catalog.current_setting('app.server_mode', true), '');
  perform pg_catalog.set_config('app.server_mode', 'on', true);

  insert into public.courier_commission_payments
    (courier_uid, amount, note, recorded_by)
  values
    (p_courier_uid, p_amount, nullif(pg_catalog.btrim(p_note), ''), v_actor);

  update public.staff
     set commission_owed = commission_owed - p_amount
   where uid = p_courier_uid
  returning commission_owed into v_remaining;

  perform pg_catalog.set_config('app.server_mode', v_prior_mode, true);

  insert into public.audit_log (action, actor, detail)
  values ('recordCourierPayment', v_actor,
          pg_catalog.jsonb_build_object('courier', p_courier_uid, 'amount', p_amount,
                                        'receipt', p_receipt_id));

  v_result := pg_catalog.jsonb_build_object(
    'remaining', v_remaining,
    'amount', p_amount);

  if p_receipt_id is not null then
    insert into public.payment_receipts
      (id, kind, merchant_id, courier_uid, result, recorded_by)
    values
      (p_receipt_id, 'courierCommission', null, p_courier_uid, v_result, v_actor);
  end if;

  return v_result;
end;
$fn$;

revoke execute on function public.record_courier_payment(uuid, integer, text, uuid)
  from public, anon;
grant execute on function public.record_courier_payment(uuid, integer, text, uuid)
  to authenticated, service_role;
