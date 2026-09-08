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

  // The clock every test runs against unless it passes its own. 13:00, so a window
  // written around it is easy to reason about; the weekday is read off this rather than
  // hard-coded, so a fixture cannot be shut one day in seven.
  final noon = DateTime(2026, 9, 8, 13);

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
    Failure? menuFailure,
    Map<String, Object> config = const {},
    DateTime? now,
    bool reducedMotion = false,
  }) async {
    // A real phone, not the 800x600 test window: this screen stacks a 168 cover, an info
    // block and a chip row above the menu, and on the default window the first dish falls
    // off the bottom and taps land outside it.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: [merchant])),
          menuRepositoryProvider.overrideWithValue(
            FakeMenuRepository(
              categories: merchant.menuCategories,
              items: items,
              failure: menuFailure,
            ),
          ),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher(config))),
          clockProvider.overrideWithValue(() => now ?? noon),
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
              return MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(disableAnimations: reducedMotion),
                child: const Directionality(
                  textDirection: TextDirection.rtl,
                  child: MerchantScreen(merchantId: 'm1'),
                ),
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

    // The price is what a customer would try to act on, and the dish cannot be bought
    // today. It would fail if the row rendered `strings.price(item.price)` without
    // gating on `isAvailable`.
    testWidgets('a sold-out row shows «خلص النهارده» and no price', (tester) async {
      await pump(tester);

      expect(find.text('خلص النهارده'), findsOneWidget);
      expect(find.text('90 ج'), findsNothing);
    });

    testWidgets('an unavailable item cannot be added', (tester) async {
      await pump(tester);

      await tester.tap(find.text('سمك بلطي'));
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantScreen.itemSheetKey), findsNothing);
    });
  });

  group('the cover', () {
    // Launch day has no photographs, so the largest empty space on the screen has to be
    // a deliberate tint rather than a broken frame. It would fail if the cover were a
    // plain coloured box instead of a `LuqmaImage`.
    testWidgets('is a LuqmaImage that falls back to the name', (tester) async {
      await pump(tester);

      final cover = tester.widget<LuqmaImage>(
        find.byKey(MerchantScreen.coverKey),
      );
      expect(cover.url, isNull);
      expect(cover.name, 'مطعم الشاطئ');
    });

    testWidgets('draws an approved cover when there is one', (tester) async {
      await pump(
        tester,
        merchant: shore.copyWith(coverUrl: 'https://example.test/cover.jpg'),
      );

      final cover = tester.widget<LuqmaImage>(
        find.byKey(MerchantScreen.coverKey),
      );
      expect(cover.url, 'https://example.test/cover.jpg');
    });
  });

  group('the أكل بيتي badge', () {
    // Home kitchens are the product's differentiator, so a badge that names one is worth
    // more than the artboard's «موثّق», which the business does not verify. It would fail
    // if the badge were shown for every merchant, or for none.
    testWidgets('shows for a home kitchen', (tester) async {
      await pump(tester, merchant: shore.copyWith(type: MerchantType.homeKitchen));

      expect(find.byKey(MerchantScreen.badgeKey), findsOneWidget);
      expect(find.text('أكل بيتي'), findsOneWidget);
    });

    testWidgets('is absent for a restaurant', (tester) async {
      await pump(tester);

      expect(find.byKey(MerchantScreen.badgeKey), findsNothing);
    });
  });

  group('the rating', () {
    // A single five-star review is not information. It would fail if the rating were
    // shown whenever `ratingCount > 0` rather than gated on `minRatingsToShow`.
    testWidgets('is shown once enough people have rated', (tester) async {
      await pump(
        tester,
        merchant: shore.copyWith(ratingAvg: 4.6, ratingCount: 38),
        config: {'min_ratings_to_show': 10},
      );

      expect(find.byKey(MerchantScreen.ratingKey), findsOneWidget);
      expect(find.text('4.6'), findsOneWidget);
      expect(find.textContaining('38'), findsOneWidget);
    });

    // Below the threshold the home's merchant row says «جديد» rather than leaving a gap
    // where a number belongs. It would fail if the screen drew nothing, or drew the
    // average anyway.
    testWidgets('is «جديد» below the threshold, not an empty gap', (tester) async {
      await pump(
        tester,
        merchant: shore.copyWith(ratingAvg: 5.0, ratingCount: 2),
        config: {'min_ratings_to_show': 10},
      );

      expect(find.byKey(MerchantScreen.ratingKey), findsNothing);
      expect(find.byKey(MerchantScreen.noRatingKey), findsOneWidget);
      expect(find.text('جديد'), findsOneWidget);
      expect(find.text('5.0'), findsNothing);
    });
  });

  group('when it is open, closed, or paused', () {
    // The close time is derived from the window, not a stored string. It would fail if
    // the status line were a hard-coded label or read a non-existent field.
    testWidgets('open says when it closes', (tester) async {
      await pump(
        tester,
        merchant: shore.copyWith(
          // Opens this morning, closes at 1 ص tonight.
          openingHours: [
            OpeningWindow(
              weekday: noon.weekday,
              openMinute: 600,
              closeMinute: 60,
            ),
          ],
        ),
      );

      expect(find.byKey(MerchantScreen.statusKey), findsOneWidget);
      expect(find.text('مفتوح لحد 1 ص'), findsOneWidget);
      expect(find.byKey(MerchantScreen.closedBannerKey), findsNothing);
    });

    // It would fail if `pausedUntil` were folded into "closed" — a busy shop and a shut
    // one read the same then, and only one of them is coming back in an hour.
    testWidgets('paused reads as busy, not closed', (tester) async {
      await pump(
        tester,
        merchant: shore.copyWith(
          pausedUntil: noon.add(const Duration(hours: 1)),
        ),
      );

      expect(find.text('مشغول دلوقتي'), findsOneWidget);
      expect(find.textContaining('مشغول'), findsWidgets);
      // The menu is still there to browse.
      expect(find.text('فراخ مشوية'), findsOneWidget);
    });

    testWidgets('nothing can be added while it is paused', (tester) async {
      await pump(
        tester,
        merchant: shore.copyWith(pausedUntil: noon.add(const Duration(hours: 1))),
      );

      await tester.tap(find.text('فراخ مشوية'));
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantScreen.itemSheetKey), findsNothing);
    });
  });

  group('the category chips', () {
    const fish = MenuItem(
      id: 'i3',
      merchantId: 'm1',
      categoryId: 'c2',
      name: 'جمبري مقلي',
      price: 18000,
    );
    const twoSections = Merchant(
      id: 'm1',
      cityId: 'edku',
      type: MerchantType.restaurant,
      name: 'مطعم الشاطئ',
      zoneId: 'z1',
      phone: '01000000000',
      status: MerchantStatus.approved,
      openingHours: alwaysOpen,
      menuCategories: [
        MenuCategory(id: 'c1', name: 'مشويات'),
        MenuCategory(id: 'c2', name: 'أسماك'),
      ],
    );

    // It would fail if the chip did not filter — tapping «أسماك» would leave the
    // grilled dish on screen.
    testWidgets('tapping one narrows the menu to that section', (tester) async {
      await pump(
        tester,
        merchant: twoSections,
        items: const [chicken, fish],
      );

      expect(find.text('فراخ مشوية'), findsOneWidget);
      expect(find.text('جمبري مقلي'), findsOneWidget);

      await tester.tap(find.byKey(MerchantScreen.categoryChipKey('c2')));
      await tester.pumpAndSettle();

      expect(find.text('جمبري مقلي'), findsOneWidget);
      expect(find.text('فراخ مشوية'), findsNothing);

      await tester.tap(find.byKey(MerchantScreen.categoryAllChipKey));
      await tester.pumpAndSettle();

      expect(find.text('فراخ مشوية'), findsOneWidget);
    });

    // A menu with one section has nothing to choose between.
    testWidgets('are absent when there is only one section', (tester) async {
      await pump(tester);

      expect(find.byKey(MerchantScreen.categoryChipsKey), findsNothing);
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

    // The bar is how somebody reaches checkout, so it should grow in rather than blink.
    // Adding straight through the controller keeps the bottom-sheet dismissal out of the
    // measurement. It would fail if the dock swapped `bottomNavigationBar` from nothing
    // to the bar with no transition between them.
    testWidgets('the bar arrives as a transition, not a jump', (tester) async {
      await pump(tester);
      final closed =
          tester.getSize(find.byKey(MerchantScreen.cartDockKey)).height;

      container.read(cartProvider.notifier).add(chicken);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final midway =
          tester.getSize(find.byKey(MerchantScreen.cartDockKey)).height;

      await tester.pumpAndSettle();
      final open =
          tester.getSize(find.byKey(MerchantScreen.cartDockKey)).height;

      expect(closed, 0);
      expect(midway, greaterThan(0));
      expect(midway, lessThan(open),
          reason: 'the dock is still growing the bar in, not already full height');
    });

    // With reduced motion the dock reaches full height in one frame rather than
    // animating. It would fail if its duration were `Motion.sheet` directly instead of
    // through `Motion.of`.
    testWidgets('under reduced motion the bar simply appears', (tester) async {
      await pump(tester, reducedMotion: true);

      container.read(cartProvider.notifier).add(chicken);
      await tester.pump();
      final afterOneFrame =
          tester.getSize(find.byKey(MerchantScreen.cartDockKey)).height;

      await tester.pumpAndSettle();
      final settled =
          tester.getSize(find.byKey(MerchantScreen.cartDockKey)).height;

      expect(find.byKey(MerchantScreen.cartBarKey), findsOneWidget);
      expect(afterOneFrame, settled,
          reason: 'no growth animation for someone who asked the OS for less of it');
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
      expect(find.text('مقفول دلوقتي'), findsWidgets);
      // Browsing a closed kitchen is how somebody decides to come back later.
      expect(find.text('فراخ مشوية'), findsOneWidget);
    });

    testWidgets('nothing can be added while it is shut', (tester) async {
      await pump(tester, merchant: closed);

      await tester.tap(find.text('فراخ مشوية'));
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantScreen.itemSheetKey), findsNothing);
    });

    // Deliberately a shop with real hours rather than the `closed` fixture above, which
    // has no window at all and so can never open however the clock moves. One merchant,
    // one schedule, two readings of the clock — otherwise the test proves only that a
    // different merchant is open, which is what the first version of it did.
    testWidgets('and is open again when the clock says so', (tester) async {
      const evenings = Merchant(
        id: 'm1',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'مطعم الشاطئ',
        zoneId: 'z1',
        phone: '0100',
        status: MerchantStatus.approved,
        openingHours: [
          OpeningWindow(weekday: DateTime.tuesday, openMinute: 1080, closeMinute: 1380),
        ],
      );
      // A Tuesday, because the window is: 15:00 is before it opens, 19:00 is inside it.
      final tuesday = DateTime(2026, 9, 8, 15);

      await pump(tester, merchant: evenings, now: tuesday);
      expect(find.byKey(MerchantScreen.closedBannerKey), findsOneWidget);

      await pump(
        tester,
        merchant: evenings,
        now: tuesday.add(const Duration(hours: 4)),
      );
      expect(find.byKey(MerchantScreen.closedBannerKey), findsNothing);
    });
  });

  // The merchant stream has a careful error arm and says why in a comment beside it.
  // The two menu streams did not: they were collapsed with `.value ?? const []`, so a
  // dropped connection drew the shop with nothing in it — a kitchen that appears to
  // cook nothing, with no error text and no way to try again. An empty menu and an
  // unreachable one look identical to the customer and are not the same thing.
  testWidgets('a menu that fails to load says so instead of showing an empty shop',
      (tester) async {
    await pump(tester, menuFailure: const OfflineFailure());

    expect(find.byType(LuqmaErrorView), findsOneWidget,
        reason: 'the customer is told, and given the retry every other error carries');
    expect(find.text('نص فرخة على الفحم'), findsNothing);
  });
}
