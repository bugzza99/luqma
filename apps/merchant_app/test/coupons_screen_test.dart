import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/shop/coupons_screen.dart';

/// كوبونات الخصم — a shop's own codes, paid for by the shop, live the moment they are made.
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

    coupons = FakeCouponRepository(
      seed: seed,
      isAdmin: false,
      merchantId: 'm1',
      actingUid: 'owner-1',
      merchantCities: const {'m1': 'edku'},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [couponRepositoryProvider.overrideWithValue(coupons)],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: MerchantCouponsScreen(merchant: shop),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with none yet, it says a coupon works the moment it is made', (tester) async {
    await pump(tester);
    expect(find.byKey(MerchantCouponsScreen.emptyKey), findsOneWidget);
    expect(find.textContaining('بيشتغل على طول'), findsOneWidget);
  });

  testWidgets('a new coupon is the shop\'s, in the shop\'s city, paid by the shop', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(MerchantCouponsScreen.addKey));
    await tester.pumpAndSettle();
    expect(find.byKey(CouponForm.fundedByKey), findsNothing);

    await tester.tap(find.byKey(CouponForm.typeFixedKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(CouponForm.codeKey), 'bahr20');
    await tester.enterText(find.byKey(CouponForm.valueKey), '20');
    await tester.ensureVisible(find.byKey(CouponForm.saveKey));
    await tester.tap(find.byKey(CouponForm.saveKey));
    await tester.pumpAndSettle();

    final saved = (await coupons.listAll()).valueOrNull!.single;
    expect(saved.code, 'BAHR20');
    expect(saved.merchantId, 'm1');
    expect(saved.cityId, 'edku');
    expect(saved.fundedBy, CouponFunder.merchant);
    expect(saved.value, 2000);
    expect(find.byType(CouponTile), findsOneWidget);
  });

  testWidgets('the switch pauses a coupon', (tester) async {
    await pump(tester, seed: const [
      Coupon(
        id: 'a',
        code: 'BAHR20',
        cityId: 'edku',
        type: CouponType.fixedAmount,
        value: 2000,
        merchantId: 'm1',
      ),
    ]);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect((await coupons.listAll()).valueOrNull!.single.isActive, isFalse);
  });
}
