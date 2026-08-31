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
}
