-- The merchants table joins realtime: watchMerchants is a customer's home screen, and
-- an approval made in AdminApp has to reach phones already open without shipping
-- anything.
select public.add_table_to_realtime('merchants');
