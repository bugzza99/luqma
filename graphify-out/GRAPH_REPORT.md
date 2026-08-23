# Graph Report - Luqma  (2026-08-22)

## Corpus Check
- Corpus is ~6,778 words - fits in a single context window. You may not need a graph.

## Summary
- 173 nodes · 304 edges · 11 communities
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 11 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Home Kitchen and Courier Fulfilment
- Order Flow and Fulfilment
- Shared Core, Media and Onboarding
- Merchant Accounts, Plans and Ratings
- Dynamic Home and Promotions
- App Shell and Platform
- Identity and Abuse Control
- Zones and Addressing
- Feature Flags and Config
- Payment and Revenue Engine
- Brand and Splash

## God Nodes (most connected - your core abstractions)
1. `merchants collection` - 18 edges
2. `orders collection` - 14 edges
3. `promotions collection` - 12 edges
4. `plans collection` - 10 edges
5. `CustomerApp` - 9 edges
6. `AdminApp` - 9 edges
7. `luqma_core shared package` - 9 edges
8. `zones collection` - 9 edges
9. `Courier Mode` - 9 edges
10. `MerchantApp` - 8 edges

## Surprising Connections (you probably didn't know these)
- `Served Zones Constraint` --references--> `zones collection`  [EXTRACTED]
  docs/09-geography-and-maps.md → docs/01-data-model.md
- `Customer Cancellation Window Policy` --references--> `orderIssues collection`  [INFERRED]
  docs/03-order-lifecycle.md → docs/01-data-model.md
- `Plan and Billing Screen` --references--> `promotions collection`  [EXTRACTED]
  docs/05-merchant-app.md → docs/01-data-model.md
- `onOrderCreate trigger` --implements--> `New Customer Flag`  [EXTRACTED]
  docs/07-backend-functions.md → docs/03-order-lifecycle.md
- `Media Moderation Queue` --references--> `Merchant Menu Management`  [INFERRED]
  docs/06-admin-app.md → docs/05-merchant-app.md

## Hyperedges (group relationships)
- **Order Fulfilment Flow** — docs_04_customer_app_checkout, docs_07_backend_functions_on_order_create, docs_05_merchant_app_order_inbox, docs_03_order_lifecycle_accept_timeout, docs_05_merchant_app_courier_mode, docs_07_backend_functions_revenue_engine, docs_03_order_lifecycle_order_state_machine [EXTRACTED 1.00]
- **Runtime Control Plane** — docs_02_dynamic_config_remote_config_service, docs_02_dynamic_config_feature_flags, docs_01_data_model_home_sections, docs_06_admin_app_home_builder, docs_01_data_model_plans, docs_06_admin_app_config_management, docs_02_dynamic_config_section_registry, docs_02_dynamic_config_ad_slot_section [EXTRACTED 1.00]
- **Trust and Abuse-Prevention Layer** — docs_03_order_lifecycle_rejection_ban, docs_06_admin_app_media_moderation, docs_06_admin_app_push_approval, docs_02_dynamic_config_otp_enabled_flag, docs_12_security_and_trust_home_kitchen_vetting, docs_12_security_and_trust_ratings_policy, docs_12_security_and_trust_firestore_security_rules [EXTRACTED 1.00]
- **Home Kitchen Pre-Order Pipeline** — docs_01_data_model_daily_meals, docs_05_merchant_app_daily_meals_publishing, docs_03_order_lifecycle_preorder_reservation, docs_07_backend_functions_on_daily_meal_reserve, docs_04_customer_app_home_kitchen_prominence, docs_05_merchant_app_platform_courier_scope, docs_12_security_and_trust_home_kitchen_vetting [EXTRACTED 1.00]
- **Zone and Landmark Addressing Stack** — docs_01_data_model_zones, docs_01_data_model_landmarks, docs_09_geography_and_maps_zone_based_addressing, docs_04_customer_app_address_picker, docs_09_geography_and_maps_delivery_fee_resolution, docs_09_geography_and_maps_served_zones_constraint, docs_09_geography_and_maps_landmark_layer [EXTRACTED 1.00]

## Communities (11 total, 0 thin omitted)

### Community 0 - "Home Kitchen and Courier Fulfilment"
Cohesion: 0.10
Nodes (28): Home Kitchen Supply Side, No Separate Driver App, auditLog collection, dailyMeals collection, staff collection, Transactional Pre-Order Quantity Reservation, Home Kitchen Home-Screen Prominence, Cash Amount To Collect (+20 more)

### Community 1 - "Order Flow and Fulfilment"
Cohesion: 0.12
Nodes (24): counters collection, menuItems collection, orderIssues collection, orders collection, Revenue Snapshot on Order, Server-Side Delivery Fee Clamp, Five-Minute Accept Timeout, Customer Cancellation Window Policy (+16 more)

### Community 2 - "Shared Core, Media and Onboarding"
Cohesion: 0.14
Nodes (21): Arabic RTL-Only Localization, Dynamic Configuration Scope Boundary, Zero-Commission Onboarding Launch Plan, luqma_core shared package, MenuEditor shared component, media collection, Compiled-In Config Defaults, Firebase Remote Config (+13 more)

### Community 3 - "Merchant Accounts, Plans and Ratings"
Cohesion: 0.12
Nodes (21): merchants collection, plans collection, ratings collection, subscriptions collection, Per-Merchant Revenue Model Switching, Derived acceptingOrders Predicate, pausedUntil Busy Window, Working Hours Ordering Gate (+13 more)

### Community 4 - "Dynamic Home and Promotions"
Cohesion: 0.15
Nodes (20): homeSections collection, promotions collection, adSlot Home Section, Deliberate Rejection of Full Server-Driven UI, Home Section Widget Registry, Customer Home Screen, Home Screen Builder, Promotions Queue (+12 more)

### Community 5 - "App Shell and Platform"
Cohesion: 0.19
Nodes (15): AdminApp, Android-First Delivery, CustomerApp, Firebase Backend, Flutter Cross-Platform Stack, Luqma Platform, MerchantApp, Multi-City Data Model, Single-City Launch (+7 more)

### Community 6 - "Identity and Abuse Control"
Cohesion: 0.29
Nodes (10): users collection, otpEnabled flag, Fake Order Defence, New Customer Flag, Rejection Count Auto-Block, Google Sign-In Auth, Unverified Phone Capture at First Order, Customer Management and Blocking (+2 more)

### Community 7 - "Zones and Addressing"
Cohesion: 0.36
Nodes (9): AddressPicker shared component, user addresses subcollection, cities collection, landmarks collection, zones collection, Zone-Based Address Picker, Zones and Landmarks Management, Unnumbered Streets Addressing Problem (+1 more)

### Community 8 - "Feature Flags and Config"
Cohesion: 0.22
Nodes (9): config/appConfig document, admobEnabled flag, Feature Flags, publicCommentsEnabled flag, Config and Feature Flag Management, Minimum Ratings Display Threshold, Ratings Visibility Policy, Small-City Reputation Risk (+1 more)

### Community 9 - "Payment and Revenue Engine"
Cohesion: 0.29
Nodes (8): Cash-Only Payment Constraint, onlinePaymentEnabled flag, RevenueEngine, Commission Revenue Model, Prepaid Wallet Revenue Model, Subscription Revenue Model, Why Subscription Precedes Commission, Phase 7 Monetization

### Community 10 - "Brand and Splash"
Cohesion: 0.32
Nodes (8): Orange Reserved For Value Signals, Android 12 Forced System Splash Problem, Luqma Colour Palette, 48px Launcher Icon Legibility Constraint, Letter Lam Bite Mark, Single Continuous Splash Screen, Vocalised Arabic Wordmark, Phase 0 Brand Foundation

## Knowledge Gaps
- **27 isolated node(s):** `Restaurant Supply Side`, `cities collection`, `config/appConfig document`, `Firebase Remote Config`, `pausedUntil Busy Window` (+22 more)
  These have ≤1 connection - possible missing edges or undocumented components.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `merchants collection` connect `Merchant Accounts, Plans and Ratings` to `Home Kitchen and Courier Fulfilment`, `Order Flow and Fulfilment`, `Shared Core, Media and Onboarding`, `Dynamic Home and Promotions`, `Payment and Revenue Engine`?**
  _High betweenness centrality (0.243) - this node is a cross-community bridge._
- **Why does `orders collection` connect `Order Flow and Fulfilment` to `Home Kitchen and Courier Fulfilment`, `Merchant Accounts, Plans and Ratings`, `Identity and Abuse Control`, `Zones and Addressing`?**
  _High betweenness centrality (0.170) - this node is a cross-community bridge._
- **Why does `promotions collection` connect `Dynamic Home and Promotions` to `Home Kitchen and Courier Fulfilment`, `Shared Core, Media and Onboarding`, `Merchant Accounts, Plans and Ratings`, `App Shell and Platform`?**
  _High betweenness centrality (0.151) - this node is a cross-community bridge._
- **What connects `Restaurant Supply Side`, `cities collection`, `config/appConfig document` to the rest of the system?**
  _27 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Home Kitchen and Courier Fulfilment` be split into smaller, more focused modules?**
  _Cohesion score 0.09523809523809523 - nodes in this community are weakly interconnected._
- **Should `Order Flow and Fulfilment` be split into smaller, more focused modules?**
  _Cohesion score 0.11956521739130435 - nodes in this community are weakly interconnected._
- **Should `Shared Core, Media and Onboarding` be split into smaller, more focused modules?**
  _Cohesion score 0.1380952380952381 - nodes in this community are weakly interconnected._