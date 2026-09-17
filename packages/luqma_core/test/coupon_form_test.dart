import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The coupon form both apps share: what a shop owner and an admin type to make a code.
void main() {
  group('couponOffer', () {
    test('says a capped percentage in words', () {
      const c = Coupon(
        id: 'c',
        code: 'EID',
        cityId: 'edku',
        type: CouponType.percentage,
        value: 1500,
        maxDiscount: 3000,
      );
      expect(couponOffer(c, (p) => '${p ~/ 100} ج'), '15% بحد أقصى 30 ج');
    });

    test('says a fixed amount and free delivery', () {
      const fixed = Coupon(
        id: 'c',
        code: 'A',
        cityId: 'edku',
        type: CouponType.fixedAmount,
        value: 2000,
      );
      const free = Coupon(
        id: 'd',
        code: 'B',
        cityId: 'edku',
        type: CouponType.freeDelivery,
        value: 0,
      );
      expect(couponOffer(fixed, (p) => '${p ~/ 100} ج'), 'خصم 20 ج');
      expect(couponOffer(free, (p) => '${p ~/ 100} ج'), 'توصيل مجاني');
    });

    test('a fractional percentage keeps its decimals', () {
      const c = Coupon(
        id: 'c',
        code: 'X',
        cityId: 'edku',
        type: CouponType.percentage,
        value: 1250,
        maxDiscount: 1000,
      );
      expect(couponOffer(c, (p) => '${p ~/ 100} ج'), '12.5% بحد أقصى 10 ج');
    });
  });

  group('CouponForm', () {
    Future<Coupon?> pump(
      WidgetTester tester, {
      bool adminExtras = false,
      List<Merchant> shops = const [],
      Failure? saveFailure,
    }) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Coupon? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: CouponForm(
                  cityId: 'edku',
                  merchantId: adminExtras ? null : 'm1',
                  adminExtras: adminExtras,
                  shops: shops,
                  onSave: (draft) async {
                    saved = draft;
                    return saveFailure;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return saved;
    }

    Future<void> type(WidgetTester tester, Key key, String text) async {
      await tester.enterText(find.byKey(key), text);
      await tester.pump();
    }

    testWidgets('refuses a percentage without a cap', (tester) async {
      await pump(tester);
      await type(tester, CouponForm.codeKey, 'eid15');
      await type(tester, CouponForm.valueKey, '15');
      await tester.tap(find.byKey(CouponForm.saveKey));
      await tester.pumpAndSettle();

      expect(find.text('النسبة لازم يكون ليها أقصى خصم'), findsOneWidget);
    });

    testWidgets(
      'a shop coupon reaches the save with the shop, the city and funded by the shop',
      (tester) async {
        Coupon? saved;
        tester.view.physicalSize = const Size(400, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: LuqmaTheme.light,
            localizationsDelegates: LuqmaStrings.localizationsDelegates,
            supportedLocales: LuqmaStrings.supportedLocales,
            locale: const Locale('ar'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: CouponForm(
                  cityId: 'edku',
                  merchantId: 'm1',
                  onSave: (draft) async {
                    saved = draft;
                    return null;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await type(tester, CouponForm.codeKey, 'eid١٥');
        await type(tester, CouponForm.valueKey, '15');
        await type(tester, CouponForm.maxDiscountKey, '30');
        await type(tester, CouponForm.minOrderKey, '100');
        await type(tester, CouponForm.totalLimitKey, '50');
        await tester.tap(find.byKey(CouponForm.saveKey));
        await tester.pumpAndSettle();

        expect(saved, isNotNull);
        expect(saved!.code, 'EID15');
        expect(saved!.type, CouponType.percentage);
        expect(saved!.value, 1500);
        expect(saved!.maxDiscount, 3000);
        expect(saved!.minOrder, 10000);
        expect(saved!.totalLimit, 50);
        expect(saved!.perUserLimit, 0);
        expect(saved!.merchantId, 'm1');
        expect(saved!.cityId, 'edku');
        expect(saved!.fundedBy, CouponFunder.merchant);
      },
    );

    testWidgets('a duplicate code is said in words', (tester) async {
      await pump(tester, saveFailure: const ConflictFailure());
      await tester.tap(find.byKey(CouponForm.typeFixedKey));
      await tester.pumpAndSettle();
      await type(tester, CouponForm.codeKey, 'SAME');
      await type(tester, CouponForm.valueKey, '20');
      await tester.tap(find.byKey(CouponForm.saveKey));
      await tester.pumpAndSettle();

      expect(find.text('الكود ده مستخدم قبل كده'), findsOneWidget);
    });

    testWidgets('the admin extras are absent for a shop', (tester) async {
      await pump(tester);
      expect(find.byKey(CouponForm.fundedByKey), findsNothing);
      expect(find.byKey(CouponForm.scopeKey), findsNothing);
    });

    testWidgets(
      'an admin platform coupon has no shop and is paid by the platform',
      (tester) async {
        Coupon? saved;
        tester.view.physicalSize = const Size(400, 1800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: LuqmaTheme.light,
            localizationsDelegates: LuqmaStrings.localizationsDelegates,
            supportedLocales: LuqmaStrings.supportedLocales,
            locale: const Locale('ar'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: CouponForm(
                  cityId: 'edku',
                  adminExtras: true,
                  onSave: (draft) async {
                    saved = draft;
                    return null;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(CouponForm.fundedByKey), findsOneWidget);
        await tester.tap(find.byKey(CouponForm.typeFreeDeliveryKey));
        await tester.pumpAndSettle();
        await type(tester, CouponForm.codeKey, 'FREE');
        await tester.tap(find.byKey(CouponForm.saveKey));
        await tester.pumpAndSettle();

        expect(saved, isNotNull);
        expect(saved!.merchantId, isNull);
        expect(saved!.type, CouponType.freeDelivery);
        expect(saved!.fundedBy, CouponFunder.platform);
      },
    );
    testWidgets('a count too large for the column is refused in words', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(CouponForm.typeFreeDeliveryKey));
      await tester.pumpAndSettle();
      await type(tester, CouponForm.codeKey, 'BIG');
      await type(tester, CouponForm.totalLimitKey, '2147483648');
      await tester.tap(find.byKey(CouponForm.saveKey));
      await tester.pumpAndSettle();

      expect(find.text('عدد المرات لازم يكون رقم صحيح'), findsOneWidget);
    });
  });
}
