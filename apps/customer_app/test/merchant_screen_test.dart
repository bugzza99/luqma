import 'package:customer_app/src/cart/cart.dart';
import 'package:customer_app/src/cart/cart_controller.dart';
import 'package:customer_app/src/merchant/merchant_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  // Every day, all day. A single weekday here would make every "can add" test pass or
  // fail depending on what day the suite happens to run.
  const alwaysOpen = [
    OpeningWindow(weekday: DateTime.monday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.tuesday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.wednesday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.thursday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.friday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.saturday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.sunday, openMinute: 0, closeMinute: 1440),
  ];

  const shore = Merchant(
    id: 'm1',
    cityId: 'edku',
    type: MerchantType.restaurant,
    name: 'مطعم الشاطئ',
    zoneId: 'z1',
    phone: '01000000000',
    status: MerchantStatus.approved,
    minOrder: 5000,
    openingHours: alwaysOpen,
    menuCategories: [MenuCategory(id: 'c1', name: 'مشويات')],
  );

  const chicken = MenuItem(
    id: 'i1',
    merchantId: 'm1',
    categoryId: 'c1',
    name: 'فراخ مشوية',
    price: 12000,
    description: 'نص فرخة على الفحم',
  );
  const soldOut = MenuItem(
    id: 'i2',
    merchantId: 'm1',
    categoryId: 'c1',
    name: 'سمك بلطي',
    price: 9000,
    isAvailable: false,
  );

  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    Merchant merchant = shore,
    List<MenuItem> items = const [chicken, soldOut],
    Cart startingCart = Cart.empty,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: [merchant])),
          menuRepositoryProvider.overrideWithValue(
            FakeMenuRepository(categories: merchant.menuCategories, items: items),
          ),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
          if (startingCart.isNotEmpty)
            cartProvider.overrideWith(() => CartController.seeded(startingCart)),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return const Directionality(
                textDirection: TextDirection.rtl,
                child: MerchantScreen(merchantId: 'm1'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the menu', () {
    testWidgets('items are listed with their price', (tester) async {
      await pump(tester);

      expect(find.text('فراخ مشوية'), findsOneWidget);
      expect(find.text('120 ج'), findsOneWidget);
    });

    // Removing it would leave a regular wondering whether they misremembered the menu.
    testWidgets('an unavailable item stays visible, marked', (tester) async {
      await pump(tester);

      expect(find.text('سمك بلطي'), findsOneWidget);
      expect(find.byKey(MerchantScreen.soldOutKey('i2')), findsOneWidget);
    });

    testWidgets('an unavailable item cannot be added', (tester) async {
      await pump(tester);

      await tester.tap(find.text('سمك بلطي'));
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantScreen.itemSheetKey), findsNothing);
    });
  });

  group('adding to the basket', () {
    testWidgets('an item goes in and the bar appears', (tester) async {
      await pump(tester);

      await tester.tap(find.text('فراخ مشوية'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantScreen.addToCartKey));
      await tester.pumpAndSettle();

      expect(container.read(cartProvider).itemCount, 1);
      expect(find.byKey(MerchantScreen.cartBarKey), findsOneWidget);
    });

    testWidgets('the bar is absent while the basket is empty', (tester) async {
      await pump(tester);
      expect(find.byKey(MerchantScreen.cartBarKey), findsNothing);
    });
  });

  group('a basket that belongs to another kitchen', () {
    const otherCart = Cart(
      merchantId: 'm2',
      lines: [
        CartLine(
          id: 'x',
          itemId: 'i9',
          merchantId: 'm2',
          name: 'كشري',
          unitPrice: 4000,
          quantity: 1,
        ),
      ],
    );

    testWidgets('adding asks before throwing the basket away', (tester) async {
      await pump(tester, startingCart: otherCart);

      await tester.tap(find.text('فراخ مشوية'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantScreen.addToCartKey));
      await tester.pumpAndSettle();

      // Never silently: the basket is somebody's decisions, and losing it without being
      // asked is worse than the inconvenience of the question.
      expect(find.byKey(MerchantScreen.replaceCartKey), findsOneWidget);
      expect(container.read(cartProvider).merchantId, 'm2');
    });

    testWidgets('confirming starts a new basket here', (tester) async {
      await pump(tester, startingCart: otherCart);

      await tester.tap(find.text('فراخ مشوية'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantScreen.addToCartKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantScreen.confirmReplaceKey));
      await tester.pumpAndSettle();

      final cart = container.read(cartProvider);
      expect(cart.merchantId, 'm1');
      expect(cart.lines.single.name, 'فراخ مشوية');
    });

    testWidgets('declining leaves the old basket untouched', (tester) async {
      await pump(tester, startingCart: otherCart);

      await tester.tap(find.text('فراخ مشوية'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantScreen.addToCartKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantScreen.cancelReplaceKey));
      await tester.pumpAndSettle();

      expect(container.read(cartProvider).merchantId, 'm2');
      expect(container.read(cartProvider).lines.single.name, 'كشري');
    });
  });

  group('a merchant that is closed', () {
    const closed = Merchant(
      id: 'm1',
      cityId: 'edku',
      type: MerchantType.restaurant,
      name: 'مطعم الشاطئ',
      zoneId: 'z1',
      phone: '0100',
      status: MerchantStatus.approved,
      // No opening window: shut right now.
    );

    testWidgets('says so, and the menu is still readable', (tester) async {
      await pump(tester, merchant: closed);

      expect(find.byKey(MerchantScreen.closedBannerKey), findsOneWidget);
      // Browsing a closed kitchen is how somebody decides to come back later.
      expect(find.text('فراخ مشوية'), findsOneWidget);
    });

    testWidgets('nothing can be added while it is shut', (tester) async {
      await pump(tester, merchant: closed);

      await tester.tap(find.text('فراخ مشوية'));
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantScreen.itemSheetKey), findsNothing);
    });
  });
}
