-- Give each app its own floor without changing the effective value already in use.
-- The legacy global row remains as the runtime fallback for old and new clients.
insert into public.config (key, value)
select app.key, legacy.value
from (
  values
    ('customer_min_supported_version'),
    ('merchant_min_supported_version'),
    ('admin_min_supported_version')
) as app(key)
join public.config as legacy on legacy.key = 'min_supported_version'
on conflict (key) do nothing;
