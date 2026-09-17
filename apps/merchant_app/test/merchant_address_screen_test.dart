import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/shop/merchant_address_screen.dart';

void main() {
  const zone = Zone(id: 'z1', cityId: 'edku', name: 'وسط البلد', defaultDeliveryFee: 1000);
  const landmark = Landmark(
    id: 'l1',
    cityId: 'edku',
    zoneId: 'z1',
    name: 'مسجد المحطة',
    lat: 31.3,
    lng: 30.3,
  );

  const shop = Merchant(
    id: 'm1',
    cityId: 'edku',
    type: MerchantType.restaurant,
    name: 'مطعم الشاطئ',
    zoneId: 'z1',
    phone: '01000000000',
    status: MerchantStatus.approved,
    landmarkId: 'l1',
    landmarkName: 'مسجد المحطة',
    street: 'شارع الجمهورية',
    lat: 31.3,
    lng: 30.3,
  );

  late FakeMerchantRepository merchantRepo;
  late FakeGeographyRepository geoRepo;

  Future<void> pumpScreen(
    WidgetTester tester, {
    Merchant? initialShop = shop,
    Failure? failure,
    Failure? saveFailure,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    merchantRepo = FakeMerchantRepository(
      seed: initialShop != null ? [initialShop] : const [],
      failure: failure,
      saveFailure: saveFailure,
    );
    geoRepo = FakeGeographyRepository(
      zones: const [zone],
      landmarks: const [landmark],
    );

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
          merchantRepositoryProvider.overrideWithValue(merchantRepo),
          geographyRepositoryProvider.overrideWithValue(geoRepo),
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
            child: MerchantAddressScreen(merchantId: 'm1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders address form pre-filled with shop address and locked zone', (tester) async {
    await pumpScreen(tester);

    expect(find.byType(AddressPicker), findsOneWidget);
    expect(find.text('وسط البلد'), findsOneWidget);
    expect(find.text('شارع الجمهورية'), findsOneWidget);
  });

  testWidgets('saving address writes landmark, street, and coordinates to merchant repository', (tester) async {
    await pumpScreen(
      tester,
      initialShop: shop.copyWith(
        landmarkId: null,
        landmarkName: null,
        street: null,
        lat: null,
        lng: null,
      ),
    );

    // Pick landmark chip
    await tester.tap(find.text('مسجد المحطة'));
    await tester.pumpAndSettle();

    // Type street
    await tester.enterText(
      find.byKey(AddressPicker.streetKey),
      'شارع البحر الجديد',
    );
    await tester.pumpAndSettle();

    // Tap submit button
    await tester.tap(find.byKey(AddressPicker.saveKey));
    await tester.pumpAndSettle();

    final saved = (await merchantRepo.getMerchant('m1')).valueOrNull;
    expect(saved?.landmarkId, 'l1');
    expect(saved?.landmarkName, 'مسجد المحطة');
    expect(saved?.street, 'شارع البحر الجديد');
    expect(saved?.lat, 31.3);
    expect(saved?.lng, 30.3);
  });

  testWidgets('save failure displays error banner', (tester) async {
    await pumpScreen(
      tester,
      saveFailure: const OfflineFailure(),
    );

    await tester.tap(find.byKey(AddressPicker.saveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(MerchantAddressScreen.errorKey), findsOneWidget);
  });
}
