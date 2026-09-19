-- A landmark suggestion can be turned down, and stays turned down.
--
-- «مقترحة» in the places screen is built from what customers typed on their own orders
-- because the list lacked their landmark. The owner could accept one and could not refuse
-- one: a misspelling, a joke, a private house — it came back every time the screen opened,
-- for as long as the orders that named it were recent (QA review 2026-09-19).
--
-- A refusal is remembered by its folded spelling within the zone, the same key the
-- suggestion list groups by, so every spelling of the same refused name stays gone.

create table if not exists public.dismissed_landmark_suggestions (
  zone_id      uuid not null references public.zones on delete cascade,
  folded_name  text not null,
  dismissed_by uuid references auth.users on delete set null,
  created_at   timestamptz not null default now(),
  primary key (zone_id, folded_name)
);

alter table public.dismissed_landmark_suggestions enable row level security;
alter table public.dismissed_landmark_suggestions force row level security;
revoke all on public.dismissed_landmark_suggestions from public, anon;
grant select, insert, delete on public.dismissed_landmark_suggestions to authenticated;

create policy admin_dismissed_suggestions on public.dismissed_landmark_suggestions
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin() and dismissed_by = auth.uid());
