import 'package:admin_app/src/coupons/coupons_screen.dart';
import 'package:admin_app/src/merchants/merchants_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// الكوبونات — every code in the city, the platform's and every shop's.
///
/// Built 2026-09-17: the schema could hold coupons since Phase 1 and nothing in either app
/// could make one, so no discount code had ever existed.
void main() {
  const shop = Merchant(
    id: 'm1',
    cityId: 'edku',
    type: MerchantType.restaurant,
    name: 'مطعم البحر',
    phone: '01000000000',
    zoneId: 'z1',
    status: MerchantStatus.approved,
  );

  late FakeCouponRepository coupons;

  Future<void> pump(WidgetTester tester, {List<Coupon> seed = const []}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    coupons = FakeCouponRepository(seed: seed);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          couponRepositoryProvider.overrideWithValue(coupons),
          allMerchantsProvider.overrideWith((ref) => Stream.value(const [shop])),
          currentCityProvider.overrideWithValue('edku'),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: CouponsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with none yet, it says so', (tester) async {
    await pump(tester);
    expect(find.byKey(CouponsScreen.emptyKey), findsOneWidget);
  });

  testWidgets('lists the platform coupons and the shops\' by owner', (tester) async {
    await pump(tester, seed: const [
      Coupon(
        id: 'a',
        code: 'EID15',
        cityId: 'edku',
        type: CouponType.percentage,
        value: 1500,
        maxDiscount: 3000,
        fundedBy: CouponFunder.platform,
      ),
      Coupon(
        id: 'b',
        code: 'BAHR20',
        cityId: 'edku',
        type: CouponType.fixedAmount,
        value: 2000,
        merchantId: 'm1',
        usedCount: 3,
        totalLimit: 50,
      ),
    ]);

    expect(find.byType(CouponTile), findsNWidgets(2));
    expect(find.text('المنصة'), findsOneWidget);
    expect(find.text('مطعم البحر'), findsOneWidget);
    expect(find.textContaining('اتستخدم 3 من 50'), findsOneWidget);
  });

  testWidgets('the switch pauses a coupon', (tester) async {
    await pump(tester, seed: const [
      Coupon(
        id: 'a',
        code: 'EID15',
        cityId: 'edku',
        type: CouponType.freeDelivery,
        value: 0,
        fundedBy: CouponFunder.platform,
      ),
    ]);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    final list = (await coupons.listAll()).valueOrNull!;
    expect(list.single.isActive, isFalse);
  });

  testWidgets('a new platform coupon is made from the form', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(CouponsScreen.addKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CouponForm.typeFreeDeliveryKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(CouponForm.codeKey), 'free');
    await tester.ensureVisible(find.byKey(CouponForm.saveKey));
    await tester.tap(find.byKey(CouponForm.saveKey));
    await tester.pumpAndSettle();

    final list = (await coupons.listAll()).valueOrNull!;
    expect(list.single.code, 'FREE');
    expect(list.single.fundedBy, CouponFunder.platform);
    expect(find.byType(CouponTile), findsOneWidget);
  });
}
