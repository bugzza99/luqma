// The async preferences API keeps its official in-memory test backend in the platform
// interface package, so this test reaches that transitive package without making it an
// application dependency.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/courier/courier_screen.dart';
import 'package:merchant_app/src/courier/courier_write_store.dart';
import 'package:merchant_app/src/courier/navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Courier mode.
///
/// Deliberately the smallest screen in the product. Somebody reads it on a motorbike at
/// a junction: where to go, who to call, how much to collect, and two buttons.
void main() {
  const address = Address(
    id: 'a1',
    zoneId: 'z1',
    landmarkName: 'صيدلية النور',
    street: 'شارع البحر',
    building: '12',
    floor: '3',
  );

  const zones = [
    Zone(id: 'z1', cityId: 'edku', name: 'المعمورة', defaultDeliveryFee: 1000),
  ];

  Order order({
    String id = 'o1',
    int number = 101,
    OrderStatus status = OrderStatus.preparing,
    Address? at = address,
    String? courierUid,
  }) =>
      Order(
        id: id,
        cityId: 'edku',
        orderNumber: number,
        customerUid: 'u1',
        customerName: 'أحمد محمود',
        customerPhone: '01000000000',
        merchantId: 'm1',
        merchantName: 'مطعم الشاطئ',
        zoneId: 'z1',
        address: at,
        type: OrderType.instant,
        items: const [
          OrderLine(itemId: 'i1', name: 'فراخ مشوية', unitPrice: 12000, quantity: 2),
        ],
        pricing: const OrderPricing(
          subtotal: 24000,
          deliveryFee: 1000,
          total: 25000,
        ),
        status: status,
        courierUid: courierUid,
      );

  late FakeCourierOrderRepository deliveries;
  late FakeNavigator navigator;
  late FakeExternalLinks links;

  Future<void> pump(
    WidgetTester tester, {
    List<Order> seed = const [],
    Failure? failure,
    Map<String, Object?> claims = const {
      'role': 'courier',
      'scope': 'merchant',
      'merchantId': 'm1',
    },
    bool phoneCanDial = true,
  }) async {
    deliveries = FakeCourierOrderRepository(seed: seed, failure: failure);
    navigator = FakeNavigator();
    links = FakeExternalLinks(answer: phoneCanDial);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(
            FakeAuthService(
              restoring: LuqmaIdentity(uid: 'c1', claims: claims),
            ),
          ),
          courierOrderRepositoryProvider.overrideWithValue(deliveries),
          geographyRepositoryProvider
              .overrideWithValue(FakeGeographyRepository(zones: zones)),
          mapNavigatorProvider.overrideWithValue(navigator),
          externalLinksProvider.overrideWithValue(links),
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
            child: CourierScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the run', () {
    testWidgets('shows what there is to take out', (tester) async {
      await pump(tester, seed: [order()]);
      expect(find.byKey(CourierScreen.cardKey('o1')), findsOneWidget);
    });

    testWidgets('nothing to carry says so', (tester) async {
      await pump(tester);
      expect(find.byKey(CourierScreen.emptyKey), findsOneWidget);
    });

    testWidgets('a failed read never looks like nothing to carry', (tester) async {
      await pump(tester, failure: const OfflineFailure());

      expect(find.byKey(CourierScreen.errorKey), findsOneWidget);
      expect(find.byKey(CourierScreen.emptyKey), findsNothing);
    });
  });

  group('what the card has to say', () {
    testWidgets('the zone and the landmark, which is how anyone here navigates',
        (tester) async {
      await pump(tester, seed: [order()]);

      expect(find.textContaining('المعمورة'), findsWidgets);
      expect(find.textContaining('صيدلية النور'), findsWidgets);
    });

    // The single number that has to be right. Cash: this is what a person hands over.
    testWidgets('the cash to collect, loudly', (tester) async {
      await pump(tester, seed: [order()]);

      expect(
        find.descendant(
          of: find.byKey(CourierScreen.cashKey('o1')),
          matching: find.text('250 ج'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the customer and a way to call them', (tester) async {
      await pump(tester, seed: [order()]);

      expect(find.textContaining('أحمد محمود'), findsWidgets);
      expect(find.byKey(CourierScreen.callKey('o1')), findsOneWidget);
    });

    // An order whose address was somehow lost still has to open — the courier can phone.
    testWidgets('an order with no address still shows the phone', (tester) async {
      await pump(tester, seed: [order(at: null)]);

      expect(find.byKey(CourierScreen.callKey('o1')), findsOneWidget);
      expect(find.byKey(CourierScreen.noAddressKey('o1')), findsOneWidget);
    });

    testWidgets('and the button actually dials', (tester) async {
      await pump(tester, seed: [order()]);

      await tester.tap(find.byKey(CourierScreen.callKey('o1')));
      await tester.pumpAndSettle();

      expect(links.opened.single.scheme, 'tel');
      expect(links.opened.single.path, '01000000000');
    });

    // The most expensive silent failure in the product. `launchUrl` throws when no
    // activity is registered for `tel:` and returns false when nothing handles it, and
    // this button ignored both: the courier is at somebody's door holding their food,
    // taps to ring them, and the screen does not change. Reading the number out is a
    // worse answer than dialling and a far better one than nothing.
    testWidgets('a handset that refuses tel: reads the number out',
        (tester) async {
      await pump(tester, seed: [order()], phoneCanDial: false);

      await tester.tap(find.byKey(CourierScreen.callKey('o1')));
      await tester.pumpAndSettle();

      expect(find.textContaining('01000000000'), findsWidgets);
    });
  });

  group('navigating', () {
    // Handed to the maps app the courier already has, which is free, current, and
    // speaks. Nothing in-app could match it.
    testWidgets('hands the address to the maps app', (tester) async {
      await pump(tester, seed: [order()]);

      await tester.tap(find.byKey(CourierScreen.navigateKey('o1')));
      await tester.pumpAndSettle();

      expect(navigator.lastQuery, contains('المعمورة'));
      expect(navigator.lastQuery, contains('صيدلية النور'));
    });

    testWidgets('offers nothing to navigate to when there is no address',
        (tester) async {
      await pump(tester, seed: [order(at: null)]);
      expect(find.byKey(CourierScreen.navigateKey('o1')), findsNothing);
    });
  });

  group('the two buttons', () {
    testWidgets('an order in the kitchen can be taken out', (tester) async {
      await pump(tester, seed: [order()]);

      await tester.tap(find.byKey(CourierScreen.outKey('o1')));
      await tester.pumpAndSettle();

      expect(deliveries['o1']!.status, OrderStatus.outForDelivery);
      // Their own name, so the customer knows who has it and the rules keep letting
      // them read it.
      expect(deliveries['o1']!.courierUid, 'c1');
    });

    testWidgets('an order on the road can be delivered', (tester) async {
      await pump(
        tester,
        seed: [order(status: OrderStatus.outForDelivery, courierUid: 'c1')],
      );

      await tester.tap(find.byKey(CourierScreen.deliveredKey('o1')));
      await tester.pumpAndSettle();
      // Confirmed, because delivered means the cash changed hands.
      await tester.tap(find.text('اه، تم'));
      await tester.pumpAndSettle();

      expect(deliveries['o1']!.status, OrderStatus.delivered);
    });

    // Delivered means the cash changed hands. Asking once costs a second; getting it
    // wrong costs the money.
    testWidgets('delivering asks first, and says the amount again', (tester) async {
      await pump(
        tester,
        seed: [order(status: OrderStatus.outForDelivery, courierUid: 'c1')],
      );

      await tester.tap(find.byKey(CourierScreen.deliveredKey('o1')));
      await tester.pump();

      expect(find.byKey(CourierScreen.confirmDeliveredKey), findsOneWidget);
      expect(find.textContaining('250 ج'), findsWidgets);
    });

    testWidgets('an order still in the kitchen offers no delivered button',
        (tester) async {
      await pump(tester, seed: [order()]);
      expect(find.byKey(CourierScreen.deliveredKey('o1')), findsNothing);
    });
  });

  group('a door nobody answers', () {
    testWidgets('can be reported, with a reason', (tester) async {
      await pump(
        tester,
        seed: [order(status: OrderStatus.outForDelivery, courierUid: 'c1')],
      );

      await tester.tap(find.byKey(CourierScreen.failedKey('o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CourierScreen.reasonKey(0)));
      await tester.pumpAndSettle();

      expect(deliveries['o1']!.status, OrderStatus.cancelled);
      expect(deliveries['o1']!.cancelReason, isNotEmpty);
      expect(deliveries['o1']!.cancelledBy, OrderActor.courier);
    });
  });

  group('the platform courier', () {
    testWidgets('sees the platform\'s work rather than one merchant\'s',
        (tester) async {
      await pump(
        tester,
        claims: const {'role': 'courier', 'scope': 'platform'},
        seed: [
          order(id: 'ours', number: 101).copyWith(deliveryBy: DeliveryBy.platform),
          order(id: 'theirs', number: 102),
        ],
      );

      expect(find.byKey(CourierScreen.cardKey('ours')), findsOneWidget);
      expect(find.byKey(CourierScreen.cardKey('theirs')), findsNothing);
    });
  });

  group('a tap that dies with the connection', () {
    // The one case where a lost write is money lost: cash collected against an order
    // the system still thinks is out. The tap must be held, and the screen must say so.
    testWidgets('is queued, not lost, and flushes on retry', (tester) async {
      await pump(
        tester,
        seed: [order(status: OrderStatus.outForDelivery, courierUid: 'c1')],
      );

      // The connection drops exactly as the courier confirms the cash is in hand.
      deliveries.failure = const OfflineFailure();

      await tester.tap(find.byKey(CourierScreen.deliveredKey('o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('اه، تم'));
      await tester.pumpAndSettle();

      // Still out, but the tap is saved and the screen says so honestly.
      expect(find.byKey(CourierScreen.pendingKey), findsOneWidget);
      expect(deliveries['o1']!.status, OrderStatus.outForDelivery);

      // The connection returns; retry sends what was held.
      deliveries.failure = null;
      await tester.tap(find.byKey(CourierScreen.retryKey));
      await tester.pumpAndSettle();

      expect(deliveries['o1']!.status, OrderStatus.delivered);
      expect(find.byKey(CourierScreen.pendingKey), findsNothing);
    });

    // Dropping a conflicting write is right; dropping it silently is not. The banner
    // above promises "هيتبعت أول ما النت يرجع", so a count that quietly falls by one
    // reads as sent — while the cash for that order is already in the courier's pocket.
    testWidgets('and a queued tap the server refuses is said out loud', (tester) async {
      await pump(
        tester,
        seed: [order(status: OrderStatus.outForDelivery, courierUid: 'c1')],
      );

      deliveries.failure = const OfflineFailure();
      await tester.tap(find.byKey(CourierScreen.deliveredKey('o1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('اه، تم'));
      await tester.pumpAndSettle();
      expect(find.byKey(CourierScreen.pendingKey), findsOneWidget);

      // The connection returns, but the order moved while there was no signal.
      deliveries.failure = const ConflictFailure();
      await tester.tap(find.byKey(CourierScreen.retryKey));
      await tester.pumpAndSettle();

      expect(find.byKey(CourierScreen.pendingKey), findsNothing,
          reason: 'it is not retried for ever');
      expect(find.byKey(CourierScreen.rejectedKey), findsOneWidget,
          reason: 'but the courier is told it never landed');

      await tester.tap(find.byKey(CourierScreen.dismissRejectedKey));
      await tester.pumpAndSettle();
      expect(find.byKey(CourierScreen.rejectedKey), findsNothing);
    });
  });

  group('the durable queue store', () {
    late SharedPreferencesAsyncPlatform? previousPlatform;
    late SharedPreferencesAsync prefs;
    late SharedPreferencesCourierWriteStore store;

    const delivered = PendingCourierWrite(
      orderId: 'o1',
      kind: CourierWriteKind.delivered,
    );

    setUp(() {
      previousPlatform = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      prefs = SharedPreferencesAsync();
      store = SharedPreferencesCourierWriteStore(prefs: prefs);
    });

    tearDown(() => SharedPreferencesAsyncPlatform.instance = previousPlatform);

    test('an account gets a versioned envelope of only its own writes', () async {
      await store.save(accountId: 'c1', pending: const [delivered]);

      expect(await store.load(accountId: 'c2'), isEmpty);
      expect(await store.load(accountId: 'c1'), hasLength(1));

      final raw = await prefs.getString('courier_write_queue.account.c1.v1');
      final envelope = jsonDecode(raw!) as Map<String, dynamic>;
      expect(envelope['version'], 1);
      expect(envelope['writes'], hasLength(1));
    });

    test('the signed-in account claims the old bare list once', () async {
      final legacy = jsonEncode([delivered.toJson()]);
      await prefs.setString('courier_write_queue', legacy);

      final migrated = await store.load(accountId: 'c1');

      expect(migrated.single.orderId, 'o1');
      expect(await prefs.getString('courier_write_queue'), isNull);

      // Even an interrupted removal or an old build putting the key back cannot make
      // cash writes that were claimed by one courier appear under the next courier.
      await prefs.setString('courier_write_queue', legacy);
      expect(await store.load(accountId: 'c2'), isEmpty);
      expect(await store.load(accountId: 'c1'), hasLength(1));
    });

    test('a newer schema survives this build saving its own queue', () async {
      const futureKey = 'courier_write_queue.account.c1.v2';
      final futureRaw = jsonEncode({
        'version': 2,
        'writes': [
          {'futureOrder': 'o2'},
        ],
      });
      await prefs.setString(futureKey, futureRaw);

      expect(await store.load(accountId: 'c1'), isEmpty);
      await store.save(accountId: 'c1', pending: const [delivered]);

      expect(await prefs.getString(futureKey), futureRaw);
      expect(
        await prefs.getString('courier_write_queue.account.c1.v1'),
        isNotNull,
      );
    });
  });
}
