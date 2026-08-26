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
  late FakeProfileRepository profiles;
  late String? placedOrderId;

  Future<void> pump(
    WidgetTester tester, {
    Merchant merchant = shore,
    List<Address> addresses = const [home],
    Failure? placementFails,
    LuqmaIdentity? signedInAs =
        const LuqmaIdentity(uid: 'u1', name: 'أحمد', phone: '01012345678'),
  }) async {
    orders = FakeOrderRepository(failure: placementFails);
    profiles = FakeProfileRepository();
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
          profileRepositoryProvider.overrideWithValue(profiles),
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
      await tester.dragUntilVisible(
        find.byKey(CheckoutScreen.noteKey),
        find.byType(ListView),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
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

  group('the coupon', () {
    testWidgets('an accepted code discounts the bill and says so', (tester) async {
      await pump(tester);
      orders.couponEvaluation = const CouponAccepted(
        subtotalDiscount: 2000,
        deliveryDiscount: 0,
        platformOwesMerchant: 0,
      );

      await tester.ensureVisible(find.byKey(CheckoutScreen.couponApplyKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(CheckoutScreen.couponInputKey), 'SAVE20');
      await tester.tap(find.byKey(CheckoutScreen.couponApplyKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('وفرت'), findsOneWidget);
      expect(find.byKey(CheckoutScreen.couponFeedbackKey), findsOneWidget);
      // The discount line, then the new total: 130 - 20 = 110.
      expect(find.text('-20 ج'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(CheckoutScreen.totalKey),
          matching: find.text('110 ج'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a rejected code says why and leaves the bill alone',
        (tester) async {
      await pump(tester);
      orders.couponEvaluation = const CouponRejected(CouponRejection.expired);

      await tester.ensureVisible(find.byKey(CheckoutScreen.couponApplyKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(CheckoutScreen.couponInputKey), 'OLD');
      await tester.tap(find.byKey(CheckoutScreen.couponApplyKey));
      await tester.pumpAndSettle();

      expect(find.text('صلاحية الكود خلصت.'), findsOneWidget);
      expect(find.byKey(CheckoutScreen.couponFeedbackKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(CheckoutScreen.totalKey),
          matching: find.text('130 ج'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an accepted code rides on the draft; a rejected one does not',
        (tester) async {
      await pump(tester);
      orders.couponEvaluation =
          const CouponRejected(CouponRejection.minOrderNotMet);

      await tester.ensureVisible(find.byKey(CheckoutScreen.couponApplyKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(CheckoutScreen.couponInputKey), 'SMALL');
      await tester.tap(find.byKey(CheckoutScreen.couponApplyKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(orders.drafts.single.couponCode, isNull);
    });

    testWidgets('an accepted code is sent with the order', (tester) async {
      await pump(tester);
      orders.couponEvaluation = const CouponAccepted(
        subtotalDiscount: 2000,
        deliveryDiscount: 0,
        platformOwesMerchant: 0,
      );

      await tester.ensureVisible(find.byKey(CheckoutScreen.couponApplyKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(CheckoutScreen.couponInputKey), 'SAVE20');
      await tester.tap(find.byKey(CheckoutScreen.couponApplyKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(placedOrderId, isNotNull);
      expect(orders.drafts.single.couponCode, 'SAVE20');
    });
  });

  group('the phone', () {
    // A Google account usually carries no phone, and a courier with nobody to call
    // cannot deliver. The field appears only when the identity has none, and the order
    // is not sent until it holds a valid Egyptian mobile.
    testWidgets('is asked for when the account has none', (tester) async {
      await pump(
        tester,
        signedInAs: const LuqmaIdentity(uid: 'u1', name: 'أحمد'),
      );

      expect(find.byKey(CheckoutScreen.phoneKey), findsOneWidget);
    });

    testWidgets('is not asked again when the account already has one',
        (tester) async {
      await pump(tester);

      expect(find.byKey(CheckoutScreen.phoneKey), findsNothing);
    });

    testWidgets('an invalid phone stops the order and says why', (tester) async {
      await pump(
        tester,
        signedInAs: const LuqmaIdentity(uid: 'u1', name: 'أحمد'),
      );

      await tester.ensureVisible(find.byKey(CheckoutScreen.phoneKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(CheckoutScreen.phoneKey), '123');
      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(placedOrderId, isNull);
      expect(orders.drafts, isEmpty);
      expect(find.textContaining('رقم موبايل مصري صحيح'), findsOneWidget);
    });

    testWidgets('a valid phone is saved and the order goes out', (tester) async {
      await pump(
        tester,
        signedInAs: const LuqmaIdentity(uid: 'u1', name: 'أحمد'),
      );

      await tester.ensureVisible(find.byKey(CheckoutScreen.phoneKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(CheckoutScreen.phoneKey),
        '01098765432',
      );
      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(placedOrderId, isNotNull);
      expect(profiles.phones['u1'], '01098765432');
    });
  });
}
