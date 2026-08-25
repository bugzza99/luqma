-- Orders join realtime: three apps watch them live.
alter publication supabase_realtime add table orders;
alter publication supabase_realtime add table order_issues;
