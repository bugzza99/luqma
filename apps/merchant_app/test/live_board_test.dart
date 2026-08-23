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

  group('what is on the board', () {
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
}
