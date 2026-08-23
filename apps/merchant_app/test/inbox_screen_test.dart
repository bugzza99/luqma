import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/orders/inbox_screen.dart';

/// The screen the app exists for.
///
/// A merchant who does not answer an order does not cook it, and somebody waits for food
/// nobody started. Everything here is arranged around one question being answerable in
/// two taps while holding something hot.
void main() {
  const line = OrderLine(
    itemId: 'i1',
    name: 'فراخ مشوية',
    unitPrice: 12000,
    quantity: 2,
  );

  Order order({
    String id = 'o1',
    int number = 101,
    OrderStatus status = OrderStatus.placed,
    OrderType type = OrderType.instant,
    DateTime? deadline,
    bool isNewCustomer = false,
    String customerName = 'أحمد',
  }) =>
      Order(
        id: id,
        cityId: 'edku',
        orderNumber: number,
        customerUid: 'u1',
        customerName: customerName,
        customerPhone: '01000000000',
        merchantId: 'm1',
        merchantName: 'مطعم الشاطئ',
        zoneId: 'z1',
        type: type,
        items: const [line],
        pricing: const OrderPricing(
          subtotal: 24000,
          deliveryFee: 1000,
          total: 25000,
        ),
        status: status,
        isNewCustomer: isNewCustomer,
        acceptDeadlineAt: deadline,
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
            child: InboxScreen(),
          ),
        ),
      ),
    );
    // Pumped rather than settled: a card with a live countdown schedules a frame every
    // second, so a tree with one on it never goes idle. Three pumps carries the session,
    // then the first stream event, then whatever that event caused.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('what an order card says', () {
    testWidgets('the number, what was ordered, and what to collect',
        (tester) async {
      await pump(tester, seed: [order()]);

      expect(find.textContaining('101'), findsWidgets);
      expect(find.textContaining('فراخ مشوية'), findsWidgets);
      // Cash: this is the money a courier will physically collect.
      expect(find.textContaining('250 ج'), findsWidgets);
    });

    testWidgets('how many of each, not just the dish', (tester) async {
      await pump(tester, seed: [order()]);
      expect(find.textContaining('2'), findsWidgets);
    });

    // A customer with no delivered order is the fake-order risk the whole cash model
    // carries. The merchant phones before cooking.
    testWidgets('a first-time customer is flagged', (tester) async {
      await pump(tester, seed: [order(isNewCustomer: true)]);
      expect(find.byKey(InboxScreen.newCustomerKey('o1')), findsOneWidget);
    });

    testWidgets('a returning customer is not', (tester) async {
      await pump(tester, seed: [order()]);
      expect(find.byKey(InboxScreen.newCustomerKey('o1')), findsNothing);
    });
  });

  group('the countdown', () {
    testWidgets('an instant order shows how long is left', (tester) async {
      await pump(
        tester,
        seed: [
          order(deadline: DateTime.now().add(const Duration(minutes: 4))),
        ],
      );

      expect(find.byKey(InboxScreen.countdownKey('o1')), findsOneWidget);
    });

    // A pre-order was accepted the moment the seller published the meal. A timer on it
    // would count down to a deadline that does not exist.
    testWidgets('a pre-order shows none', (tester) async {
      await pump(
        tester,
        seed: [order(type: OrderType.preorder, deadline: null)],
      );

      expect(find.byKey(InboxScreen.countdownKey('o1')), findsNothing);
    });

    // The deadline passing does not remove the order — somebody is still waiting for
    // food — but a timer reading "-2:14" is worse than no timer.
    testWidgets('a deadline already gone reads as late, not as a negative number',
        (tester) async {
      await pump(
        tester,
        seed: [
          order(
            status: OrderStatus.needsAttention,
            deadline: DateTime.now().subtract(const Duration(minutes: 2)),
          ),
        ],
      );

      expect(find.byKey(InboxScreen.lateKey('o1')), findsOneWidget);
      expect(find.textContaining('-'), findsNothing);
    });
  });

  group('accepting', () {
    testWidgets('asks how long it will take', (tester) async {
      await pump(tester, seed: [order()]);

      await tester.tap(find.byKey(InboxScreen.acceptKey('o1')));
      await tester.pumpAndSettle();

      expect(find.byKey(InboxScreen.prepSheetKey), findsOneWidget);
    });

    testWidgets('a chosen time reaches the order', (tester) async {
      await pump(tester, seed: [order()]);

      await tester.tap(find.byKey(InboxScreen.acceptKey('o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(InboxScreen.prepChoiceKey(30)));
      await tester.pumpAndSettle();

      expect(orders['o1']!.status, OrderStatus.accepted);
      expect(orders['o1']!.prepMinutes, 30);
    });

    testWidgets('the order leaves the inbox once answered', (tester) async {
      await pump(tester, seed: [order()]);

      await tester.tap(find.byKey(InboxScreen.acceptKey('o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(InboxScreen.prepChoiceKey(30)));
      await tester.pumpAndSettle();

      expect(find.byKey(InboxScreen.acceptKey('o1')), findsNothing);
    });
  });

  group('rejecting', () {
    testWidgets('asks why', (tester) async {
      await pump(tester, seed: [order()]);

      await tester.tap(find.byKey(InboxScreen.rejectKey('o1')));
      await tester.pumpAndSettle();

      expect(find.byKey(InboxScreen.reasonSheetKey), findsOneWidget);
    });

    // Typing a reason with one hand while holding a pan is not going to happen, so the
    // common ones are one tap.
    testWidgets('a reason can be picked rather than typed', (tester) async {
      await pump(tester, seed: [order()]);

      await tester.tap(find.byKey(InboxScreen.rejectKey('o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(InboxScreen.reasonChoiceKey(0)));
      await tester.pumpAndSettle();

      expect(orders['o1']!.status, OrderStatus.cancelled);
      expect(orders['o1']!.cancelReason, isNotEmpty);
      expect(orders['o1']!.cancelledBy, OrderActor.merchant);
    });

    testWidgets('backing out of the sheet rejects nothing', (tester) async {
      await pump(tester, seed: [order()]);

      await tester.tap(find.byKey(InboxScreen.rejectKey('o1')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(orders['o1']!.status, OrderStatus.placed);
    });
  });

  group('a quiet evening', () {
    testWidgets('says so, rather than showing an empty screen', (tester) async {
      await pump(tester);
      expect(find.byKey(InboxScreen.emptyKey), findsOneWidget);
    });

    // The difference matters more here than anywhere else in the product: a merchant
    // who reads a failed connection as "no orders" stops checking.
    testWidgets('a failed read never looks like a quiet evening', (tester) async {
      await pump(tester, failure: const OfflineFailure());

      expect(find.byKey(InboxScreen.errorKey), findsOneWidget);
      expect(find.byKey(InboxScreen.emptyKey), findsNothing);
    });
  });
}
