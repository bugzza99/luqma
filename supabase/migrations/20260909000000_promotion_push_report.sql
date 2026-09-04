-- Approval needs more than `promotions.pushed_at`: the outcome lives in an
-- outbox no phone may read. Exposing those rows would reveal one customer per campaign;
-- counting them here keeps that boundary closed while still answering the operator's
-- four questions about the send.

-- One outbox row per customer per campaign makes a sequential scan grow with every
-- audience ever targeted. The report always asks for this JSON key and only marketing
-- rows carry it for this purpose, so the expression index is both usable by the lookup
-- and smaller than indexing the operational notification history beside it.
create index push_outbox_promotion_idx
  on public.push_outbox ((data ->> 'promotionId'))
  where channel = 'marketing' and data ->> 'promotionId' is not null;

-- Exhausted is its own count because it is not another spelling of waiting: a row below
-- five attempts may still move on the next drain, while a row at five will never be
-- claimed again. Combining them would hide the only outcome that needs investigation.
--
-- The five is `claim_push_batch`'s, not this function's — it is the drain that decides
-- when a row stops being retried, and this only reports the consequence. The number is
-- written in both places, so a cap that moves has to move here as well or the screen
-- starts calling rows dead that the drain will still pick up.
--
-- SECURITY DEFINER is necessary because `push_outbox` deliberately grants no client
-- read. The grant is still only the coarse signed-in door; the guard is the authority,
-- and `is_admin()` checks both the claim and the caller's current active staff row. The
-- two layers keep a later accidental grant from turning this aggregate into public data.
create or replace function public.promotion_push_report(p_promotion_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if auth.uid() is null or not public.is_admin() then
    raise exception 'only an admin reads a push report' using errcode = '42501';
  end if;

  return (
    select pg_catalog.jsonb_build_object(
      'queued', count(*),
      'sent', count(*) filter (where sent_at is not null),
      'waiting', count(*) filter (where sent_at is null and attempts < 5),
      'failed', count(*) filter (where sent_at is null and attempts >= 5)
    )
      from public.push_outbox
     where channel = 'marketing'
       and data ->> 'promotionId' = p_promotion_id::text
  );
end;
$fn$;

revoke all on function public.promotion_push_report(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.promotion_push_report(uuid) to authenticated;
