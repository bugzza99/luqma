import 'package:customer_app/src/kitchen/preorder_checkout_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Confirming a reservation.
///
/// This screen had no tests at all, which is how the gap below survived: it is 400-odd
/// lines, it is the only path to a pre-order, and it is a money path. The ordinary
/// checkout has had a served-zone guard since it was written; this one asked only
/// whether an address existed.
void main() {
  const today = '2026-08-23';
  // Inside the collection window, so "can this still be reserved" stays a question about
  // the meal rather than about what time the suite happens to run.
  final now = DateTime(2026, 8, 23, 11);

  const kitchen = Merchant(
    id: 'm1',
    cityId: 'edku',
    type: MerchantType.homeKitchen,
    name: 'مطبخ أم أحمد',
    zoneId: 'z1',
    // It serves its own zone and one more. Not z9.
    servedZones: ['z2'],
    phone: '01000000000',
    status: MerchantStatus.approved,
  );

  DailyMeal meal({
    DeliveryOption deliveryOption = DeliveryOption.platformCourier,
  }) =>
      DailyMeal(
        id: 'd1',
        merchantId: 'm1',
        cityId: 'edku',
        name: 'محشي كرنب',
        description: 'اتعمل النهارده الصبح',
        price: 9000,
        date: today,
        totalQty: 20,
        remainingQty: 8,
        pickupWindowStart: 13 * 60,
        pickupWindowEnd: 16 * 60,
        deliveryOption: deliveryOption,
        status: DailyMealStatus.published,
      );

  Address address(String zoneId) => Address(
        id: 'a1',
        zoneId: zoneId,
        label: 'البيت',
      );

  const zones = [
    Zone(id: 'z1', cityId: 'edku', name: 'وسط البلد'),
    Zone(id: 'z9', cityId: 'edku', name: 'المعمورة'),
  ];

  late FakeOrderRepository orders;
  Order? placed;

  Future<void> pump(
    WidgetTester tester, {
    required DailyMeal dish,
    Address? chosen,
    Merchant cook = kitchen,
    LuqmaConfig config = LuqmaConfig.defaults,
  }) async {
    orders = FakeOrderRepository();
    placed = null;
    // A phone, not the 800x600 default: that window is wider than it is tall and unlike
    // any device this ships on, which has hidden real layout faults here before.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: [cook])),
          orderRepositoryProvider.overrideWithValue(orders),
          appConfigProvider.overrideWithValue(config),
          geographyRepositoryProvider
              .overrideWithValue(FakeGeographyRepository(zones: zones)),
          currentIdentityProvider.overrideWith((ref) => Stream.value(
                const LuqmaIdentity(uid: 'u1', name: 'أحمد'),
              )),
          chosenAddressProvider.overrideWith((ref) async => chosen),
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
            child: PreorderCheckoutScreen(
              meal: dish,
              quantity: 2,
              onPlaced: (order) => placed = order,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(PreorderCheckoutScreen.reserveKey))
          .onPressed !=
      null;

  for (final option in [DeliveryOption.pickup, DeliveryOption.sellerArrangement]) {
    testWidgets('$option omits a selected address from the reservation',
        (tester) async {
      await pump(tester,
          dish: meal(deliveryOption: option), chosen: address('z1'));

      await tester.tap(find.byKey(PreorderCheckoutScreen.reserveKey));
      await tester.pumpAndSettle();

      expect(placed, isNotNull);
      expect(orders.drafts.single.addressId, isNull,
          reason: 'a remembered address must not buy an unrequested delivery');
    });
  }

  testWidgets('a zone the kitchen serves can be confirmed', (tester) async {
    await pump(tester, dish: meal(), chosen: address('z1'));

    expect(enabled(tester), isTrue);
    expect(find.byKey(PreorderCheckoutScreen.outOfRangeKey), findsNothing);
  });

  testWidgets('platform courier sends the address and quotes the clamped bill',
      (tester) async {
    // Two 90 EGP portions plus 10 EGP delivery. The stored override is only 5,
    // so reading it raw would quote 185 while the courier asks for 190.
    await pump(tester,
        dish: meal(),
        chosen: address('z1'),
        cook: kitchen.copyWith(deliveryFeeOverride: 500),
        config: LuqmaConfig.from(MapConfigSource({'delivery_fee_min': 1000})));

    expect(
        find.descendant(
            of: find.byKey(PreorderCheckoutScreen.totalKey),
            matching: find.text('190 ج')),
        findsOneWidget);
    final deliveryRow = find.ancestor(
        of: find.text('التوصيل — وسط البلد'), matching: find.byType(Row));
    expect(find.descendant(of: deliveryRow, matching: find.text('10 ج')),
        findsOneWidget);
    final subtotalRow = find.ancestor(
        of: find.text('الأصناف'), matching: find.byType(Row));
    expect(find.descendant(of: subtotalRow, matching: find.text('180 ج')),
        findsOneWidget);

    await tester.tap(find.byKey(PreorderCheckoutScreen.reserveKey));
    await tester.pumpAndSettle();
    expect(placed, isNotNull);
    expect(orders.drafts.single.addressId, 'a1');
  });

  testWidgets('a zone it does not serve is refused on this screen, not later',
      (tester) async {
    await pump(tester, dish: meal(), chosen: address('z9'));

    expect(enabled(tester), isFalse,
        reason: 'having an address is not the same as being somewhere it delivers');
    expect(find.byKey(PreorderCheckoutScreen.outOfRangeKey), findsOneWidget,
        reason: 'and the customer is told which kitchen and which zone');
  });

  testWidgets('with no address at all it still asks for one', (tester) async {
    await pump(tester, dish: meal(), chosen: null);

    expect(enabled(tester), isFalse);
    expect(find.byKey(PreorderCheckoutScreen.needsAddressKey), findsOneWidget);
    expect(find.byKey(PreorderCheckoutScreen.outOfRangeKey), findsNothing,
        reason: 'no address is a different sentence from the wrong address');
  });

  testWidgets('a meal collected in person asks for no address and no zone',
      (tester) async {
    await pump(tester,
        dish: meal(deliveryOption: DeliveryOption.pickup), chosen: null);

    expect(enabled(tester), isTrue,
        reason: 'there is nowhere to deliver to, so there is nothing to be out of '
            'range of');
    expect(find.byKey(PreorderCheckoutScreen.outOfRangeKey), findsNothing);
    expect(find.byKey(PreorderCheckoutScreen.needsAddressKey), findsNothing);
    await tester.tap(find.byKey(PreorderCheckoutScreen.reserveKey));
    await tester.pumpAndSettle();
    expect(placed, isNotNull);
    expect(orders.drafts.single.addressId, isNull);
  });
}
