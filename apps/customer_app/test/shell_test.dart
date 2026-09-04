import 'package:customer_app/src/account/account_screen.dart';
import 'package:customer_app/src/cart/cart.dart';
import 'package:customer_app/src/cart/cart_controller.dart';
import 'package:customer_app/src/cart/cart_screen.dart';
import 'package:customer_app/src/checkout/checkout_screen.dart';
import 'package:customer_app/src/home/home_screen.dart';
import 'package:customer_app/src/home/sections/home_kitchen_section.dart';
import 'package:customer_app/src/kitchen/meal_screen.dart';
import 'package:customer_app/src/kitchen/preorder_checkout_screen.dart';
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

  const kitchen = Merchant(
    id: 'k1',
    cityId: 'edku',
    type: MerchantType.homeKitchen,
    name: 'مطبخ أم أحمد',
    zoneId: 'z1',
    phone: '01000000000',
    status: MerchantStatus.approved,
  );

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

  /// A window the size of a phone.
  ///
  /// The test default is 800x600, which is not the shape of any device this app runs on
  /// — it is wider than it is tall. Once merchant cards carried a picture, the first
  /// card's name fell below 600 and every tap on it landed outside the render tree,
  /// which reads as "the card does not open" rather than "the window is the wrong shape".
  void phoneSized(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

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
    List<DailyMeal> meals = const [],
  }) async {
    phoneSized(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider
              .overrideWithValue(FakeAuthService(restoring: signedInAs)),
          merchantRepositoryProvider
              .overrideWithValue(
                // The kitchen too: `MealScreen` reads the merchant behind a meal, so a
                // reservation that cannot find it never reaches the checkout at all.
                FakeMerchantRepository(seed: const [shore, kitchen]),
              ),
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
          dailyMealRepositoryProvider
              .overrideWithValue(FakeDailyMealRepository(seed: meals)),
          clockProvider.overrideWithValue(() => DateTime(2026, 8, 23, 11)),
          orderRepositoryProvider.overrideWithValue(FakeOrderRepository()),
          // حسابي is built inside the IndexedStack whichever tab is showing, and it now
          // reads the customer's own marketing preference — so every test in this file
          // reaches the profile repository, on every tab.
          profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
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

    // Switching tabs shows the next one in place rather than pushing a route, which is
    // what keeps scroll position — and what left the Navigator holding a single entry.
    // System back then found nothing to pop and closed the app, which to a customer on
    // طلباتي is the app crashing when they meant to step back to the home.
    testWidgets('back from another tab returns to the home rather than exiting',
        (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(CustomerShell.accountTabKey));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(AccountScreen, skipOffstage: false), findsOneWidget,
          reason: 'the tab is still in the stack, just no longer showing');
    });

    // From the home there is genuinely nowhere further back, and letting the system
    // close the app is the right answer — trapping back there would make the app
    // impossible to leave.
    testWidgets('and back from the home is left to the system', (tester) async {
      await pump(tester);

      final popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(popped, isFalse);
      expect(find.byType(HomeScreen), findsOneWidget);
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

  // The one route to a checkout that did not come from `openCart`.
  //
  // Every other way in — the basket button on the shell, the bar on a merchant screen —
  // goes through `openCart`, which the shell hands its own `_goToAccount`. A meal is
  // opened from a *registry section*, which is built from a server-chosen string and has
  // no callbacks to hand it, so `openMeal` forwarded nothing. A signed-out customer
  // reached a checkout whose "سجّل دخول" button was disabled: the app's own suggestion,
  // greyed out, with nothing else on the screen to press.
  group('reserving a meal without an account', () {
    final mahshi = DailyMeal(
      id: 'd1',
      merchantId: 'k1',
      cityId: 'edku',
      name: 'محشي كرنب',
      price: 9000,
      date: '2026-08-23',
      totalQty: 20,
      remainingQty: 8,
      pickupWindowStart: 13 * 60,
      pickupWindowEnd: 16 * 60,
      deliveryOption: DeliveryOption.pickup,
      status: DailyMealStatus.published,
    );

    const kitchenSection = [
      HomeSection(
        key: 'kitchen',
        type: 'homeKitchenToday',
        sortOrder: 0,
        cityId: 'edku',
      ),
    ];

    testWidgets('lands on the account tab, not on a dead button', (tester) async {
      await pump(
        tester,
        signedInAs: null,
        sections: kitchenSection,
        meals: [mahshi],
      );

      await tester.tap(find.byKey(MealCard.cardKey('d1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(MealScreen.reserveKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(PreorderCheckoutScreen.signInKey));
      await tester.pumpAndSettle();

      // And the checkout is gone rather than sitting behind the account: coming "back"
      // to a checkout for a meal somebody has not signed in for is not a place to be.
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.byType(PreorderCheckoutScreen), findsNothing);
    });
  });

  group('a tapped notification', () {
    setUp(() => LuqmaPush.tappedOrder.value = null);
    tearDown(() => LuqmaPush.tappedOrder.value = null);

    // The launch case. The tap is recorded before any widget of this app exists, so a
    // shell that only listened for changes would never hear it — and until this existed,
    // nothing heard it at all: the customer tapped "الأوردر في الطريق" and the app came
    // forward on الرئيسية.
    testWidgets('from a cold start opens the order it was about', (tester) async {
      LuqmaPush.tappedOrder.value = 'o-cold';

      await pump(tester);

      expect(find.byType(OrderScreen), findsOneWidget);
    });

    testWidgets('while the app is open opens the order too', (tester) async {
      await pump(tester);

      LuqmaPush.tappedOrder.value = 'o-live';
      await tester.pumpAndSettle();

      expect(find.byType(OrderScreen), findsOneWidget);
    });

    // The tab moves as well as the route being pushed, so back from the order is طلباتي
    // — the list the order belongs to — rather than the home tab it was launched on.
    testWidgets('leaves طلباتي underneath it', (tester) async {
      LuqmaPush.tappedOrder.value = 'o-cold';
      await pump(tester);

      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();

      expect(find.byType(OrdersScreen), findsOneWidget);
    });
  });
}
