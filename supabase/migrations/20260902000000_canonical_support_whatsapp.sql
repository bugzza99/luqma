-- Seed the canonical snake_case key from the value released clients/admins used.
-- The legacy row remains for old clients and this is safe to replay.
insert into public.config (key, value)
select 'support_whatsapp', legacy.value
from public.config as legacy
where legacy.key = 'supportWhatsapp'
on conflict (key) do nothing;
