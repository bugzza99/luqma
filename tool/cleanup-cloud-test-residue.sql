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
    or id ~ '^(collect|img|settle|money|rbf|marketing|delete-account)-[0-9]+$';
-->>

-- Money first, and it still has to be, though the reason narrowed on 2026-09-21.
-- `order_settlements.order_id` is `on delete restrict`: a settlement is evidence of a
-- charge and the order must not be able to take it with it, so a teardown that forgets it
-- fails on `23503` partway through and leaves the residue half-cleared — worse than not
-- having run at all.
--
-- The shop-side money rows no longer restrict: `commission_payments`, `subscriptions` and
-- `payment_receipts` are `on delete set null` since 20261022000000, so a shop can be
-- deleted and its payments survive it, named by the frozen `merchant_name`. They are
-- still deleted explicitly here, and they have to be — set to null they would no longer
-- match the city filter below, and every run would leave a few more orphans behind that
-- nothing else ever removes.
delete from commission_payments
 where merchant_id in (select id from merchants where city_id in (select id from luqma_test_cities));
-->>
-- Receipts and courier payments used to leave with their subject: the first cascaded from
-- the shop, the second was impossible to orphan because the shop could not be deleted
-- while it existed. Both survive a deletion now, so both need removing by name or every
-- run leaves a few more rows nothing will ever collect.
delete from payment_receipts
 where merchant_id in (select id from merchants where city_id in (select id from luqma_test_cities))
    or courier_uid in (
      select uid from staff where merchant_id in (
        select id from merchants where city_id in (select id from luqma_test_cities)));
-->>
delete from courier_commission_payments
 where courier_uid in (
   select uid from staff where merchant_id in (
     select id from merchants where city_id in (select id from luqma_test_cities)));
-->>
delete from courier_settlements
 where order_id in (select id from orders where city_id in (select id from luqma_test_cities));
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
-- The marketing fan-out queues one row per opted-in customer, so a single test campaign
-- leaves as many rows as the project has accounts — and unlike the rest of this script
-- they are not reachable through a city. Only the undrained ones go: a sent row is the
-- record that something was actually delivered.
delete from push_outbox where channel = 'marketing' and sent_at is null;
-->>
delete from promotions where city_id in (select id from luqma_test_cities);
-->>
delete from orders where city_id in (select id from luqma_test_cities);
-->>
delete from home_sections where city_id in (select id from luqma_test_cities);
-->>
-- Addresses reference zones (and landmarks), they are otherwise only removed by the auth.users
-- cascade at the end, so a test-city zone with an address on it refuses its delete with 23503 and
-- the whole cleanup rolls back.
delete from addresses
 where zone_id in (select id from zones where city_id in (select id from luqma_test_cities));
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
-- The same for a courier's identity papers. `staff_documents` cascades from `auth.users`
-- below, so the row would go on its own -- the objects would not, and these are national
-- ID photographs rather than a menu picture nobody minds leaving behind.
delete from storage.objects where bucket_id = 'staff-docs';
-->>
delete from staff_documents;
-->>
-- The test accounts go through auth.users so the cascade takes their profile and staff
-- rows with them, exactly as production deletion would. This is intentionally every
-- account: the exact-project guard in cleanup-cloud.mjs makes this a test-only database.
delete from auth.users;
