-- Orders join realtime: three apps watch them live.
select public.add_table_to_realtime('orders');
select public.add_table_to_realtime('order_issues');
