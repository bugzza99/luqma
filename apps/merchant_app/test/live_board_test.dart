import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/orders/live_board_screen.dart';

/// What is already being cooked or carried.
///
/// The inbox answers "yes or no". This screen answers "where is it now", and its only
/// job is to make the next step one tap.
void main() {
  const line = OrderLine(itemId: 'i1', name: 'فراخ مشوية', unitPrice: 12000, quantity: 1);

  Order order({
    String id = 'o1',
    int number = 101,
    OrderStatus status = OrderStatus.accepted,
    int? prepMinutes = 20,
    DeliveryBy deliveryBy = DeliveryBy.merchant,
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
        type: OrderType.instant,
        items: const [line],
        pricing: const OrderPricing(
          subtotal: 12000,
          deliveryFee: 1000,
          total: 13000,
        ),
        status: status,
        prepMinutes: prepMinutes,
        deliveryBy: deliveryBy,
      );

  late FakeMerchantOrderRepository orders;

  Future<void> pump(
    WidgetTester tester, {
    List<Order> seed = const [],
    Failure? failure,
  }) async {
    orders = FakeMerchantOrderRepository(seed: seed, failure: failure);

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
          merchantOrderRepositoryProvider.overrideWithValue(orders),
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
            child: LiveBoardScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('chosen extras qualify their dish, before the next dish', (tester) async {
    final incoming = order().copyWith(items: [
      OrderLine.fromJson({
        ...line.toJson(),
        'optionIds': ['large', 'cheese'],
        'optionsTotal': 750,
        'options': [
          {'id': 'large', 'name': 'حجم كبير', 'price': 500},
          {'id': 'cheese', 'name': 'جبنة زيادة', 'price': 250},
        ],
      }),
      const OrderLine(itemId: 'i2', name: 'سلطة', unitPrice: 1000, quantity: 1),
    ]);
    await pump(tester, seed: [incoming]);
    final extras = find.text('حجم كبير، جبنة زيادة');
    expect(extras, findsOneWidget);
    expect(tester.getTopLeft(extras).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('فراخ مشوية')).dy));
    expect(tester.getBottomLeft(extras).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('سلطة')).dy));
    expect(find.text(''), findsNothing);
  });

  testWidgets('no chosen extras draws no extra text or space', (tester) async {
    // Old rows have ids but no frozen names. They must still open without inventing
    // names from a menu that may have changed since the order was placed.
    for (final snapshot in [<String, dynamic>{}, <String, dynamic>{'options': []}]) {
      final incoming = order().copyWith(items: [
        OrderLine.fromJson({
          ...(line.toJson()..remove('options')),
          'optionIds': ['old'],
          ...snapshot,
        }),
      ]);
      await pump(tester, seed: [incoming]);
      expect(find.text(''), findsNothing);
      expect(find.text('حجم كبير، جبنة زيادة'), findsNothing);
      final dish = find.text('فراخ مشوية');
      final row = find.ancestor(of: dish, matching: find.byType(Row)).first;
      expect(tester.getSize(row).height, tester.getSize(dish).height);
    }
  });

  group('what is on the board', () {
    testWidgets('the checkout instruction stays visible while cooking', (tester) async {
      final cooking = Order.fromJson({
        ...order(status: OrderStatus.preparing).toJson(),
        'note': 'من غير شطة\nالدور التالت، الجرس مكسور',
      });
      await pump(tester, seed: [cooking]);
      expect(find.text('من غير شطة\nالدور التالت، الجرس مكسور'), findsOneWidget);
      expect(find.text('ملاحظة العميل'), findsOneWidget);
    });

    testWidgets('no checkout instruction draws no note section', (tester) async {
      await pump(tester, seed: [order()]);
      expect(find.text('ملاحظة العميل'), findsNothing);
    });

    testWidgets('orders that have been accepted and not yet finished',
        (tester) async {
      await pump(tester, seed: [
        order(id: 'a'),
        order(id: 'b', number: 102, status: OrderStatus.preparing),
        order(id: 'c', number: 103, status: OrderStatus.outForDelivery),
      ]);

      expect(find.byKey(LiveBoardScreen.cardKey('a')), findsOneWidget);
      expect(find.byKey(LiveBoardScreen.cardKey('b')), findsOneWidget);
      expect(find.byKey(LiveBoardScreen.cardKey('c')), findsOneWidget);
    });

    testWidgets('the promised time is shown back to the merchant', (tester) async {
      await pump(tester, seed: [order(prepMinutes: 45)]);

      // They said 45 minutes to a customer who is now waiting exactly that long.
      expect(find.textContaining('45'), findsWidgets);
    });

    testWidgets('nothing cooking says so', (tester) async {
      await pump(tester);
      expect(find.byKey(LiveBoardScreen.emptyKey), findsOneWidget);
    });

    testWidgets('a failed read never looks like nothing cooking', (tester) async {
      await pump(tester, failure: const OfflineFailure());

      expect(find.byKey(LiveBoardScreen.errorKey), findsOneWidget);
      expect(find.byKey(LiveBoardScreen.emptyKey), findsNothing);
    });
  });

  group('the next step', () {
    testWidgets('an accepted order can start cooking', (tester) async {
      await pump(tester, seed: [order()]);

      await tester.tap(find.byKey(LiveBoardScreen.advanceKey('o1')));
      await tester.pumpAndSettle();

      expect(orders['o1']!.status, OrderStatus.preparing);
    });

    testWidgets('a cooking order goes out for delivery', (tester) async {
      await pump(tester, seed: [order(status: OrderStatus.preparing)]);

      await tester.tap(find.byKey(LiveBoardScreen.advanceKey('o1')));
      await tester.pumpAndSettle();

      expect(orders['o1']!.status, OrderStatus.outForDelivery);
      expect(find.byKey(LiveBoardScreen.waitingKey('o1')), findsNothing);
    });

    // A platform order leaves when a Luqma courier takes it, which puts their name on it
    // in the same write. The shop's tap wrote the status alone, stranded the order where
    // no rider could take it, and the server refuses it now.
    testWidgets('a cooking platform order waits for the courier, with no button',
        (tester) async {
      await pump(tester, seed: [
        order(status: OrderStatus.preparing, deliveryBy: DeliveryBy.platform),
      ]);

      expect(find.byKey(LiveBoardScreen.advanceKey('o1')), findsNothing);
      expect(find.byKey(LiveBoardScreen.waitingKey('o1')), findsOneWidget);
      expect(find.text('مستني مندوب لقمة ياخده'), findsOneWidget);
    });

    testWidgets('an accepted platform order can still start cooking', (tester) async {
      await pump(tester, seed: [order(deliveryBy: DeliveryBy.platform)]);

      await tester.tap(find.byKey(LiveBoardScreen.advanceKey('o1')));
      await tester.pumpAndSettle();

      expect(orders['o1']!.status, OrderStatus.preparing);
    });

    // The courier marks delivery — they are the one at the door with the cash. A
    // button here would be the merchant guessing from the kitchen.
    testWidgets('an order on the road offers no further step', (tester) async {
      await pump(tester, seed: [order(status: OrderStatus.outForDelivery)]);

      expect(find.byKey(LiveBoardScreen.advanceKey('o1')), findsNothing);
    });

    testWidgets('the card moves as the order does', (tester) async {
      await pump(tester, seed: [order()]);

      await tester.tap(find.byKey(LiveBoardScreen.advanceKey('o1')));
      await tester.pumpAndSettle();

      expect(find.byKey(LiveBoardScreen.stageKey('o1', OrderStatus.preparing)),
          findsOneWidget);
    });
  });

  group('reaching the customer', () {
    // A courier at a wrong door and a customer who is not answering are the two
    // things that actually go wrong, and both are solved by a phone call.
    testWidgets('the phone number is on the card', (tester) async {
      await pump(tester, seed: [order()]);
      expect(find.textContaining('01000000000'), findsWidgets);
    });
  });

  group('M02 columns restyle', () {
    testWidgets('columns exist for accepted, preparing, and outForDelivery stages', (tester) async {
      await pump(tester, seed: [
        order(id: 'a', status: OrderStatus.accepted),
        order(id: 'b', number: 102, status: OrderStatus.preparing),
        order(id: 'c', number: 103, status: OrderStatus.outForDelivery),
      ]);

      expect(find.byKey(LiveBoardScreen.columnKey(OrderStatus.accepted)), findsOneWidget);
      expect(find.byKey(LiveBoardScreen.columnKey(OrderStatus.preparing)), findsOneWidget);
      expect(find.byKey(LiveBoardScreen.columnKey(OrderStatus.outForDelivery)), findsOneWidget);

      expect(
        find.descendant(
          of: find.byKey(LiveBoardScreen.columnKey(OrderStatus.accepted)),
          matching: find.text('مقبولة'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(LiveBoardScreen.columnKey(OrderStatus.preparing)),
          matching: find.text('قيد التحضير'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(LiveBoardScreen.columnKey(OrderStatus.outForDelivery)),
          matching: find.text('خرج للتوصيل'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('column headers display correct order counts', (tester) async {
      await pump(tester, seed: [
        order(id: 'a1', status: OrderStatus.accepted),
        order(id: 'a2', number: 102, status: OrderStatus.accepted),
        order(id: 'b1', number: 103, status: OrderStatus.preparing),
      ]);

      expect(
        find.descendant(
          of: find.byKey(LiveBoardScreen.columnCountKey(OrderStatus.accepted)),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(LiveBoardScreen.columnCountKey(OrderStatus.preparing)),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(LiveBoardScreen.columnCountKey(OrderStatus.outForDelivery)),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('advancing an order updates column counts and moves card', (tester) async {
      await pump(tester, seed: [order(id: 'o1', status: OrderStatus.accepted)]);

      expect(
        find.descendant(
          of: find.byKey(LiveBoardScreen.columnCountKey(OrderStatus.accepted)),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(LiveBoardScreen.columnCountKey(OrderStatus.preparing)),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(LiveBoardScreen.advanceKey('o1')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(LiveBoardScreen.columnCountKey(OrderStatus.accepted)),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(LiveBoardScreen.columnCountKey(OrderStatus.preparing)),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('columns render without overflow on a phone view', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pump(tester, seed: [
        order(id: 'a', status: OrderStatus.accepted),
        order(id: 'b', number: 102, status: OrderStatus.preparing),
        order(id: 'c', number: 103, status: OrderStatus.outForDelivery),
      ]);

      expect(tester.takeException(), isNull);
    });
  });
}
