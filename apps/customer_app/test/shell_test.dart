import 'package:customer_app/src/account/account_screen.dart';
import 'package:customer_app/src/cart/cart.dart';
import 'package:customer_app/src/cart/cart_controller.dart';
import 'package:customer_app/src/cart/cart_screen.dart';
import 'package:customer_app/src/checkout/checkout_screen.dart';
import 'package:customer_app/src/merchant/merchant_screen.dart';
import 'package:customer_app/src/orders/order_screen.dart';
import 'package:customer_app/src/orders/orders_screen.dart';
import 'package:customer_app/src/shell/customer_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The three tabs, and the one path that runs across all of them: basket → checkout →
/// the order.
void main() {
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
    openingHours: alwaysOpen,
  );

  const zones = [
    Zone(id: 'z1', cityId: 'edku', name: 'المعمورة', defaultDeliveryFee: 1000),
  ];
  const home = Address(id: 'a1', zoneId: 'z1', label: 'البيت');

  const cart = Cart(
    merchantId: 'm1',
    lines: [
      CartLine(
        id: 'l1',
        itemId: 'i1',
        merchantId: 'm1',
        name: 'فراخ مشوية',
        unitPrice: 12000,
        quantity: 2,
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester, {
    Cart startingCart = Cart.empty,
    // A phone on the identity, because the checkout now refuses to send an order the
    // courier could not call about — a signed-in customer without one is asked for it
    // there first.
    LuqmaIdentity? signedInAs = const LuqmaIdentity(
      uid: 'u1',
      name: 'أحمد',
      phone: '01000000000',
    ),
    List<HomeSection> sections = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider
              .overrideWithValue(FakeAuthService(restoring: signedInAs)),
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: const [shore])),
          menuRepositoryProvider.overrideWithValue(FakeMenuRepository()),
          homeSectionRepositoryProvider
              .overrideWithValue(FakeHomeSectionRepository(seed: sections)),
          geographyRepositoryProvider
              .overrideWithValue(FakeGeographyRepository(zones: zones)),
          addressRepositoryProvider.overrideWithValue(
            FakeAddressRepository(
              seed: signedInAs == null ? const {} : {signedInAs.uid: const [home]},
            ),
          ),
          orderRepositoryProvider.overrideWithValue(FakeOrderRepository()),
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
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: CustomerShell(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the tabs', () {
    testWidgets('open on the home', (tester) async {
      await pump(tester);

      expect(find.byType(LuqmaLockup), findsWidgets);
      expect(find.byType(OrdersScreen), findsNothing);
    });

    testWidgets('switch when tapped', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(CustomerShell.ordersTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(OrdersScreen), findsOneWidget);

      await tester.tap(find.byKey(CustomerShell.accountTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
    });

    // Each tab keeps where it was: coming back to a half-scrolled home and finding it
    // reset is the app forgetting what somebody was doing.
    testWidgets('a tab is not rebuilt from scratch when returned to',
        (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(CustomerShell.ordersTabKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CustomerShell.homeTabKey));
      await tester.pumpAndSettle();

      // All three live in one stack, so the other two are still in the tree.
      expect(find.byType(OrdersScreen, skipOffstage: false), findsOneWidget);
    });
  });

  group('the basket', () {
    testWidgets('is not offered while it is empty', (tester) async {
      await pump(tester);
      expect(find.byKey(CustomerShell.cartKey), findsNothing);
    });

    testWidgets('shows how many are in it', (tester) async {
      await pump(tester, startingCart: cart);

      expect(find.byKey(CustomerShell.cartKey), findsOneWidget);
      // Pieces, not lines: two of one dish is two things in the basket.
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('opens the basket screen', (tester) async {
      await pump(tester, startingCart: cart);

      await tester.tap(find.byKey(CustomerShell.cartKey));
      await tester.pumpAndSettle();

      expect(find.byType(CartScreen), findsOneWidget);
    });

    // The bar belongs to the whole app, not to one tab: a basket assembled on the home
    // must still be reachable from طلباتي.
    testWidgets('stays reachable from every tab', (tester) async {
      await pump(tester, startingCart: cart);

      await tester.tap(find.byKey(CustomerShell.accountTabKey));
      await tester.pumpAndSettle();

      expect(find.byKey(CustomerShell.cartKey), findsOneWidget);
    });
  });

  group('basket to order', () {
    testWidgets('checkout is reached from the basket', (tester) async {
      await pump(tester, startingCart: cart);

      await tester.tap(find.byKey(CustomerShell.cartKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CartScreen.checkoutKey));
      await tester.pumpAndSettle();

      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    testWidgets('a placed order lands on its own tracking screen', (tester) async {
      await pump(tester, startingCart: cart);

      await tester.tap(find.byKey(CustomerShell.cartKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CartScreen.checkoutKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(find.byType(OrderScreen), findsOneWidget);
      // Going "back" from the order must not return to a checkout for an order that
      // has already been sent.
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.byType(CartScreen), findsNothing);
    });
  });

  group('getting to a merchant', () {
    const list = [
      HomeSection(key: 'list', type: 'merchantList', sortOrder: 0, cityId: 'edku'),
    ];

    testWidgets('tapping one on the home opens it', (tester) async {
      await pump(tester, sections: list);

      await tester.tap(find.text('مطعم الشاطئ'));
      await tester.pumpAndSettle();

      expect(find.byType(MerchantScreen), findsOneWidget);
    });

    // The bar on a merchant screen is the shortest path from "I picked something" to
    // "send it"; leaving it inert makes the customer hunt for the basket.
    testWidgets('the bar there opens the basket', (tester) async {
      await pump(tester, sections: list, startingCart: cart);

      await tester.tap(find.text('مطعم الشاطئ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantScreen.cartBarKey));
      await tester.pumpAndSettle();

      expect(find.byType(CartScreen), findsOneWidget);
    });
  });

  group('being asked to sign in', () {
    testWidgets('from طلباتي lands on the account tab', (tester) async {
      await pump(tester, signedInAs: null);

      await tester.tap(find.byKey(CustomerShell.ordersTabKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrdersScreen.signInKey));
      await tester.pumpAndSettle();

      expect(find.byKey(AccountScreen.signInKey), findsOneWidget);
    });
  });
}
