import 'package:customer_app/src/cart/cart.dart';
import 'package:customer_app/src/address/address_editor_screen.dart';
import 'package:customer_app/src/address/address_list_screen.dart';
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
  late ValueNotifier<bool> reducedMotion;

  Future<void> pump(
    WidgetTester tester, {
    Merchant merchant = shore,
    List<Address> addresses = const [home],
    Failure? placementFails,
    bool reduced = false,
    LuqmaIdentity? signedInAs =
        const LuqmaIdentity(uid: 'u1', name: 'أحمد', phone: '01012345678'),
  }) async {
    orders = FakeOrderRepository(failure: placementFails);
    profiles = FakeProfileRepository();
    placedOrderId = null;
    reducedMotion = ValueNotifier(reduced);
    addTearDown(reducedMotion.dispose);

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
          builder: (context, child) => ValueListenableBuilder<bool>(
            valueListenable: reducedMotion,
            builder: (context, reduced, _) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
          ),
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

  for (final hasAddress in [false, true]) {
    testWidgets('checkout carries its merchant ${hasAddress ? 'through the list' : 'to the editor'}',
        (tester) async {
      await pump(tester, addresses: hasAddress ? const [home] : const []);
      await tester.ensureVisible(find.byKey(CheckoutScreen.changeAddressKey));
      await tester.tap(find.byKey(CheckoutScreen.changeAddressKey));
      await tester.pumpAndSettle();
      if (hasAddress) {
        expect(tester.widget<AddressListScreen>(find.byType(AddressListScreen)).merchantId, 'm1');
        await tester.tap(find.byKey(AddressListScreen.addKey));
        await tester.pumpAndSettle();
      }
      expect(tester.widget<AddressEditorScreen>(find.byType(AddressEditorScreen)).merchantId, 'm1');
      await tester.tap(find.text('المعمورة'));
      await tester.pumpAndSettle();
      expect(find.text('التوصيل للمنطقة دي: 10 ج'), findsOneWidget);
    });
  }

  group('the bill', () {
    testWidgets('the address separates the landmark from the street details',
        (tester) async {
      await pump(tester, addresses: [home.copyWith(
        landmarkName: 'الصيدلية', street: 'شارع البحر', building: '2',
        floor: '3', apartment: '4',
      )]);
      expect(find.text('المعمورة · جنب الصيدلية'), findsOneWidget);
      expect(find.text('شارع البحر · عمارة 2 · الدور 3 · شقة 4'), findsOneWidget);
    });

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
      expect(find.text('التوصيل — الشط'), findsOneWidget);
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
      expect(find.text('التوصيل'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
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

    testWidgets('a retry keeps the checkout id from the first tap', (tester) async {
      await pump(tester, placementFails: const OfflineFailure());

      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(orders.drafts, hasLength(2));
      expect(orders.drafts.first.clientOrderId, isNotNull);
      expect(
        orders.drafts.last.clientOrderId,
        orders.drafts.first.clientOrderId,
        reason: 'the screen survives a failed response, so its id must survive too',
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

  Future<void> applyCoupon(WidgetTester tester, {int deliveryDiscount = 0}) async {
    orders.couponEvaluation = CouponAccepted(
      subtotalDiscount: 2000,
      deliveryDiscount: deliveryDiscount,
      platformOwesMerchant: 0,
    );
    await tester.ensureVisible(find.byKey(CheckoutScreen.couponApplyKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(CheckoutScreen.couponInputKey), 'SAVE20');
    await tester.tap(find.byKey(CheckoutScreen.couponApplyKey));
    await tester.pump();
  }

  void expectTotals(String amount) {
    expect(find.descendant(
      of: find.byKey(CheckoutScreen.totalKey), matching: find.text(amount),
    ), findsOneWidget);
    expect(find.descendant(
      of: find.byKey(CheckoutScreen.placeKey),
      matching: find.text('اطلب دلوقتي · $amount'),
    ), findsOneWidget);
  }

  group('the coupon', () {
    testWidgets('both discounts keep their own row and the footer follows the bill',
        (tester) async {
      await pump(tester);
      expectTotals('130 ج');
      await applyCoupon(tester, deliveryDiscount: 500);
      await tester.pumpAndSettle();
      expect(find.descendant(
        of: find.byKey(CheckoutScreen.billDiscountKey),
        matching: find.text('− 20 ج'),
      ), findsOneWidget);
      final deliveryRow = find.ancestor(
        of: find.text('خصم التوصيل'), matching: find.byType(Row),
      ).first;
      expect(find.descendant(of: deliveryRow, matching: find.text('− 5 ج')),
          findsOneWidget);
      expectTotals('105 ج');
      await tester.tap(find.byKey(CheckoutScreen.couponRemoveKey));
      await tester.pumpAndSettle();
      expectTotals('130 ج');
    });

    testWidgets('a changed delivery fee drops the card and the code on the draft',
        (tester) async {
      await pump(tester, addresses: const [home, beach]);
      await applyCoupon(tester);
      await tester.pumpAndSettle();
      expectTotals('110 ج');
      await container.read(addressRepositoryProvider).setDefaultAddress('u1', 'a2');
      container.invalidate(chosenAddressProvider);
      await tester.pumpAndSettle();
      expect(find.byKey(CheckoutScreen.couponCardKey), findsNothing);
      expect(find.byKey(CheckoutScreen.couponInputKey), findsOneWidget);
      expectTotals('135 ج');
      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();
      expect(orders.drafts.single.couponCode, isNull);
      expect(orders.drafts.single.addressId, 'a2');
    });

    testWidgets('an unavailable apply action is disabled rather than a no-op button',
        (tester) async {
      await pump(tester);
      container.read(cartProvider.notifier).clear();
      await tester.pumpAndSettle();
      final action = find.byKey(CheckoutScreen.couponApplyKey);
      expect(find.descendant(of: action, matching: find.byType(InkWell)), findsNothing);
      final semantics = tester.widget<Semantics>(find.descendant(
        of: action, matching: find.byType(Semantics),
      ).first);
      expect(semantics.properties.enabled, isFalse);
    });

    testWidgets('coupon actions keep 48 targets and an eight pixel input gap',
        (tester) async {
      await pump(tester);
      void target(Key key) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      target(CheckoutScreen.changeAddressKey);
      target(CheckoutScreen.couponApplyKey);
      expect(tester.getTopLeft(find.byKey(CheckoutScreen.couponInputKey)).dx -
          tester.getTopRight(find.byKey(CheckoutScreen.couponApplyKey)).dx,
          greaterThanOrEqualTo(8));
      await applyCoupon(tester);
      await tester.pumpAndSettle();
      target(CheckoutScreen.couponRemoveKey);
    });

    testWidgets('coupon replacement changes size while the footer has one tappable total',
        (tester) async {
      await pump(tester);
      await applyCoupon(tester);
      final card = find.byKey(CheckoutScreen.couponCardKey);
      final transition = find.ancestor(of: card, matching: find.byType(SizeTransition));
      expect(transition, findsOneWidget);
      expect(tester.widget<SizeTransition>(transition).sizeFactor.value, lessThan(1));
      final footer = find.byKey(CheckoutScreen.placeKey);
      final pulse = find.descendant(of: footer,
          matching: find.byType(TweenAnimationBuilder<double>));
      double scale() => tester.widget<Transform>(find.descendant(
        of: pulse, matching: find.byType(Transform),
      ).first).transform.storage.first;
      expect(scale(), lessThan(1));
      for (var frame = 0; frame < 12; frame++) {
        expect(find.descendant(of: footer,
            matching: find.text('اطلب دلوقتي · 130 ج')), findsNothing);
        expect(find.descendant(of: footer,
            matching: find.text('اطلب دلوقتي · 110 ج')), findsOneWidget);
        expect(tester.widget<FilledButton>(footer).onPressed, isNotNull);
        expect(footer.hitTestable(), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scale(), 1);
      await tester.tap(find.byKey(CheckoutScreen.couponRemoveKey));
      await tester.pump();
      final fieldTransition = find.ancestor(
        of: find.byKey(CheckoutScreen.couponInputKey),
        matching: find.byType(SizeTransition),
      );
      expect(tester.widget<SizeTransition>(fieldTransition).sizeFactor.value,
          lessThan(1));
      expect(find.descendant(of: footer,
          matching: find.text('اطلب دلوقتي · 110 ج')), findsNothing);
      expect(find.descendant(of: footer,
          matching: find.text('اطلب دلوقتي · 130 ج')), findsOneWidget);
      await tester.tap(footer);
      await tester.pumpAndSettle();
      expect(orders.drafts.single.couponCode, isNull);
    });

    for (final reducedAtStart in [false, true]) {
      testWidgets('reduced motion ${reducedAtStart ? 'from entry' : 'during a pulse'} keeps actions usable',
          (tester) async {
        await pump(tester, reduced: reducedAtStart);
        await applyCoupon(tester);
        reducedMotion.value = true;
        await tester.pump();
        expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
        expect(find.byType(LuqmaEntrance), findsNothing);
        expect(find.ancestor(of: find.byKey(CheckoutScreen.couponCardKey),
            matching: find.byType(SizeTransition)), findsNothing);
        expectTotals('110 ج');
        await tester.tap(find.byKey(CheckoutScreen.couponRemoveKey));
        await tester.pump();
        expect(find.byKey(CheckoutScreen.couponCardKey), findsNothing);
        expect(find.byKey(CheckoutScreen.couponInputKey).hitTestable(), findsOneWidget);
        expectTotals('130 ج');
        await tester.tap(find.byKey(CheckoutScreen.placeKey));
        await tester.pumpAndSettle();
        expect(orders.drafts.single.couponCode, isNull);
      });
    }

    testWidgets('an accepted code becomes a card, and discounts the bill',
        (tester) async {
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

      // The field and the card are one slot: a box still offering «طبّق» under a code
      // that is already on reads as a second discount waiting to be claimed.
      expect(find.byKey(CheckoutScreen.couponCardKey), findsOneWidget);
      expect(find.byKey(CheckoutScreen.couponInputKey), findsNothing);
      expect(find.text('كود SAVE20 اتطبق'), findsOneWidget);
      expect(find.descendant(
        of: find.byKey(CheckoutScreen.couponCardKey),
        matching: find.text('وفّرت 20 ج'),
      ), findsOneWidget);

      // The discount line, then the new total: 130 - 20 = 110.
      expect(find.text('− 20 ج'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(CheckoutScreen.totalKey),
          matching: find.text('110 ج'),
        ),
        findsOneWidget,
      );
    });

    // The screen renders from `_couponEvaluation` and `_place` sends
    // `_appliedCouponCode`. Removing has to clear both, or the customer is shown a total
    // the courier will not collect — which is the whole reason this control exists rather
    // than making somebody restart the order to drop a code.
    testWidgets('and «شيل» takes it back off, in full', (tester) async {
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

      await tester.ensureVisible(find.byKey(CheckoutScreen.couponRemoveKey));
      await tester.tap(find.byKey(CheckoutScreen.couponRemoveKey));
      await tester.pumpAndSettle();

      // Off the screen: the card is gone, the box is back, and it is empty rather than
      // still holding the code that was just dropped.
      expect(find.byKey(CheckoutScreen.couponCardKey), findsNothing);
      expect(find.byKey(CheckoutScreen.couponInputKey), findsOneWidget);
      expect(find.text('SAVE20'), findsNothing);
      expect(tester.widget<TextField>(find.byKey(CheckoutScreen.couponInputKey))
          .controller!.text, isEmpty);
      expect(find.byKey(CheckoutScreen.billDiscountKey), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(CheckoutScreen.totalKey),
          matching: find.text('130 ج'),
        ),
        findsOneWidget,
      );

      // And off the order. This is the half a screen cannot show: placing now must not
      // carry the code the customer just removed.
      await tester.ensureVisible(find.byKey(CheckoutScreen.placeKey));
      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(orders.drafts.single.couponCode, isNull);
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
      expect(find.byKey(CheckoutScreen.couponCardKey), findsNothing);
      expect(find.byKey(CheckoutScreen.couponRemoveKey), findsNothing);
      expect(find.byKey(CheckoutScreen.couponInputKey), findsOneWidget);
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

  // The server refuses an order for about a dozen named reasons. Each is its own
  // sentence here, because «جرّب تاني» is only true of one of them — the dead
  // connection — and was said for all of them.
  group('a refusal from the server', () {
    // Previewed as accepted, then taken by somebody else's last use before this order
    // went. Every retry re-sent the dead code and failed with a sentence about the
    // network, until the customer happened to tap «شيل».
    testWidgets('a coupon refused at placement is taken off, with its reason',
        (tester) async {
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

      orders.failure = const CouponFailure(CouponRejection.exhausted);
      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('الكود ده مبقاش ينفع'), findsOneWidget);
      expect(find.textContaining('مفيش نت'), findsNothing);

      // And the next tap sends the order without it, and goes through.
      orders.failure = null;
      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();
      expect(orders.drafts.last.couponCode, isNull);
      expect(placedOrderId, isNotNull);
    });

    testWidgets('a dish switched off says so rather than «جرّب تاني»', (tester) async {
      await pump(
        tester,
        placementFails: const OrderRefusedFailure(OrderRefusal.dishUnavailable),
      );

      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('مبقاش متاح'), findsOneWidget);
      expect(find.textContaining('جرّب تاني'), findsNothing);
    });

    testWidgets('a shut shop says it is shut', (tester) async {
      await pump(
        tester,
        placementFails: const OrderRefusedFailure(OrderRefusal.shopClosed),
      );

      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('مش بيستقبل طلبات'), findsOneWidget);
    });

    // A blocked customer is signed in. «لازم تسجّل دخول» sent them round a loop.
    testWidgets('a blocked account is not asked to sign in', (tester) async {
      await pump(tester, placementFails: const AccountBlockedFailure());

      await tester.tap(find.byKey(CheckoutScreen.placeKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('تسجّل دخول'), findsNothing);
      expect(find.textContaining('موقوف'), findsOneWidget);
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
