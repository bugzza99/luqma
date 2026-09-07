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
        placedAt: DateTime(2026, 8, 20, 19, 30),
      );

  late FakeOrderRepository orders;

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
  }) async {
    orders = FakeOrderRepository(seed: seed, failure: failure);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider
              .overrideWithValue(FakeAuthService(restoring: signedInAs)),
          orderRepositoryProvider.overrideWithValue(orders),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
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

  group('cancelling', () {
    testWidgets('is offered while nobody has answered yet', (tester) async {
      await pump(
        tester,
        const OrderScreen(orderId: 'o1'),
        seed: [order()],
      );

      expect(find.byKey(OrderScreen.cancelKey), findsOneWidget);
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
      await tester.enterText(
        find.byKey(OrderScreen.issueTextKey),
        'الأكل وصل بارد',
      );
      await tester.tap(find.byKey(OrderScreen.sendIssueKey));
      await tester.pumpAndSettle();

      expect(orders.issues.single['reason'], 'الأكل وصل بارد');
      expect(orders.issues.single['orderId'], 'o1');
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
      await tester.tap(find.byKey(OrderScreen.sendIssueKey));
      await tester.pumpAndSettle();

      expect(orders.issues, isEmpty);
    });
  });

  group('rating', () {
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
