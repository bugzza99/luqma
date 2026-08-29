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

  Future<void> pump(
    WidgetTester tester, {
    required DailyMeal dish,
    Address? chosen,
  }) async {
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
              .overrideWithValue(FakeMerchantRepository(seed: const [kitchen])),
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
              onPlaced: (_) {},
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

  testWidgets('a zone the kitchen serves can be confirmed', (tester) async {
    await pump(tester, dish: meal(), chosen: address('z1'));

    expect(enabled(tester), isTrue);
    expect(find.byKey(PreorderCheckoutScreen.outOfRangeKey), findsNothing);
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
  });
}
