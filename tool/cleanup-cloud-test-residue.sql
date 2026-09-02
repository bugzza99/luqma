-- Cleanup for the dedicated cloud test project. It covers Flutter's `live-*` fixtures,
-- every stack-suite city prefix, transient config/plans, auth accounts and test media.
-- cleanup-cloud.mjs refuses to execute this file unless the exact `luqma-test` project
-- ref is supplied, so no production data can ever be in scope.
-->>

-- Freeze the exact set first. Stack suites use their own prefixes while Flutter live
-- suites use `live-*`; a cancelled runner must not make the next run depend on which
-- suite happened to be active.
create temporary table luqma_test_cities on commit drop as
select id from cities
 where id like 'live-%'
    or id in ('admin-test-city', 'jobs-test-city', 'rls-test-city')
    or id ~ '^(collect|img|settle|money|rbf)-[0-9]+$';
-->>

-- Money first, and it has to be. `order_settlements.order_id` and
-- `commission_payments.merchant_id` are both `on delete restrict`, because a record that
-- somebody was charged must not be removable by deleting the order or the shop it belongs
-- to. Nothing in the product deletes either; only this script and the test teardowns do,
-- and one that forgets these two fails on `23503` partway through — leaving the residue
-- half-cleared, which is worse than not having run it.
delete from commission_payments
 where merchant_id in (select id from merchants where city_id in (select id from luqma_test_cities));
-->>
delete from order_settlements
 where merchant_id in (select id from merchants where city_id in (select id from luqma_test_cities))
    or order_id in (select id from orders where city_id in (select id from luqma_test_cities));
-->>
delete from coupon_redemptions
 where order_id in (select id from orders where city_id in (select id from luqma_test_cities))
    or coupon_id in (select id from coupons where city_id in (select id from luqma_test_cities));
-->>
delete from ratings
 where order_id in (select id from orders where city_id in (select id from luqma_test_cities))
    or merchant_id in (select id from merchants where city_id in (select id from luqma_test_cities));
-->>
delete from order_issues
 where order_id in (select id from orders where city_id in (select id from luqma_test_cities))
    or merchant_id in (select id from merchants where city_id in (select id from luqma_test_cities));
-->>
delete from audit_log
 where merchant_id in (select id from merchants where city_id in (select id from luqma_test_cities));
-->>
delete from subscriptions
 where merchant_id in (select id from merchants where city_id in (select id from luqma_test_cities));
-->>
delete from menu_items
 where merchant_id in (select id from merchants where city_id in (select id from luqma_test_cities));
-->>
delete from menu_categories
 where merchant_id in (select id from merchants where city_id in (select id from luqma_test_cities));
-->>
delete from merchant_served_zones
 where merchant_id in (select id from merchants where city_id in (select id from luqma_test_cities))
    or zone_id in (select id from zones where city_id in (select id from luqma_test_cities));
-->>
delete from staff
 where merchant_id in (select id from merchants where city_id in (select id from luqma_test_cities));
-->>
delete from coupons where city_id in (select id from luqma_test_cities);
-->>
delete from daily_meals where city_id in (select id from luqma_test_cities);
-->>
delete from promotions where city_id in (select id from luqma_test_cities);
-->>
delete from orders where city_id in (select id from luqma_test_cities);
-->>
delete from home_sections where city_id in (select id from luqma_test_cities);
-->>
delete from landmarks where city_id in (select id from luqma_test_cities);
-->>
delete from merchants where city_id in (select id from luqma_test_cities);
-->>
delete from zones where city_id in (select id from luqma_test_cities);
-->>
delete from cities where id in (select id from luqma_test_cities);
-->>
delete from config where key like 'live\_test\_%' escape '\';
-->>
delete from plans where id in ('money-basic', 'jobs-test-plan');
-->>
-- The dedicated test project carries no product media. Clear both halves together so a
-- cancelled upload test cannot slowly fill Storage while the database looks empty.
select set_config('storage.allow_delete_query', 'true', true);
-->>
delete from storage.objects where bucket_id = 'media';
-->>
delete from media;
-->>
-- The test accounts go through auth.users so the cascade takes their profile and staff
-- rows with them, exactly as production deletion would. This is intentionally every
-- account: the exact-project guard in cleanup-cloud.mjs makes this a test-only database.
delete from auth.users;
