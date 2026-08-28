import 'package:customer_app/src/cart/cart.dart';
import 'package:customer_app/src/cart/cart_controller.dart';
import 'package:customer_app/src/cart/cart_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The last screen before money is committed. Everything the customer is agreeing to
/// has to be visible and changeable here.
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
    minOrder: 5000,
    openingHours: alwaysOpen,
  );

  const chicken = CartLine(
    id: 'l1',
    itemId: 'i1',
    merchantId: 'm1',
    name: 'فراخ مشوية',
    unitPrice: 12000,
    quantity: 1,
  );
  const bread = CartLine(
    id: 'l2',
    itemId: 'i2',
    merchantId: 'm1',
    name: 'عيش',
    unitPrice: 500,
    quantity: 2,
  );

  const full = Cart(merchantId: 'm1', lines: [chicken, bread]);

  late ProviderContainer container;
  late bool checkedOut;

  Future<void> pump(
    WidgetTester tester, {
    Cart cart = full,
    Merchant merchant = shore,
  }) async {
    checkedOut = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: [merchant])),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
          if (cart.isNotEmpty)
            cartProvider.overrideWith(() => CartController.seeded(cart)),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return Directionality(
                textDirection: TextDirection.rtl,
                child: CartScreen(onCheckout: () => checkedOut = true),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('what is in the basket', () {
    testWidgets('every line is shown with its total, not its unit price',
        (tester) async {
      await pump(tester);

      expect(find.text('فراخ مشوية'), findsOneWidget);
      // Two loaves at 5 each. Showing 5 next to a line of two would be a wrong number
      // sitting right above a correct sum.
      expect(find.text('10 ج'), findsOneWidget);
    });

    testWidgets('the food subtotal is the sum of the lines', (tester) async {
      await pump(tester);
      expect(find.byKey(CartScreen.subtotalKey), findsOneWidget);
      expect(find.text('130 ج'), findsWidgets);
    });

    testWidgets('an empty basket says so and offers no way to pay',
        (tester) async {
      await pump(tester, cart: Cart.empty);

      expect(find.byKey(CartScreen.emptyKey), findsOneWidget);
      expect(find.byKey(CartScreen.checkoutKey), findsNothing);
    });
  });

  group('changing the basket', () {
    testWidgets('more of something raises its quantity and the subtotal',
        (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(CartScreen.moreKey('l1')));
      await tester.pumpAndSettle();

      expect(container.read(cartProvider).lines.first.quantity, 2);
      expect(find.text('250 ج'), findsWidgets);
    });

    testWidgets('fewer removes the line when it reaches zero', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(CartScreen.lessKey('l1')));
      await tester.pumpAndSettle();

      expect(container.read(cartProvider).lines.length, 1);
      expect(find.text('فراخ مشوية'), findsNothing);
    });

    // Emptying the basket by hand lands on the same state as arriving with nothing.
    testWidgets('removing the last line leaves the empty state', (tester) async {
      await pump(tester, cart: const Cart(merchantId: 'm1', lines: [chicken]));

      await tester.tap(find.byKey(CartScreen.lessKey('l1')));
      await tester.pumpAndSettle();

      expect(find.byKey(CartScreen.emptyKey), findsOneWidget);
    });
  });

  group('the merchant floor', () {
    testWidgets('a basket under the minimum cannot go to checkout',
        (tester) async {
      await pump(
        tester,
        cart: const Cart(merchantId: 'm1', lines: [bread]),
      );

      final button = tester.widget<FilledButton>(
        find.byKey(CartScreen.checkoutKey),
      );
      expect(button.onPressed, isNull);
    });

    // Saying "under the minimum" without saying by how much makes the customer do
    // arithmetic to find out what would fix it.
    testWidgets('it says how much more is needed', (tester) async {
      await pump(
        tester,
        cart: const Cart(merchantId: 'm1', lines: [bread]),
      );

      expect(find.byKey(CartScreen.shortfallKey), findsOneWidget);
      expect(find.textContaining('40 ج'), findsOneWidget);
    });

    testWidgets('a basket over the minimum can go to checkout', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(CartScreen.checkoutKey));
      await tester.pumpAndSettle();

      expect(checkedOut, isTrue);
    });
  });

  group('a merchant that shut while the basket sat there', () {
    const closed = Merchant(
      id: 'm1',
      cityId: 'edku',
      type: MerchantType.restaurant,
      name: 'مطعم الشاطئ',
      zoneId: 'z1',
      phone: '01000000000',
      status: MerchantStatus.approved,
      minOrder: 5000,
      // No window: shut right now.
    );

    // The basket survives — it is still what they wanted — but sending it would produce
    // an order nobody is in the kitchen to cook.
    testWidgets('says so and refuses checkout', (tester) async {
      await pump(tester, merchant: closed);

      expect(find.byKey(CartScreen.closedKey), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(CartScreen.checkoutKey),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('the lines are still all there', (tester) async {
      await pump(tester, merchant: closed);
      expect(find.text('فراخ مشوية'), findsOneWidget);
    });
  });
}
