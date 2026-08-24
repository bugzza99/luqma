-- Live queries, stage three of the move off Firebase.
--
-- Firestore streamed any query. Supabase streams row changes only for tables added to
-- the supabase_realtime publication — and a watched table missing from it does not
-- fail anywhere; it just never tells anybody, which is worse than failing. Tables join
-- here on the day the first live stream moves onto them.
alter publication supabase_realtime add table home_sections;

-- ---------------------------------------------------------------- reorder

-- Reordering the home, in one statement.
--
-- The Firestore version wrote N updates in one batch, and the reason is recorded there:
-- a half-applied reorder would leave two sections claiming the same position, and the
-- screen would settle on whichever loaded first. PostgREST can send one statement or N
-- statements, but no batch of updates — so the batch becomes this function. All rows
-- land on their position or none of them does.
create function public.reorder_home_sections(p_keys text[])
returns void
language sql
as $$
  update home_sections s
    set sort_order = k.ord - 1
    from unnest(p_keys) with ordinality as k(key, ord)
    where s.key = k.key;
$$;

-- Every function is executable by PUBLIC in Postgres unless told otherwise, and nobody
-- but staff has any business rearranging the customer's home. `service_role` stays
-- allowed: it speaks for the server — Edge Functions, the nightly pass — and for the
-- live tests, which reach the database exactly as production will.
revoke execute on function public.reorder_home_sections(text[]) from public, anon;
grant execute on function public.reorder_home_sections(text[]) to authenticated;
grant execute on function public.reorder_home_sections(text[]) to service_role;
