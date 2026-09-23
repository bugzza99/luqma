import 'dart:async';

import 'package:customer_app/src/orders/order_help_sheet.dart';
import 'package:customer_app/src/orders/order_screen.dart';
import 'package:customer_app/src/orders/orders_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Following an order, and what to do when it goes wrong.
void main() {
  const line = OrderLine(
    itemId: 'i1',
    name: 'فراخ مشوية',
    unitPrice: 12000,
    quantity: 1,
  );

  Order order({
    String id = 'o1',
    int number = 101,
    OrderStatus status = OrderStatus.placed,
    OrderType type = OrderType.instant,
    DateTime? deadline,
    int? prepMinutes,
    DateTime? placedAt,
  }) =>
      Order(
        id: id,
        cityId: 'edku',
        orderNumber: number,
        customerUid: 'u1',
        customerName: 'أحمد',
        customerPhone: '01000000000',
        merchantId: 'm1',
        merchantName: 'مطعم الشاطئ',
        zoneId: 'z1',
        type: type,
        items: const [line],
        pricing: const OrderPricing(
          subtotal: 12000,
          deliveryFee: 1000,
          total: 13000,
        ),
        status: status,
        acceptDeadlineAt: deadline,
        prepMinutes: prepMinutes,
        placedAt: placedAt ?? DateTime(2026, 8, 20, 19, 30),
      );

  /// A shop with a number on it. The order never carries one — it holds the
  /// *customer's* phone — so calling the kitchen means having the merchant.
  const shopWithPhone = Merchant(
    id: 'm1',
    cityId: 'edku',
    type: MerchantType.restaurant,
    name: 'مطعم الشاطئ',
    zoneId: 'z1',
    phone: '0123456789',
    status: MerchantStatus.approved,
  );

  late FakeOrderRepository orders;
  late FakeExternalLinks links;
  late FakeZaatarRepository zaatar;

  /// Brings a control at the bottom of a lazily built list into the viewport.
  ///
  /// The outermost scrollable is named explicitly: the screen has text fields of its
  /// own, and the default finder matches more than one.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    List<Order> seed = const [],
    LuqmaIdentity? signedInAs = const LuqmaIdentity(uid: 'u1', name: 'أحمد'),
    Failure? failure,
    List<Merchant> merchants = const [],
    bool dark = false,

    /// Orders that already carry a rating when the screen opens — what returning to an
    /// order rated last week looks like.
    List<String> ratedOrderIds = const [],
    FakeZaatarRepository? zaatarRepo,

    /// A repository of the test's own, for the cases that need the order to *change*
    /// while somebody is looking at it.
    FakeOrderRepository? orderRepo,
  }) async {
    // A real phone, not the 800x600 test window. This screen stacks a hero, a five-step
    // track, a bill and the order's own lines, so on a window wider than it is tall the
    // things at the bottom — the rating, the cancel — fall outside what the `ListView`
    // builds at all, and `findsNothing` reads as "the feature is gone".
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    orders = orderRepo ?? FakeOrderRepository(seed: seed, failure: failure);
    // Seeded before the tree is built: `watchHasRated` is read as the card first builds,
    // so a rating added afterwards is a rating the screen never sees.
    for (final id in ratedOrderIds) {
      orders.ratings.add({'orderId': id, 'stars': 5});
    }
    links = FakeExternalLinks();
    zaatar = zaatarRepo ?? FakeZaatarRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider
              .overrideWithValue(FakeAuthService(restoring: signedInAs)),
          orderRepositoryProvider.overrideWithValue(orders),
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: merchants)),
          externalLinksProvider.overrideWithValue(links),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
          zaatarRepositoryProvider.overrideWithValue(zaatar),
        ],
        child: MaterialApp(
          theme: dark ? LuqmaTheme.dark : LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: screen,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The orders tab on its own, sized to a phone, with a fixed clock so the relative
  /// dates on finished rows are deterministic and a `disableAnimations` switch for the
  /// motion tests. The redesign's tests drive their own pumps to catch the screen
  /// mid-animation, so [settle] is opt-out.
  Future<void> pumpOrders(
    WidgetTester tester, {
    required List<Order> seed,
    DateTime? now,
    bool reducedMotion = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    orders = FakeOrderRepository(seed: seed);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(
            FakeAuthService(
              restoring: const LuqmaIdentity(uid: 'u1', name: 'أحمد'),
            ),
          ),
          orderRepositoryProvider.overrideWithValue(orders),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
          clockProvider.overrideWithValue(() => now ?? DateTime(2026, 8, 27, 20)),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reducedMotion),
            child: const Directionality(
              textDirection: TextDirection.rtl,
              child: OrdersScreen(),
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  group('following one order', () {
    // The permission was asked for only on طلباتي. A customer goes from checkout straight
    // to this screen, may never open that tab, and so was never asked — and Android then
    // drops every status notification silently.
    testWidgets('asks for notifications where the order is being followed',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order()],
      );

      // `skipOffstage: false`: with notifications unavailable (as in a test) the banner is
      // zero-sized, and a zero-extent list child counts as offstage.
      expect(
        find.byType(LuqmaNotificationBanner, skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('the number is shown — it is what a phone call starts with',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order()],
      );

      expect(find.textContaining('101'), findsWidgets);
    });

    testWidgets('every step is listed, with the one it is on marked',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.preparing)],
      );

      // Seeing the steps that have not happened yet is how somebody knows what is left.
      expect(find.byKey(OrderScreen.stepKey(OrderStatus.placed)), findsOneWidget);
      expect(find.byKey(OrderScreen.stepKey(OrderStatus.delivered)), findsOneWidget);
      expect(find.byKey(OrderScreen.currentStepKey), findsOneWidget);
    });

    testWidgets('a cancelled order says so instead of showing a dead track',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.cancelled)],
      );

      expect(find.byKey(OrderScreen.cancelledKey), findsOneWidget);
      expect(find.byKey(OrderScreen.currentStepKey), findsNothing);
    });

    testWidgets('the total is shown as what the courier collects', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order()],
      );

      expect(find.text('130 ج'), findsWidgets);
    });

    testWidgets('an order that is gone says so rather than spinning forever',
        (tester) async {
      await pump(tester, const OrderScreen(orderId: 'missing'));

      expect(find.byKey(OrderScreen.errorKey), findsOneWidget);
    });
  });

  group('the hero says only what the order knows', () {
    // The artboard's largest line is «هيوصلك 8:45 م». Nothing can produce it: the
    // merchant quotes `prepMinutes` when they accept and the order stamps no
    // `acceptedAt`, so there is nothing to add those minutes to. The stage is what the
    // order actually knows, so the stage is what the biggest type says.
    testWidgets('the stage is the largest thing on it, not an arrival time',
        (tester) async {
      await pump(tester, const OrderScreen(orderId: 'o1'),
          seed: [order(status: OrderStatus.preparing)]);
      await tester.pumpAndSettle();

      expect(find.byKey(OrderScreen.heroKey), findsOneWidget);
      final stage = tester.widget<Text>(find.byKey(OrderScreen.stageKey));
      expect(stage.style, LuqmaType.display.copyWith(color: LuqmaPalette.white));
      final heroTexts = tester.widgetList<Text>(find.descendant(
        of: find.byKey(OrderScreen.heroKey), matching: find.byType(Text),
      ));
      expect(heroTexts.map((text) => text.data),
          ['مطعم الشاطئ', 'الطلب بيتجهز']);
      expect(
        find.descendant(
          of: find.byKey(OrderScreen.heroKey),
          matching: find.text('الطلب بيتجهز'),
        ),
        findsOneWidget,
      );
      // No invented clock time anywhere on the hero.
      expect(find.textContaining('هيوصلك'), findsNothing);
    });

    testWidgets('the quote is attributed to the kitchen, and only when it gave one',
        (tester) async {
      await pump(tester, const OrderScreen(orderId: 'o1'),
          seed: [order(status: OrderStatus.preparing, prepMinutes: 30)],
          merchants: [shopWithPhone]);
      await tester.pumpAndSettle();

      expect(find.byKey(OrderScreen.prepQuoteKey), findsOneWidget);
      expect(find.text('المطعم قال هيجهز خلال 30 دقيقة'), findsOneWidget);
    });

    // Found on a handset, not in this suite: an order that had been delivered still
    // carried «المطعم قال هيجهز خلال ١٥ دقيقة» under «الطلب اتسلّم». The quote is about
    // food becoming ready, and once it has been carried to a door that has happened —
    // so on a finished order it is a sentence about the future written under a past
    // tense, and the guard was on the quote existing rather than on it still meaning
    // anything.
    testWidgets('and stops quoting once the food is past being prepared', (tester) async {
      for (final status in [
        OrderStatus.outForDelivery,
        OrderStatus.delivered,
        OrderStatus.cancelled,
      ]) {
        await pump(tester, const OrderScreen(orderId: 'o1'),
            seed: [order(status: status, prepMinutes: 15)],
            merchants: [shopWithPhone]);
        await tester.pumpAndSettle();

        expect(find.byKey(OrderScreen.prepQuoteKey), findsNothing,
            reason: 'a $status order is not still being prepared');
      }
    });

    testWidgets('and says nothing about timing when it did not', (tester) async {
      await pump(tester, const OrderScreen(orderId: 'o1'),
          seed: [order(status: OrderStatus.preparing)]);
      await tester.pumpAndSettle();

      expect(find.byKey(OrderScreen.prepQuoteKey), findsNothing);
      expect(find.textContaining('خلال'), findsNothing);
    });
  });

  group('the track', () {
    // The order stamps `placedAt` and `deliveredAt` and nothing else. Acceptance,
    // cooking and setting off carry no hour, and a plausible-looking one beside
    // «المطعم قبل الطلب» is the sort of detail somebody repeats down the phone.
    testWidgets('shows an hour only where the order actually stamped one',
        (tester) async {
      final placed = DateTime(2026, 9, 8, 20, 12);
      await pump(tester, const OrderScreen(orderId: 'o1'),
          seed: [order(status: OrderStatus.preparing, placedAt: placed)]);
      await tester.pumpAndSettle();

      final step = find.byKey(OrderScreen.stepKey(OrderStatus.placed));
      expect(
        find.descendant(of: step, matching: find.text('8:12 م')),
        findsOneWidget,
      );

      // Accepted was passed but never stamped. It keeps its tick and is given no hour
      // at all — not a dash: three unstamped stages in a row drew a column of them down
      // the card, which reads as data that failed to load rather than as three moments
      // nobody recorded.
      final accepted = find.byKey(OrderScreen.stepKey(OrderStatus.accepted));
      expect(find.descendant(of: accepted,
          matching: find.byIcon(Icons.check_rounded)), findsOneWidget);
      expect(find.descendant(of: accepted, matching: find.text('—')), findsNothing);
      // One Text in that row, the label — no second one holding a placeholder.
      expect(
        find.descendant(of: accepted, matching: find.byType(Text)),
        findsOneWidget,
      );
    });

    testWidgets('marks the step it is on as now, and the ones ahead as unknown',
        (tester) async {
      await pump(tester, const OrderScreen(orderId: 'o1'),
          seed: [order(status: OrderStatus.preparing)]);
      await tester.pumpAndSettle();

      final current = find.byKey(OrderScreen.stepKey(OrderStatus.preparing));
      expect(
        find.descendant(of: current, matching: find.text('دلوقتي')),
        findsOneWidget,
      );

      // A stage still ahead says nothing about time. The empty ring on its left is
      // already the whole statement.
      final ahead = find.byKey(OrderScreen.stepKey(OrderStatus.outForDelivery));
      expect(find.descendant(of: ahead, matching: find.text('—')), findsNothing);
      expect(
        find.descendant(of: ahead, matching: find.byType(Text)),
        findsOneWidget,
      );
    });
  });

  group('calling the shop', () {
    testWidgets('is not offered when no number is known', (tester) async {
      await pump(tester, const OrderScreen(orderId: 'o1'),
          seed: [order(status: OrderStatus.preparing)]);
      await tester.pumpAndSettle();

      // The order carries the *customer's* phone, never the shop's. With no merchant
      // loaded there is nothing to dial, and a button that cannot dial is worse than no
      // button on the screen somebody opens because their food is late.
      expect(find.byKey(OrderScreen.callMerchantKey), findsNothing);
      // The way to complain is still there, which is the point of it being separate.
      expect(find.byKey(OrderScreen.issueKey), findsOneWidget);
    });

    testWidgets('dials the shop, not the customer', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.preparing)],
        merchants: [shopWithPhone],
      );
      await tester.pumpAndSettle();

      final call = find.byKey(OrderScreen.callMerchantKey);
      await reveal(tester, call);
      await tester.tap(call);
      await tester.pumpAndSettle();

      expect(links.opened.single, Uri(scheme: 'tel', path: '0123456789'));
    });

    testWidgets('a refused dial shows the shop number', (tester) async {
      await pump(tester, const OrderScreen(orderId: 'o1'),
          seed: [order()], merchants: [shopWithPhone]);
      links.answer = false;
      await reveal(tester, find.byKey(OrderScreen.callMerchantKey));
      await tester.tap(find.byKey(OrderScreen.callMerchantKey));
      await tester.pumpAndSettle();
      expect(find.text('مش قادرين نفتح الاتصال. الرقم: 0123456789'),
          findsOneWidget);
    });

    testWidgets('a blank shop phone offers no call', (tester) async {
      await pump(tester, const OrderScreen(orderId: 'o1'),
          seed: [order()], merchants: [shopWithPhone.copyWith(phone: '   ')]);
      await reveal(tester, find.byKey(OrderScreen.issueKey));
      expect(find.byKey(OrderScreen.callMerchantKey), findsNothing);
    });
  });

  testWidgets('the bill keeps both frozen discounts and the recorded total',
      (tester) async {
    await pump(tester, const OrderScreen(orderId: 'o1'), seed: [
      order().copyWith(couponCode: 'SAVED', pricing: const OrderPricing(
        subtotal: 21000, subtotalDiscount: 3000, deliveryFee: 1000,
        deliveryDiscount: 500, total: 17700,
      )),
    ]);
    await reveal(tester, find.byKey(OrderScreen.billKey));
    // Deliberately unlike the item sum or the arithmetic of these rows: only the
    // stored total is authoritative, even when a fixture is inconsistent.
    expect(tester.widgetList<Text>(find.descendant(
      of: find.byKey(OrderScreen.billKey), matching: find.byType(Text),
    )).map((text) => text.data), [
      'الأصناف', '210 ج', 'خصم SAVED', '− 30 ج', 'خصم التوصيل',
      '− 5 ج', 'التوصيل', '10 ج', 'المطلوب كاش', '177 ج',
    ]);
  });

  for (final dark in [false, true]) {
    testWidgets('hero and passed marks have contrast, dark=$dark', (tester) async {
      await pump(tester, const OrderScreen(orderId: 'o1'), dark: dark,
          seed: [order(status: OrderStatus.preparing, prepMinutes: 30)],
          merchants: [shopWithPhone]);
      final hero = tester.widget<Container>(find.byKey(OrderScreen.heroKey));
      final grounds = ((hero.decoration as BoxDecoration).gradient!
          as LinearGradient).colors;
      expect(grounds, [LuqmaPalette.bannerTop, LuqmaPalette.bannerBottom]);
      double contrast(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
      }
      for (final text in tester.widgetList<Text>(find.descendant(
        of: find.byKey(OrderScreen.heroKey), matching: find.byType(Text),
      ))) {
        for (final ground in grounds) {
          expect(contrast(text.style!.color!, ground), greaterThanOrEqualTo(4.5));
        }
      }
      final tick = tester.widget<Icon>(find.descendant(
        of: find.byKey(OrderScreen.stepKey(OrderStatus.accepted)),
        matching: find.byIcon(Icons.check_rounded),
      ));
      expect(contrast(tick.color!,
          dark ? LuqmaColors.dark.success : LuqmaColors.light.success),
          greaterThanOrEqualTo(3));
      final colors = dark ? LuqmaColors.dark : LuqmaColors.light;
      final label = tester.widget<Text>(find.descendant(
        of: find.byKey(OrderScreen.stepKey(OrderStatus.preparing)),
        matching: find.text('بيتجهّز'),
      ));
      expect(contrast(label.style!.color!, colors.card),
          greaterThanOrEqualTo(4.5));
      await reveal(tester, find.byKey(OrderScreen.callMerchantKey));
      final call = tester.widget<OutlinedButton>(
          find.byKey(OrderScreen.callMerchantKey));
      expect(contrast(call.style!.foregroundColor!.resolve({})!, colors.background),
          greaterThanOrEqualTo(4.5));
    });
  }

  testWidgets('only delivery has the delivery timestamp; passed steps keep ticks',
      (tester) async {
    await pump(tester, const OrderScreen(orderId: 'o1'), seed: [
      order(status: OrderStatus.delivered)
          .copyWith(deliveredAt: DateTime(2026, 9, 8, 21, 17)),
    ]);
    for (final status in [OrderStatus.accepted, OrderStatus.preparing,
        OrderStatus.outForDelivery]) {
      final step = find.byKey(OrderScreen.stepKey(status));
      // Ticked, and silent about the hour: these three are not stamped anywhere on the
      // order, and a placeholder in each drew a column of dashes beside a delivered
      // order that read as a failure to load.
      expect(find.descendant(of: step, matching: find.text('—')), findsNothing);
      expect(find.descendant(of: step, matching: find.byType(Text)), findsOneWidget);
      expect(find.descendant(of: step, matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget);
    }
    expect(find.descendant(
      of: find.byKey(OrderScreen.stepKey(OrderStatus.delivered)),
      matching: find.text('9:17 م'),
    ), findsOneWidget);
  });

  // The state changes the words on the hero, never its ground. A pale card for a
  // delivered order was tried and taken back out: the colour is the product's, and a
  // receipt in the brand reads better than a receipt in grey.
  testWidgets('a delivered order keeps the brand ground and says the hour it arrived',
      (tester) async {
    await pump(tester, const OrderScreen(orderId: 'o1'), seed: [
      order(status: OrderStatus.delivered)
          .copyWith(deliveredAt: DateTime(2026, 9, 8, 21, 17)),
    ]);
    await tester.pumpAndSettle();

    final hero = tester.widget<Container>(find.byKey(OrderScreen.heroKey));
    expect((hero.decoration! as BoxDecoration).gradient, isNotNull);

    // The headline is the stamped hour, not the stage's words — the one number on this
    // screen that the order can actually prove.
    expect(
      tester.widget<Text>(find.byKey(OrderScreen.stageKey)).data,
      'اتسلّم 9:17 م',
    );
  });

  // «اتسلّم» is the end of the track, and an order resting there is finished with it
  // rather than at it. It was drawn with the in-progress mark, which left the one stage
  // that genuinely completed as the only one without a tick.
  testWidgets('the last step of a delivered order is ticked, not in progress',
      (tester) async {
    await pump(tester, const OrderScreen(orderId: 'o1'), seed: [
      order(status: OrderStatus.delivered)
          .copyWith(deliveredAt: DateTime(2026, 9, 8, 21, 17)),
    ]);
    await tester.pumpAndSettle();

    final last = find.byKey(OrderScreen.stepKey(OrderStatus.delivered));
    expect(find.descendant(of: last, matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget);
    // Every one of the five is complete, so every one carries a tick.
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(5));
  });

  testWidgets('a live order keeps the burgundy hero', (tester) async {
    await pump(tester, const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.preparing)]);
    await tester.pumpAndSettle();

    final hero = tester.widget<Container>(find.byKey(OrderScreen.heroKey));
    expect((hero.decoration! as BoxDecoration).gradient, isNotNull);
    expect(tester.widget<Text>(find.byKey(OrderScreen.stageKey)).data,
        'الطلب بيتجهز');
  });

  group('cancelling', () {
    testWidgets('is offered while nobody has answered yet', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order()],
      );

      expect(find.byKey(OrderScreen.cancelKey), findsOneWidget);
    });

    // The owner's decision, 2026-09-23: an order the shop never answered is escalated,
    // and fifteen minutes later the customer may let it go. Before then the admin may
    // still rescue it, and the screen says when the button will come.
    testWidgets('is offered fifteen minutes after nobody answered', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [
          order(
            status: OrderStatus.needsAttention,
            deadline: DateTime.now().subtract(const Duration(minutes: 20)),
          ),
        ],
      );

      await reveal(tester, find.byKey(OrderScreen.cancelKey));
      await tester.tap(find.byKey(OrderScreen.cancelKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderScreen.confirmCancelKey));
      await tester.pumpAndSettle();

      expect((await orders.watchOrder('o1').first).status, OrderStatus.cancelled);
    });

    testWidgets('before then it says when, and offers nothing yet', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [
          order(
            status: OrderStatus.needsAttention,
            deadline: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ],
      );

      expect(find.byKey(OrderScreen.cancelKey), findsNothing);
      await reveal(tester, find.byKey(OrderScreen.cancelLaterKey));
      expect(find.textContaining('تقدر تلغيه'), findsOneWidget);
    });

    // Once a kitchen has started, cancelling costs somebody food they already cooked.
    testWidgets('is not offered once the merchant has accepted', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.accepted)],
      );

      expect(find.byKey(OrderScreen.cancelKey), findsNothing);
    });

    testWidgets('asks before it happens', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order()],
      );

      await reveal(tester, find.byKey(OrderScreen.cancelKey));
      await tester.tap(find.byKey(OrderScreen.cancelKey));
      await tester.pumpAndSettle();

      expect(find.byKey(OrderScreen.confirmCancelKey), findsOneWidget);
    });

    testWidgets('confirming cancels it', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order()],
      );

      await reveal(tester, find.byKey(OrderScreen.cancelKey));
      await tester.tap(find.byKey(OrderScreen.cancelKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderScreen.confirmCancelKey));
      await tester.pumpAndSettle();

      final updated = await orders.watchOrder('o1').first;
      expect(updated.status, OrderStatus.cancelled);
    });

    // It awaited the cancel and threw the answer away. Offline, nothing was said: the
    // customer left believing the order was cancelled, and the kitchen cooked it.
    testWidgets('a cancel that does not reach the server says so', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order()],
      );
      orders.failure = const OfflineFailure();

      await reveal(tester, find.byKey(OrderScreen.cancelKey));
      await tester.tap(find.byKey(OrderScreen.cancelKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderScreen.confirmCancelKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('الإلغاء موصلش'), findsOneWidget);
      // And the order is still on screen, still cancellable, rather than an error.
      expect(find.byKey(OrderScreen.cancelKey), findsOneWidget);
    });

    // The shop accepted while the dialog was open. The order is no longer the customer's
    // to cancel, and a silent refresh to «المطعم قبل الطلب» explained nothing.
    testWidgets('a cancel the shop overtook says why', (tester) async {
      final repo = _AcceptsBeforeCancel(seed: [order()]);
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order()],
        orderRepo: repo,
      );

      await reveal(tester, find.byKey(OrderScreen.cancelKey));
      await tester.tap(find.byKey(OrderScreen.cancelKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderScreen.confirmCancelKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('المطعم قبل الطلب خلاص'), findsOneWidget);
    });
  });

  group('reporting a problem', () {
    testWidgets('is offered on any order', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.outForDelivery)],
      );

      expect(find.byKey(OrderScreen.issueKey), findsOneWidget);
    });

    testWidgets('files the complaint against the order', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderHelpSheet.topicKey(HelpTopic.other)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(OrderScreen.issueTextKey),
        'الأكل وصل بارد',
      );
      await tester.tap(find.byKey(OrderScreen.sendIssueKey));
      await tester.pumpAndSettle();

      // The topic leads, so the admin's queue reads at a glance.
      expect(orders.issues.single['reason'], 'حاجة تانية: الأكل وصل بارد');
      expect(orders.issues.single['orderId'], 'o1');
      expect(find.text('وصلتنا شكواك، هنراجعها ونرد عليك.'), findsOneWidget);
    });

    testWidgets('a missing item after delivery becomes a ticket under that topic',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderHelpSheet.topicKey(HelpTopic.wrongItems)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderHelpSheet.actionKey(HelpAction.complain)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(OrderScreen.issueTextKey), 'ناقص عيش');
      await tester.tap(find.byKey(OrderScreen.sendIssueKey));
      await tester.pumpAndSettle();

      expect(orders.issues.single['reason'], 'ناقص صنف أو غلط في الطلب: ناقص عيش');
    });

    // "What do I owe" is answered by the bill on the order, not by a person.
    testWidgets('the assistant reads the bill back without filing anything',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.outForDelivery)],
      );

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderHelpSheet.topicKey(HelpTopic.money)));
      await tester.pumpAndSettle();

      expect(find.textContaining('المطلوب كاش للمندوب: 130 ج'), findsOneWidget);
      await tester.tap(find.byKey(OrderHelpSheet.actionKey(HelpAction.done)));
      await tester.pumpAndSettle();
      expect(orders.issues, isEmpty);
    });

    testWidgets('a late order the shop has not answered can be cancelled from the assistant',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.placed)],
      );

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderHelpSheet.topicKey(HelpTopic.late)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderHelpSheet.actionKey(HelpAction.cancelOrder)));
      await tester.pumpAndSettle();

      // The same question the cancel button asks — the assistant does not skip it.
      expect(find.byKey(OrderScreen.confirmCancelKey), findsOneWidget);
    });

    testWidgets('a complaint that fails to send says so', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );
      orders.failure = const OfflineFailure();

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderHelpSheet.topicKey(HelpTopic.other)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(OrderScreen.issueTextKey), 'الأكل بارد');
      await tester.tap(find.byKey(OrderScreen.sendIssueKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('الشكوى موصلتش'), findsOneWidget);
    });

    // An empty complaint tells an admin nothing and wastes the reply.
    testWidgets('refuses to send an empty complaint', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderHelpSheet.topicKey(HelpTopic.other)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderScreen.sendIssueKey));
      await tester.pumpAndSettle();

      expect(orders.issues, isEmpty);
      expect(find.text('اكتب اللي حصل الأول'), findsOneWidget);
    });

    testWidgets('a typed question is answered from the topic the server chose',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.placed)],
      );

      zaatar.enqueue(
        const ZaatarVerdict(topic: HelpTopic.late, fromModel: true),
      );

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();

      expect(find.text('زعتر'), findsOneWidget);
      expect(find.textContaining('أهلاً، أنا زعتر من لقمة'), findsOneWidget);

      await tester.enterText(find.byKey(OrderHelpSheet.inputKey), 'الأكل فين؟');
      await tester.tap(find.byKey(OrderHelpSheet.sendKey));
      await tester.pumpAndSettle();

      // The words are OrderHelper's, not the server's: the server sent a topic and the
      // sentence was drawn here from the order.
      expect(find.byKey(OrderHelpSheet.replyKey), findsOneWidget);
      expect(find.textContaining('اتأخر في الرد على طلبك'), findsOneWidget);
      expect(
        find.byKey(OrderHelpSheet.actionKey(HelpAction.complain)),
        findsOneWidget,
      );
      // And nothing says the rules answered, because they did not.
      expect(find.text('زعتر بيرد من الردود الجاهزة دلوقتي'), findsNothing);
      expect(zaatar.calls.single.message, 'الأكل فين؟');
    });

    testWidgets('the server topic and the offline topic draw the same sentence',
        (tester) async {
      // One answer specification. The Edge Function used to carry its own copy of these
      // templates in TypeScript; it returns a topic now, and this is what says so.
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.placed)],
      );
      zaatar.enqueue(const ZaatarVerdict(topic: HelpTopic.late, fromModel: true));

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(OrderHelpSheet.inputKey), 'سؤال');
      await tester.tap(find.byKey(OrderHelpSheet.sendKey));
      await tester.pumpAndSettle();

      final fromServer =
          tester.widget<Text>(find.descendant(
        of: find.byKey(OrderHelpSheet.replyKey),
        matching: find.byType(Text),
      )).data;

      // Now the same order and the same topic, reached the other way.
      zaatar.fallback = true;
      await tester.enterText(
        find.byKey(OrderHelpSheet.inputKey),
        'الطلب اتأخر',
      );
      await tester.tap(find.byKey(OrderHelpSheet.sendKey));
      await tester.pumpAndSettle();

      final fromRules =
          tester.widget<Text>(find.descendant(
        of: find.byKey(OrderHelpSheet.replyKey),
        matching: find.byType(Text),
      )).data;

      expect(fromRules, isNotNull);
      expect(fromRules, fromServer);
    });

    testWidgets('fallback path answers from OrderHelper with the grey line',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.placed)],
      );
      zaatar.fallback = true;

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();

      // Keyword 'اتأخر' routes to HelpTopic.late
      await tester.enterText(
        find.byKey(OrderHelpSheet.inputKey),
        'الطلب اتأخر جداً ومش عارف أعمل إيه',
      );
      await tester.tap(find.byKey(OrderHelpSheet.sendKey));
      await tester.pumpAndSettle();

      expect(find.text('زعتر بيرد من الردود الجاهزة دلوقتي'), findsOneWidget);
      expect(find.textContaining('اتأخر في الرد على طلبك'), findsOneWidget);
      expect(find.byKey(OrderHelpSheet.replyKey), findsOneWidget);
    });

    testWidgets('suggested cancel still asks for confirmation',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.placed)],
      );
      zaatar.enqueue(
        const ZaatarVerdict(topic: HelpTopic.cancel, fromModel: true),
      );

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(OrderHelpSheet.inputKey), 'عاوز ألغي');
      await tester.tap(find.byKey(OrderHelpSheet.sendKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(OrderHelpSheet.actionKey(HelpAction.cancelOrder)));
      await tester.pumpAndSettle();

      expect(find.byKey(OrderScreen.confirmCancelKey), findsOneWidget);
    });

    testWidgets('complaint from a typed message files a ticket with that text',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );
      zaatar.enqueue(
        const ZaatarVerdict(topic: HelpTopic.wrongItems, fromModel: true),
      );

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();

      const complaintMsg = 'الأكل وصل بارد ومفيش معالق';
      await tester.enterText(find.byKey(OrderHelpSheet.inputKey), complaintMsg);
      await tester.tap(find.byKey(OrderHelpSheet.sendKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(OrderHelpSheet.actionKey(HelpAction.complain)));
      await tester.pumpAndSettle();

      expect(find.byKey(OrderScreen.issueTextKey), findsOneWidget);
      final field = tester.widget<TextField>(find.byKey(OrderScreen.issueTextKey));
      expect(field.controller?.text, complaintMsg);

      await tester.tap(find.byKey(OrderScreen.sendIssueKey));
      await tester.pumpAndSettle();

      expect(orders.issues.single['reason'], contains(complaintMsg));
      expect(orders.issues.single['orderId'], 'o1');
    });

    testWidgets('send is disabled while pending', (tester) async {
      final completer = Completer<Result<ZaatarVerdict>>();
      final pendingZaatar = _PendingZaatar(completer);

      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.placed)],
        zaatarRepo: pendingZaatar,
      );

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(OrderHelpSheet.inputKey), 'سؤال');
      await tester.tap(find.byKey(OrderHelpSheet.sendKey));
      await tester.pump();

      final sendButton = tester.widget<IconButton>(find.byKey(OrderHelpSheet.sendKey));
      expect(sendButton.onPressed, isNull);

      completer.complete(const Result.ok(
        ZaatarVerdict(topic: HelpTopic.late, fromModel: true),
      ));
      await tester.pumpAndSettle();

      final sendButtonAfter = tester.widget<IconButton>(find.byKey(OrderHelpSheet.sendKey));
      expect(sendButtonAfter.onPressed, isNotNull);
    });

    // The sheet used to answer from the order it was handed when it opened. A shop that
    // accepts while زعتر is thinking left the customer reading «لسه مردش» under a cancel
    // button the database would refuse — and the server's reply cannot correct it,
    // because all it carries is a topic.
    testWidgets('answers the order as it is now, not as it was when the sheet opened',
        (tester) async {
      final completer = Completer<Result<ZaatarVerdict>>();
      final live = _LiveOrders(order(status: OrderStatus.placed));
      addTearDown(live.close);

      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        orderRepo: live,
        zaatarRepo: _PendingZaatar(completer),
      );

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(OrderHelpSheet.inputKey), 'عاوز ألغي');
      await tester.tap(find.byKey(OrderHelpSheet.sendKey));
      await tester.pump();

      // The shop answers while the question is in flight.
      live.emit(order(status: OrderStatus.accepted));
      await tester.pump();

      completer.complete(const Result.ok(
        ZaatarVerdict(topic: HelpTopic.cancel, fromModel: true),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('بدأ يجهّز الأكل'), findsOneWidget);
      expect(find.textContaining('لسه مردش'), findsNothing);
      expect(
        find.byKey(OrderHelpSheet.actionKey(HelpAction.cancelOrder)),
        findsNothing,
        reason: 'the database would refuse it, so the button must not be offered',
      );
    });

    testWidgets('withdraws a cancel button the moment the shop accepts',
        (tester) async {
      final live = _LiveOrders(order(status: OrderStatus.placed));
      addTearDown(live.close);

      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        orderRepo: live,
      );

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(OrderHelpSheet.topicKey(HelpTopic.cancel)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(OrderHelpSheet.actionKey(HelpAction.cancelOrder)),
        findsOneWidget,
      );

      live.emit(order(status: OrderStatus.accepted));
      await tester.pumpAndSettle();

      expect(
        find.byKey(OrderHelpSheet.actionKey(HelpAction.cancelOrder)),
        findsNothing,
      );
    });

    // Both copies of the reader are one specification now — `ZaatarClassifier` in
    // luqma_core, ported into the Edge Function and pinned to it by
    // `data/zaatar_corpus.json`. These two sentences are what the phone used to get
    // wrong on its own: «السعر» was «حاجة تانية» here and money on the server, and
    // «لسه عاوز ألغي» was «اتأخر» here and cancel there.
    testWidgets('the offline reader is the shared one', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.placed)],
      );
      zaatar.fallback = true;

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(OrderHelpSheet.inputKey), 'السعر');
      await tester.tap(find.byKey(OrderHelpSheet.sendKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('حساب طلبك'), findsOneWidget);

      await tester.enterText(find.byKey(OrderHelpSheet.inputKey), 'لسه عاوز ألغي');
      await tester.tap(find.byKey(OrderHelpSheet.sendKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('تقدر تلغي دلوقتي'), findsOneWidget);
    });

    testWidgets('sends messages to zaatar with order id',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.placed)],
      );

      await reveal(tester, find.byKey(OrderScreen.issueKey));
      await tester.tap(find.byKey(OrderScreen.issueKey));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(OrderHelpSheet.inputKey), 'سؤال 1');
      await tester.tap(find.byKey(OrderHelpSheet.sendKey));
      await tester.pumpAndSettle();

      expect(zaatar.calls.first.orderId, 'o1');
      expect(zaatar.calls.first.message, 'سؤال 1');

      await tester.enterText(find.byKey(OrderHelpSheet.inputKey), 'سؤال 2');
      await tester.tap(find.byKey(OrderHelpSheet.sendKey));
      await tester.pumpAndSettle();

      expect(zaatar.calls.length, 2);
      expect(zaatar.calls.last.orderId, 'o1');
      expect(zaatar.calls.last.message, 'سؤال 2');
    });
  });

  group('rating', () {
    // It awaited the write and set `_sent` whatever came back, so a rating lost to a dead
    // connection was thanked for — and the form came back empty next time.
    testWidgets('a rating that fails to send keeps the form and says so',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );
      orders.failure = const OfflineFailure();

      await reveal(tester, find.byKey(OrderScreen.starKey(4)));
      await tester.tap(find.byKey(OrderScreen.starKey(4)));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(OrderScreen.sendRatingKey));
      await tester.tap(find.byKey(OrderScreen.sendRatingKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('وصلنا تقييمك'), findsNothing);
      expect(find.textContaining('التقييم موصلش'), findsOneWidget);
      expect(find.byKey(OrderScreen.sendRatingKey), findsOneWidget);
    });

    testWidgets('is asked for only once the order arrived', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.outForDelivery)],
      );

      expect(find.byKey(OrderScreen.rateKey), findsNothing);
    });

    testWidgets('appears on a delivered order', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );

      expect(find.byKey(OrderScreen.rateKey), findsOneWidget);
    });

    // The card's memory used to be a `bool` inside the widget, so leaving the screen and
    // coming back asked again for a rating already given — and `rate` upserts, so
    // answering the second time replaced the first verdict from a form that starts
    // empty. Five stars could become three for no reason but being asked twice.
    testWidgets('does not come back for an order that was already rated',
        (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
        ratedOrderIds: const ['o1'],
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(OrderScreen.rateKey));

      // No form at all: the question has been answered, and asking it again is how a
      // five-star verdict gets replaced by whatever an empty form is set to.
      expect(find.byKey(OrderScreen.starKey(5)), findsNothing);
      expect(find.byKey(OrderScreen.sendRatingKey), findsNothing);
    });

    testWidgets('the stars are filed against the order', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );

      await reveal(tester, find.byKey(OrderScreen.starKey(4)));
      await tester.tap(find.byKey(OrderScreen.starKey(4)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderScreen.sendRatingKey));
      await tester.pumpAndSettle();

      expect(orders.ratings.single['stars'], 4);
    });


    // One number for a whole order cannot say the grill was good and the rice was cold —
    // and that second half is what another customer scrolling the menu needs.
    testWidgets('each dish star is a full-size target', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );
      final star = find.byKey(OrderScreen.itemStarKey('i1', 3));
      await reveal(tester, star);

      final size = tester.getSize(star);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('a dish can be rated on its own', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );

      await reveal(tester, find.byKey(OrderScreen.starKey(4)));
      await tester.tap(find.byKey(OrderScreen.starKey(4)));
      await tester.pumpAndSettle();

      await reveal(tester, find.byKey(OrderScreen.itemStarKey('i1', 5)));
      await tester.tap(find.byKey(OrderScreen.itemStarKey('i1', 5)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderScreen.sendRatingKey));
      await tester.pumpAndSettle();

      expect(orders.ratings.single['items'], {'i1': 5});
    });

    // Silence, not a zero: a dish nobody commented on must not have its average dragged
    // down for not being mentioned.
    testWidgets('a dish left alone is not rated at all', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );

      await reveal(tester, find.byKey(OrderScreen.starKey(4)));
      await tester.tap(find.byKey(OrderScreen.starKey(4)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderScreen.sendRatingKey));
      await tester.pumpAndSettle();

      expect(orders.ratings.single['items'], isEmpty);
    });

    // Somebody who pressed a star by accident needs a way back to having said nothing.
    testWidgets('pressing the same star again clears it', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );

      await reveal(tester, find.byKey(OrderScreen.starKey(4)));
      await tester.tap(find.byKey(OrderScreen.starKey(4)));
      await tester.pumpAndSettle();

      await reveal(tester, find.byKey(OrderScreen.itemStarKey('i1', 3)));
      await tester.tap(find.byKey(OrderScreen.itemStarKey('i1', 3)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderScreen.itemStarKey('i1', 3)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(OrderScreen.sendRatingKey));
      await tester.pumpAndSettle();

      expect(orders.ratings.single['items'], isEmpty);
    });

    // A rating with no stars is not a rating.
    testWidgets('cannot be sent without stars', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order(status: OrderStatus.delivered)],
      );

      expect(
        tester
            .widget<FilledButton>(find.byKey(OrderScreen.sendRatingKey))
            .onPressed,
        isNull,
      );
    });
  });

  group('the orders tab', () {
    testWidgets('shows what is running now above what is finished',
        (tester) async {
      await pump(
        tester,
        const OrdersScreen(),
        seed: [
          order(id: 'done', number: 90, status: OrderStatus.delivered),
          order(id: 'live', number: 91, status: OrderStatus.preparing),
        ],
      );

      final live = tester.getTopLeft(find.byKey(OrdersScreen.rowKey('live'))).dy;
      final done = tester.getTopLeft(find.byKey(OrdersScreen.rowKey('done'))).dy;
      // The one being cooked right now is the one being looked for.
      expect(live, lessThan(done));
    });

    testWidgets('a customer with no orders is told, not shown an error',
        (tester) async {
      await pump(tester, const OrdersScreen());

      expect(find.byKey(OrdersScreen.emptyKey), findsOneWidget);
    });

    testWidgets('signed out, it asks for an account', (tester) async {
      await pump(tester, const OrdersScreen(), signedInAs: null);

      expect(find.byKey(OrdersScreen.signInKey), findsOneWidget);
    });

    testWidgets('a failed read says so rather than looking like no orders',
        (tester) async {
      await pump(
        tester,
        const OrdersScreen(),
        failure: const OfflineFailure(),
      );

      expect(find.byKey(OrdersScreen.errorKey), findsOneWidget);
      expect(find.byKey(OrdersScreen.emptyKey), findsNothing);
    });
  });

  group('the redesign — دلوقتي is a hero, اللي فات is a row', () {
    testWidgets('a running order is the burgundy hero; a finished one is a plain row',
        (tester) async {
      await pumpOrders(tester, seed: [
        order(id: 'done', number: 90, status: OrderStatus.delivered),
        order(id: 'live', number: 91, status: OrderStatus.preparing),
      ]);

      expect(find.byKey(OrdersScreen.heroKey('live')), findsOneWidget);
      // The finished order is drawn, but never as a second hero.
      expect(find.byKey(OrdersScreen.rowKey('done')), findsOneWidget);
      expect(find.byKey(OrdersScreen.heroKey('done')), findsNothing);

      final hero =
          tester.widget<Container>(find.byKey(OrdersScreen.heroKey('live')));
      expect((hero.decoration as BoxDecoration).color, LuqmaColors.light.brand);
    });

    testWidgets('the hero puts how long it takes and the total on one line',
        (tester) async {
      await pumpOrders(tester, seed: [
        order(id: 'live', status: OrderStatus.preparing)
            .copyWith(placedAt: DateTime(2026, 8, 27, 20, 15), prepMinutes: 30),
      ]);

      // A duration, not a clock time. This asserted «هيوصلك 8:45 م» — placement plus the
      // quoted minutes — and that arithmetic adds two numbers from different moments:
      // the minutes are quoted when the merchant accepts, and they cover cooking, not
      // delivery. Every clock time it produced was early. See `_HeroCard._etaText`.
      final time = find.textContaining('جاهز خلال 30 دقيقة');
      final total = find.text('130 ج');
      expect(time, findsOneWidget);
      expect(total, findsOneWidget);

      // "On one line" is the claim in the name, and finding both strings anywhere is not
      // that claim: stacked in a column they would both still be found. They have to
      // share a row, and sit on the same baseline within it.
      expect(
        find.ancestor(of: time, matching: find.byType(Row)),
        findsWidgets,
      );
      final shared = tester
          .widgetList<Row>(find.ancestor(of: time, matching: find.byType(Row)))
          .where((row) =>
              tester
                  .widgetList<Row>(
                      find.ancestor(of: total, matching: find.byType(Row)))
                  .contains(row))
          .toList();
      expect(shared, isNotEmpty, reason: 'the time and the total share a Row');
      expect(
        tester.getCenter(time).dy,
        closeTo(tester.getCenter(total).dy, 8),
        reason: 'and sit on one line, not merely inside one widget',
      );
    });
  });

  group('the redesign — the hero progress bar', () {
    double widthFactor(WidgetTester tester, String id) => tester
        .widget<FractionallySizedBox>(find.byKey(OrdersScreen.progressKey(id)))
        .widthFactor!;

    testWidgets('advances toward its target rather than snapping to it',
        (tester) async {
      await pumpOrders(
        tester,
        seed: [order(id: 'live', status: OrderStatus.preparing)],
        settle: false,
      );
      // Let the stream resolve and the card mount, then step partway into the fill.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      final mid = widthFactor(tester, 'live');
      expect(mid, greaterThan(0.0));
      expect(mid, lessThan(0.55));

      await tester.pumpAndSettle();
      expect(widthFactor(tester, 'live'), moreOrLessEquals(0.55, epsilon: 0.001));
    });

    testWidgets('is set straight to the target under reduced motion',
        (tester) async {
      await pumpOrders(
        tester,
        seed: [order(id: 'live', status: OrderStatus.preparing)],
        reducedMotion: true,
        settle: false,
      );
      await tester.pump();
      await tester.pump();

      // No pumping past two frames: with the setting on, the bar is simply full to 0.55.
      expect(widthFactor(tester, 'live'), moreOrLessEquals(0.55, epsilon: 0.001));
    });
  });

  group('the redesign — a status is never colour alone', () {
    testWidgets('a cancelled order still reads اتلغى', (tester) async {
      await pumpOrders(tester, seed: [
        order(id: 'x', status: OrderStatus.cancelled),
      ]);

      // Mirrors _Row._labels[cancelled]; pinned here so a colour-only pip fails.
      expect(find.text('اتلغى'), findsOneWidget);
    });

    testWidgets('a delivered order reads اتسلّم beside a pip of its own colour',
        (tester) async {
      await pumpOrders(tester, seed: [
        order(id: 'y', status: OrderStatus.delivered),
      ]);

      expect(find.text('اتسلّم'), findsOneWidget);

      final pip = find.descendant(
        of: find.byKey(OrdersScreen.rowKey('y')),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(pip, findsOneWidget);
      expect(
        (tester.widget<Container>(pip).decoration as BoxDecoration).color,
        LuqmaColors.light.success,
      );
    });

    testWidgets('the finished row shows its number and a relative date',
        (tester) async {
      await pumpOrders(
        tester,
        now: DateTime(2026, 8, 27, 20),
        seed: [
          order(id: 'z', number: 1039, status: OrderStatus.delivered)
              .copyWith(placedAt: DateTime(2026, 8, 26, 21, 20)),
        ],
      );

      expect(find.textContaining('طلب #1039'), findsOneWidget);
      expect(find.textContaining('امبارح'), findsOneWidget);
      expect(find.textContaining('9:20 م'), findsOneWidget);
    });
  });

  group('the redesign — repeat order', () {
    testWidgets('a card under the finished list offers the last shop again',
        (tester) async {
      await pumpOrders(tester, seed: [
        order(id: 'p1', number: 5, status: OrderStatus.delivered),
      ]);

      expect(find.byKey(OrdersScreen.repeatKey), findsOneWidget);
      expect(find.textContaining('اطلب تاني من مطعم الشاطئ'), findsOneWidget);
      expect(find.byKey(OrdersScreen.repeatActionKey), findsOneWidget);

      // And it does something. The button being present proved nothing: a null `onPressed`
      // or a throwing handler would have left this test green while the control was dead,
      // which is the exact shape of the dead-button bugs this codebase keeps finding.
      await tester.tap(find.byKey(OrdersScreen.repeatActionKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(OrdersScreen.repeatKey), findsNothing,
          reason: 'pressing it left the orders screen for the shop');
    });

    testWidgets('there is no repeat card while nothing has finished',
        (tester) async {
      await pumpOrders(tester, seed: [
        order(id: 'live', status: OrderStatus.preparing),
      ]);

      expect(find.byKey(OrdersScreen.repeatKey), findsNothing);
    });
  });

  group('the redesign — rows arrive', () {
    double fade(WidgetTester tester, int i) => tester
        .widget<FadeTransition>(
          find
              .descendant(
                of: find.byType(LuqmaEntrance).at(i),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    testWidgets('finished rows stagger in',
        (tester) async {
      final seed = [
        order(id: 'a', number: 3, status: OrderStatus.delivered),
        order(id: 'b', number: 2, status: OrderStatus.delivered),
        order(id: 'c', number: 1, status: OrderStatus.delivered),
      ];

      await pumpOrders(tester, seed: seed, settle: false);
      await tester.pump();
      await tester.pump();
      await tester.pump(Motion.stagger);

      // The first row is further into its entrance than the second — the whole
      // difference between a stagger and one shared fade.
      expect(fade(tester, 0), greaterThan(fade(tester, 1)));

      await tester.pumpAndSettle();
      expect(fade(tester, 0), 1.0);
      expect(fade(tester, 1), 1.0);
    });

    testWidgets('under reduced motion the rows are just there', (tester) async {
      await pumpOrders(
        tester,
        reducedMotion: true,
        settle: false,
        seed: [
          order(id: 'a', number: 2, status: OrderStatus.delivered),
          order(id: 'b', number: 1, status: OrderStatus.delivered),
        ],
      );
      await tester.pump();
      await tester.pump();

      expect(fade(tester, 0), 1.0);
      expect(fade(tester, 1), 1.0);
    });
  });
}

class _PendingZaatar extends FakeZaatarRepository {
  _PendingZaatar(this._completer);
  final Completer<Result<ZaatarVerdict>> _completer;

  @override
  Future<Result<ZaatarVerdict>> ask({
    required String orderId,
    required String message,
  }) =>
      _completer.future;
}

/// An order that changes while somebody is looking at it.
///
/// [FakeOrderRepository.watchOrder] is a `Stream.value` — one reading, for ever — which
/// is fine for a screen that opens and closes and hides every bug about an order moving
/// underneath one. The real repository is a live subscription; this is that.
class _LiveOrders extends FakeOrderRepository {
  _LiveOrders(Order initial)
      : _current = initial,
        super(seed: [initial]);

  Order _current;
  final _changes = StreamController<Order>.broadcast();

  void emit(Order order) {
    _current = order;
    _changes.add(order);
  }

  Future<void> close() => _changes.close();

  @override
  Stream<Order> watchOrder(String orderId) async* {
    yield _current;
    yield* _changes.stream;
  }
}

/// Accepts the order at the moment the customer confirms their cancel — the race the
/// cancel dialog cannot see.
class _AcceptsBeforeCancel extends FakeOrderRepository {
  _AcceptsBeforeCancel({super.seed});

  @override
  Future<Result<void>> cancel(String orderId, {required String reason}) async =>
      const Result.err(ConflictFailure());
}
