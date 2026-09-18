import 'dart:async';

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
    Merchant? merchant = shore,
    bool reduced = false,
    Size size = const Size(390, 844),
    double textScale = 1,
    Completer<Merchant>? merchantInFlight,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    checkedOut = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: [?merchant])),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
          if (cart.isNotEmpty)
            cartProvider.overrideWith(() => CartController.seeded(cart)),
          // Holds `merchantProvider` in `AsyncLoading` for as long as the test wants.
          // Last, so it replaces the repository-backed answer above.
          if (merchantInFlight != null)
            merchantProvider('m1')
                .overrideWith((ref) => Stream.fromFuture(merchantInFlight.future)),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced, textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
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
      final card = find.byKey(CartScreen.lineKey('l2'));
      expect(find.descendant(of: card, matching: find.text('10 ج')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('5 ج')), findsNothing);
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

      final less = tester.widget<IconButton>(find.byKey(CartScreen.lessKey('l1')));
      expect(less.tooltip, 'شيل الصنف');
      expect((less.icon as Icon).icon, Icons.delete_outline_rounded);
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

  group('the finished basket', () {
    for (final cart in [Cart.empty, full,
      const Cart(merchantId: 'm1', lines: [bread]),
      Cart(merchantId: 'm1', lines: [chicken.copyWith(quantity: 99)])]) {
      testWidgets('only known money for ${cart.subtotal} piastres', (tester) async {
        await pump(tester, cart: cart, merchant: shore.copyWith(deliveryFeeOverride: 3700));
        expect(find.text('الإجمالي'), findsNothing);
        expect(find.textContaining('المعمورة'), findsNothing);
        expect(find.text('37 ج'), findsNothing);
        if (cart.isNotEmpty) {
          final summary = find.byKey(CartScreen.summaryKey);
          final texts = tester.widgetList<Text>(find.descendant(of: summary,
              matching: find.byType(Text))).map((t) => t.data).toList();
          final strings = LuqmaStrings.of(tester.element(summary));
          expect(texts, ['الأصناف', strings.price(cart.subtotal),
            'التوصيل بيتحسب بعد ما تختار العنوان']);
          expect(find.descendant(of: summary, matching: find.byType(Divider)), findsOneWidget);
        }
      });
    }

    testWidgets('snapshot monograms, extras, cash and address copy', (tester) async {
      const extra = MenuOption(id: 't', name: 'طحينة زيادة', price: 500);
      final cart = Cart.empty.add(const MenuItem(id: 'i', merchantId: 'm1',
        categoryId: 'c', name: 'فراخ', price: 12000), options: [extra], note: 'من غير شطة');
      await pump(tester, cart: cart);
      final image = tester.widget<LuqmaImage>(find.byKey(CartScreen.imageKey(cart.lines.single.id)));
      expect(image.url, isNull);
      expect(image.name, 'فراخ');
      expect(tester.getSize(find.byType(LuqmaImage)), const Size(56, 56));
      expect(find.text('+ طحينة زيادة'), findsOneWidget);
      expect(find.text('من غير شطة'), findsOneWidget);
      expect(find.text('من مطعم الشاطئ'), findsOneWidget);
      expect(find.text('الدفع كاش عند الاستلام'), findsOneWidget);
      expect(find.text('اختار العنوان'), findsOneWidget);
    });

    testWidgets('two taps before a frame both count and controls remain 48', (tester) async {
      await pump(tester);
      final more = find.byKey(CartScreen.moreKey('l2'));
      final less = find.byKey(CartScreen.lessKey('l2'));
      for (final target in [more, less]) {
        expect(tester.getSize(target).width, greaterThanOrEqualTo(Sizes.minTarget));
        expect(tester.getSize(target).height, greaterThanOrEqualTo(Sizes.minTarget));
      }
      expect(tester.widget<IconButton>(less).tooltip, 'واحد أقل');
      await tester.tap(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(container.read(cartProvider).lines.last.quantity, 4);
    });

    for (final reduced in [false, true]) {
      testWidgets('removal closes the gap, reduced=$reduced', (tester) async {
        await pump(tester, reduced: reduced);
        final survivor = find.byKey(CartScreen.lineKey('l2'));
        final before = tester.getTopLeft(survivor).dy;
        await tester.tap(find.byKey(CartScreen.lessKey('l1')));
        await tester.pump();
        expect(container.read(cartProvider).lines.length, 1);
        final departing = find.byKey(CartScreen.lineKey('l1'));
        if (reduced) {
          expect(departing, findsNothing);
          final after = tester.getTopLeft(survivor).dy;
          expect(after, lessThan(before));
          await tester.pump(const Duration(milliseconds: 80));
          expect(tester.getTopLeft(survivor).dy, after);
        } else {
          expect(departing, findsOneWidget);
          await tester.pump(const Duration(milliseconds: 80));
          final middle = tester.getTopLeft(survivor).dy;
          expect(middle, lessThan(before));
          expect(tester.widget<SizeTransition>(find.byKey(CartScreen.exitKey('l1')))
              .sizeFactor.value, inExclusiveRange(0, 1));
          await tester.pumpAndSettle();
          expect(departing, findsNothing);
          expect(tester.getTopLeft(survivor).dy, lessThan(middle));
        }
      });
    }

    testWidgets('subtotal pulses with exactly one current number per frame', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(CartScreen.moreKey('l1')));
      await tester.pump();
      final summary = find.byKey(CartScreen.subtotalKey);
      double scale() => tester.widget<Transform>(find.byKey(CartScreen.subtotalMotionKey))
          .transform.storage.first;
      final firstScale = scale();
      expect(firstScale, lessThan(1));
      for (var frame = 0; frame < 12; frame++) {
        expect(find.descendant(of: summary, matching: find.text('130 ج')), findsNothing);
        expect(find.descendant(of: summary, matching: find.text('250 ج')), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scale(), 1);
    });

    testWidgets('reduced motion has no subtotal pulse or entrance', (tester) async {
      await pump(tester, reduced: true);
      await tester.tap(find.byKey(CartScreen.moreKey('l1')));
      await tester.pump();
      expect(find.byKey(CartScreen.subtotalMotionKey), findsNothing);
      expect(find.byType(LuqmaEntrance), findsNothing);
      expect(find.text('250 ج'), findsOneWidget);
    });

    testWidgets('a missing merchant explains the blocked button above it', (tester) async {
      await pump(tester, merchant: null);
      expect(find.text('المطعم مش متاح دلوقتي — سلتك محفوظة.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(CartScreen.checkoutKey)).onPressed, isNull);
      expect(tester.getBottomLeft(find.byKey(CartScreen.missingKey)).dy,
          lessThan(tester.getTopLeft(find.byKey(CartScreen.checkoutKey)).dy));
    });

    // `merchantProvider` is a FutureProvider, so its first state is `AsyncLoading`, where
    // `.value` is null — indistinguishable from a shop that is genuinely gone unless the
    // screen reads the `AsyncValue` itself. It did not, so the ordinary path into this
    // screen — the shell's basket badge, where nothing else holds the provider alive —
    // drew «المطعم مش متاح» in the alarming tone for the length of a round trip, about a
    // shop that was simply still loading.
    //
    // Nothing in the suite could see it: `FakeMerchantRepository` resolves in the same
    // microtask and every other test ends in `pumpAndSettle`, so the loading frame never
    // existed. This one holds the provider in flight and never settles.
    testWidgets('a merchant still loading is not accused of being gone',
        (tester) async {
      final never = Completer<Merchant>();
      addTearDown(() => never.complete(shore));

      await pump(tester, merchantInFlight: never);
      await tester.pump();

      expect(find.byKey(CartScreen.missingKey), findsNothing,
          reason: 'loading is not the same answer as gone');
      // Still refused, because nothing is known yet — it is only the sentence that was
      // wrong, never the disabled button.
      expect(tester.widget<FilledButton>(find.byKey(CartScreen.checkoutKey)).onPressed,
          isNull);
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
