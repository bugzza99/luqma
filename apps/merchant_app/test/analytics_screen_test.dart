import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/shop/analytics_screen.dart';
import 'package:merchant_app/src/shop/shop_screen.dart';

void main() {
  final cairoNow = DateTime(2026, 9, 12, 14, 0);

  const alwaysOpen = [
    OpeningWindow(weekday: 1, openMinute: 0, closeMinute: 1440),
  ];

  Merchant shop({
    RevenueModel model = RevenueModel.commission,
    int value = 1000,
  }) =>
      Merchant(
        id: 'm1',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'مطعم الشاطئ',
        zoneId: 'z1',
        phone: '01000000000',
        status: MerchantStatus.approved,
        openingHours: alwaysOpen,
        revenueModel: model,
        revenueValue: value,
      );

  OrderLine line(String id, String name, int qty, int price) => OrderLine(
        itemId: id,
        name: name,
        quantity: qty,
        unitPrice: price,
      );

  Order makeOrder({
    required String id,
    String merchantId = 'm1',
    int subtotal = 10000,
    int deliveryFee = 1500,
    OrderStatus status = OrderStatus.delivered,
    OrderActor? cancelledBy,
    DateTime? placedAt,
    List<OrderLine> items = const [],
  }) {
    return Order(
      id: id,
      cityId: 'edku',
      orderNumber: 1,
      customerName: 'عميل',
      customerPhone: '01000000000',
      merchantId: merchantId,
      merchantName: 'مطعم',
      zoneId: 'z1',
      type: OrderType.instant,
      items: items.isEmpty
          ? [line('i1', 'سمك', 1, subtotal)]
          : items,
      pricing: OrderPricing(
        subtotal: subtotal,
        deliveryFee: deliveryFee,
        total: subtotal + deliveryFee,
      ),
      status: status,
      cancelledBy: cancelledBy,
      placedAt: placedAt ?? cairoNow,
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    List<Order> orders = const [],
    Failure? failure,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantSalesRepositoryProvider.overrideWithValue(
            FakeMerchantSalesRepository(
              seed: orders,
              failure: failure,
              now: () => cairoNow,
            ),
          ),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: AnalyticsScreen(merchantId: 'm1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('four figures', () {
    testWidgets('shows orders, food sales, average, and cancellations card',
        (tester) async {
      final fish = [line('i1', 'سمك', 2, 5000)];
      final rice = [line('i2', 'رز', 1, 6000)];

      final orders = [
        makeOrder(id: 'o1', subtotal: 10000, deliveryFee: 2000, items: fish, placedAt: cairoNow),
        makeOrder(id: 'o2', subtotal: 20000, deliveryFee: 1500, items: fish, placedAt: cairoNow.subtract(const Duration(days: 1))),
        makeOrder(id: 'o3', subtotal: 6000, deliveryFee: 1000, items: rice, placedAt: cairoNow.subtract(const Duration(days: 2))),
        makeOrder(id: 'o4', subtotal: 9000, status: OrderStatus.cancelled, cancelledBy: OrderActor.customer, placedAt: cairoNow),
        makeOrder(id: 'o5', subtotal: 9000, status: OrderStatus.cancelled, cancelledBy: OrderActor.courier, placedAt: cairoNow),
      ];

      await pump(tester, orders: orders);

      // Orders count
      expect(find.byKey(AnalyticsScreen.statOrdersKey), findsOneWidget);
      expect(find.descendant(of: find.byKey(AnalyticsScreen.statOrdersKey), matching: find.text('3')), findsOneWidget);

      // Food sales — explicitly «مبيعات الأكل», not «الإيرادات»
      expect(find.byKey(AnalyticsScreen.statSalesKey), findsOneWidget);
      expect(find.text('مبيعات الأكل'), findsOneWidget);
      expect(find.text('الإيرادات'), findsNothing);
      expect(find.descendant(of: find.byKey(AnalyticsScreen.statSalesKey), matching: find.text('360 ج')), findsOneWidget);

      // Average order
      expect(find.byKey(AnalyticsScreen.statAverageKey), findsOneWidget);
      expect(find.text('متوسط الطلب'), findsOneWidget);
      expect(find.descendant(of: find.byKey(AnalyticsScreen.statAverageKey), matching: find.text('120 ج')), findsOneWidget);

      // Cancellations and returns in one card: total 2, with why
      expect(find.byKey(AnalyticsScreen.statUnfulfilledKey), findsOneWidget);
      final unfulfilledCard = find.byKey(AnalyticsScreen.statUnfulfilledKey);
      expect(find.descendant(of: unfulfilledCard, matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: unfulfilledCard, matching: find.textContaining('من العميل')), findsOneWidget);
      expect(find.descendant(of: unfulfilledCard, matching: find.textContaining('مع الطيار')), findsOneWidget);
    });
  });

  group('range chips', () {
    testWidgets('defaults to 7 days, switches to today (1) and month (30)',
        (tester) async {
      final orders = [
        makeOrder(id: 'o1', subtotal: 10000, placedAt: cairoNow),
        makeOrder(id: 'o2', subtotal: 20000, placedAt: cairoNow.subtract(const Duration(days: 3))),
        makeOrder(id: 'o3', subtotal: 50000, placedAt: cairoNow.subtract(const Duration(days: 15))),
      ];

      await pump(tester, orders: orders);

      // Default is week (7 days): o1 and o2 included, o3 excluded
      expect(find.descendant(of: find.byKey(AnalyticsScreen.statOrdersKey), matching: find.text('2')), findsOneWidget);

      // Switch to today (1 day): only o1
      await tester.tap(find.byKey(AnalyticsScreen.rangeTodayKey));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(AnalyticsScreen.statOrdersKey), matching: find.text('1')), findsOneWidget);

      // Switch to month (30 days): o1, o2, and o3
      await tester.tap(find.byKey(AnalyticsScreen.rangeMonthKey));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(AnalyticsScreen.statOrdersKey), matching: find.text('3')), findsOneWidget);
    });
  });

  group('bar chart', () {
    testWidgets('renders days and survives a zero week without division by zero',
        (tester) async {
      await pump(tester, orders: []);

      expect(find.byKey(AnalyticsScreen.chartKey), findsOneWidget);
      // All 7 bars are present
      for (var i = 0; i < 7; i++) {
        final d = cairoNow.subtract(Duration(days: 6 - i));
        final dayStr =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        expect(find.byKey(AnalyticsScreen.barKey(dayStr)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('top dishes', () {
    testWidgets('displays each dish quantity in descending order',
        (tester) async {
      final orders = [
        makeOrder(
          id: 'o1',
          subtotal: 10000,
          items: [
            line('i2', 'شوربة سي فود', 1, 1000),
            line('i1', 'سمك بلطي', 3, 3000),
          ],
          placedAt: cairoNow,
        ),
      ];

      await pump(tester, orders: orders);

      expect(find.text('سمك بلطي'), findsOneWidget);
      expect(find.text('شوربة سي فود'), findsOneWidget);
      expect(tester.getTopLeft(find.text('سمك بلطي')).dy,
          lessThan(tester.getTopLeft(find.text('شوربة سي فود')).dy));
      for (final (id, quantity) in [('i1', 3), ('i2', 1)]) {
        expect(find.descendant(
          of: find.byKey(AnalyticsScreen.itemKey(id)),
          matching: find.text('$quantity طلب'),
        ), findsOneWidget);
      }
    });

    testWidgets('empty message when no dishes sold', (tester) async {
      await pump(tester, orders: []);

      expect(find.byKey(AnalyticsScreen.emptyTopItemsKey), findsOneWidget);
    });
  });

  group('error handling', () {
    testWidgets('failed fetch shows error view with retry', (tester) async {
      await pump(tester, failure: const OfflineFailure());

      expect(find.byType(LuqmaErrorView), findsOneWidget);
    });
  });

  group('navigation from ShopScreen', () {
    Future<void> pumpShop(WidgetTester tester, Merchant merchant) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authServiceProvider.overrideWithValue(
              FakeAuthService(
                restoring: const LuqmaIdentity(
                  uid: 'owner1',
                  claims: {'role': 'owner', 'scope': 'merchant', 'merchantId': 'm1'},
                ),
              ),
            ),
            merchantRepositoryProvider
                .overrideWithValue(FakeMerchantRepository(seed: [merchant])),
            settlementRepositoryProvider
                .overrideWithValue(FakeSettlementRepository()),
            merchantSalesRepositoryProvider
                .overrideWithValue(FakeMerchantSalesRepository(now: () => cairoNow)),
            remoteConfigServiceProvider
                .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
          ],
          child: MaterialApp(
            theme: LuqmaTheme.light,
            locale: const Locale('ar'),
            localizationsDelegates: LuqmaStrings.localizationsDelegates,
            supportedLocales: LuqmaStrings.supportedLocales,
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: ShopScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('billing card offers analytics under commission', (tester) async {
      await pumpShop(tester, shop());

      expect(find.byKey(ShopScreen.analyticsKey), findsOneWidget);
    });

    testWidgets('billing card ALSO offers analytics under subscription (not plan-gated)',
        (tester) async {
      await pumpShop(tester, shop(model: RevenueModel.subscription));

      // Statement is hidden under subscription, but analytics must be visible!
      expect(find.byKey(ShopScreen.statementKey), findsNothing);
      expect(find.byKey(ShopScreen.analyticsKey), findsOneWidget);
    });

    testWidgets('tapping analytics opens AnalyticsScreen', (tester) async {
      await pumpShop(tester, shop());

      await tester.ensureVisible(find.byKey(ShopScreen.analyticsKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ShopScreen.analyticsKey));
      await tester.pumpAndSettle();

      expect(find.byType(AnalyticsScreen), findsOneWidget);
    });
  });
}
