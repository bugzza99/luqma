-- A customer is told only what is news.
--
-- `queue_order_status_push` told a customer «الأوردر اتلغى» for an order they had just
-- cancelled themselves, phone still in hand. And a status push that failed was retried
-- on the spacing that exists so a join application reaches an admin who installs the app
-- that evening (`push_retry_delay`) — so «اتقبل طلبك» could land seven hours after the
-- food had. An order's news is news for half an hour; after that the row is retired
-- (attempts = 5, which also takes it out of the queue's partial index) rather than sent.
-- The kitchen's alarm, the admin's needsAttention and everything else keep their retries.
--
-- Both functions are patched in place; each anchor must match exactly once.

do $migrate$
declare
  v_def text;
  v_old_cancel constant text := '    when ''cancelled'' then
      v_title := ''الأوردر اتلغى'';';
  v_old_claim constant text := 'begin
  return query
  with claimed as (';
begin
  select pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), chr(13), '') into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'queue_order_status_push';
  if (length(v_def) - length(replace(v_def, v_old_cancel, ''))) / length(v_old_cancel) <> 1 then
    raise exception 'queue_order_status_push has drifted; re-read it before patching.';
  end if;
  execute replace(v_def, v_old_cancel, '    when ''cancelled'' then
      -- They pressed the button; telling them is telling them what they just did.
      if new.cancelled_by is not distinct from ''customer'' then
        return new;
      end if;
      v_title := ''الأوردر اتلغى'';');

  select pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), chr(13), '') into v_def
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'claim_push_batch';
  if (length(v_def) - length(replace(v_def, v_old_claim, ''))) / length(v_old_claim) <> 1 then
    raise exception 'claim_push_batch has drifted; re-read it before patching.';
  end if;
  execute replace(v_def, v_old_claim, 'begin
  -- An order update half an hour old is not news; retire it rather than send it.
  update public.push_outbox o
     set attempts = 5,
         last_error = ''too late to be news''
   where o.sent_at is null
     and o.attempts < 5
     and o.data ->> ''kind'' = ''orderStatus''
     and o.created_at < now() - interval ''30 minutes'';

  return query
  with claimed as (');
end;
$migrate$;
