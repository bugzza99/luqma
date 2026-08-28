-- Cleanup of test residue left on the cloud project by an earlier test_live run
-- against the hosted database (2026-08-25). Everything targets rows the harness owns:
-- cities named `live-*` and accounts with a `luqma.test` e-mail. The real Edku data is
-- never touched.
-->>

delete from coupon_redemptions
 where order_id in (select id from orders where city_id like 'live-%')
    or coupon_id in (select id from coupons where city_id like 'live-%');
-->>
delete from ratings
 where order_id in (select id from orders where city_id like 'live-%')
    or merchant_id in (select id from merchants where city_id like 'live-%');
-->>
delete from order_issues
 where order_id in (select id from orders where city_id like 'live-%')
    or merchant_id in (select id from merchants where city_id like 'live-%');
-->>
delete from audit_log
 where merchant_id in (select id from merchants where city_id like 'live-%');
-->>
delete from subscriptions
 where merchant_id in (select id from merchants where city_id like 'live-%');
-->>
delete from menu_items
 where merchant_id in (select id from merchants where city_id like 'live-%');
-->>
delete from menu_categories
 where merchant_id in (select id from merchants where city_id like 'live-%');
-->>
delete from merchant_served_zones
 where merchant_id in (select id from merchants where city_id like 'live-%')
    or zone_id in (select id from zones where city_id like 'live-%');
-->>
delete from staff
 where merchant_id in (select id from merchants where city_id like 'live-%');
-->>
delete from coupons where city_id like 'live-%';
-->>
delete from daily_meals where city_id like 'live-%';
-->>
delete from promotions where city_id like 'live-%';
-->>
delete from orders where city_id like 'live-%';
-->>
delete from home_sections where city_id like 'live-%';
-->>
delete from landmarks where city_id like 'live-%';
-->>
delete from merchants where city_id like 'live-%';
-->>
delete from zones where city_id like 'live-%';
-->>
delete from cities where id like 'live-%';
-->>
-- The test accounts go through auth.users so the cascade takes their profile and staff
-- rows with them, exactly as production deletion would.
delete from auth.users where email like '%luqma.test';
