import 'package:customer_app/src/cart/cart.dart';
import 'package:customer_app/src/cart/cart_controller.dart';
import 'package:customer_app/src/checkout/checkout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Cash on delivery.
///
/// The number on this screen is money a person will physically hand to a courier at a
/// door. Every rule here follows from that: it must be visible before the order is sent,
/// it must be broken down, and it must be the server's number rather than the phone's.
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
    servedZones: ['z1', 'z2'],
    openingHours: alwaysOpen,
  );

  const zones = [
    Zone(id: 'z1', cityId: 'edku', name: 'المعمورة', defaultDeliveryFee: 1000),
    Zone(id: 'z2', cityId: 'edku', name: 'الشط', defaultDeliveryFee: 1500),
    Zone(id: 'z9', cityId: 'edku', name: 'برج مغيزل', defaultDeliveryFee: 2500),
  ];

  const home = Address(id: 'a1', zoneId: 'z1', label: 'البيت');
  const beach = Address(id: 'a2', zoneId: 'z2', label: 'الشط');
  const faraway = Address(id: 'a9', zoneId: 'z9', label: 'بعيد');

  const cart = Cart(
    merchantId: 'm1',
    lines: [
      CartLine(
        id: 'l1',
        itemId: 'i1',
        merchantId: 'm1',
        name: 'فراخ مشوية',
        unitPrice: 12000,
        quantity: 1,
      ),
    ],
  );

  late ProviderContainer container;
  late FakeOrderRepository orders;
  late String? placedOrderId;

  Future<void> pump(
    WidgetTester tester, {
    Merchant merchant = shore,
    List<Address> addresses = const [home],
    Failure? placementFails,
    LuqmaIdentity? signedInAs = const LuqmaIdentity(uid: 'u1', name: 'أحمد'),
  }) async {
    orders = FakeOrderRepository(failure: placementFails);
    placedOrderId = null;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider
              .overrideWithValue(FakeAuthService(restoring: signedInAs)),
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: [merchant])),
          geographyRepositoryProvider
              .overrideWithValue(FakeGeographyRepository(zones: zones)),
          addressRepositoryProvider.overrideWithValue(
            FakeAddressRepository(
              seed: signedInAs == null ? const {} : {signedInAs.uid: addresses},
            ),
          ),
          orderRepositoryProvider.overrideWithValue(orders),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
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
                child: CheckoutScreen(
                  onPlaced: (order) => placedOrderId = order.id,
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the bill', () {
    testWidgets('shows the food, the delivery and the total separately',
        (tester) async {
      await pump(tester);

      expect(find.text('120 ج'), findsWidgets); // food
      expect(find.text('10 ج'), findsWidgets); // delivery into المعمورة
      // The one number that will actually change hands.
      expect(
        find.descendant(
          of: find.byKey(CheckoutScreen.totalKey),
          matching: find.text('130 ج'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the delivery follows the zone of the chosen address',
        (tester) async {
      // The seeded default is the first one — الشط, which this merchant serves at 15.
      await pump(tester, addresses: const [beach, home]);

      expect(find.text('15 ج'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(CheckoutScreen.totalKey),
          matching: find.text('135 ج'),
        ),
        findsOneWidget,
      );
    });

    // Cash only at launch. Offering a choice that has one option is a step for nothing.
    testWidgets('says it is cash, with no payment method to choose', (tester) async {
      await pump(tester);

      expect(find.byKey(CheckoutScreen.cashKey), findsOneWidget);
    });
  });

  group('what has to be true before it can be sent', () {
    testWidgets('an address is required', (tester) async {
      await pump(tester, addresses: const []);

      expect(find.byKey(CheckoutScreen.needsAddressKey), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(CheckoutScreen.placeKey))
            .onPressed,
        isNull,
      );
    });

    // A merchant that does not deliver to this zone cannot cook this order at all, and
    // finding that out from a rejection an hour later is the worst way to learn it.
    testWidgets('the merchant has to deliver to that zone', (tester) async {
      await pump(tester, addresses: const [faraway]);

      expect(find.byKey(CheckoutScreen.outOfRangeKey), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(CheckoutScreen.placeKey))
            .onPressed,
        isNull,
      );
    });

    testWidgets('signed out, it asks for an account rather than failing later',
        (tester) async {
      await pump(tester, signedInAs: null);

      expect(find.byKey(CheckoutScreen.signInKey), findsOneWidget);
      expect(find.byKey(CheckoutScreen.placeKey), findsNothing);
    });
  });

  group('sending it', () {
    testWidgets('the order goes out and the basket is emptied', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(placedOrderId, isNotNull);
      // Left full, the next screen would offer to send the same order again.
      expect(container.read(cartProvider).isEmpty, isTrue);
    });

    testWidgets('the button cannot be pressed twice', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(find.byKey(CheckoutScreen.placeKey))
            .onPressed,
        isNull,
      );
      await tester.pumpAndSettle();
    });

    // A basket thrown away on a failed send is an order the customer has to rebuild
    // from memory.
    testWidgets('a refused order keeps the basket and says why', (tester) async {
      await pump(tester, placementFails: const OfflineFailure());

      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(find.byKey(CheckoutScreen.errorKey), findsOneWidget);
      expect(container.read(cartProvider).isEmpty, isFalse);
      expect(placedOrderId, isNull);
    });

    testWidgets('after a refusal it can be tried again', (tester) async {
      await pump(tester, placementFails: const OfflineFailure());

      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.byKey(CheckoutScreen.placeKey))
            .onPressed,
        isNotNull,
      );
    });
  });

  group('the note to the merchant', () {
    testWidgets('travels with the order', (tester) async {
      await pump(tester);

      // Lives at the bottom of a lazily built list, so it has to be scrolled into
      // existence before it can be typed into.
      await tester.scrollUntilVisible(find.byKey(CheckoutScreen.noteKey), 200);
      await tester.enterText(
        find.byKey(CheckoutScreen.noteKey),
        'الشقة فوق الصيدلية',
      );
      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(orders.drafts.single.note, 'الشقة فوق الصيدلية');
    });

    testWidgets('an empty note is no note at all', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      // A blank line on the kitchen ticket is worse than nothing on it.
      expect(orders.drafts.single.note, isNull);
    });
  });

  group('what the server is asked for', () {
    // The phone says what was wanted; the server says what it costs. Sending a total
    // would be sending a price the customer's device chose.
    testWidgets('the draft carries the basket and the address, not a total',
        (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      final draft = orders.drafts.single;
      expect(draft.merchantId, 'm1');
      expect(draft.addressId, 'a1');
      expect(draft.items.single.name, 'فراخ مشوية');
      expect(draft.type, OrderType.instant);
      expect(draft.toJson().containsKey('total'), isFalse);
    });
  });
}
