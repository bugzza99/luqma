import 'package:admin_app/src/plans/plans_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The plan price and limits editor.
void main() {
  Plan plan({String id = 'basic', int priceMonthly = 25000}) => Plan(
        id: id,
        name: 'أساسية',
        priceMonthly: priceMonthly,
        sortOrder: 1,
      );

  late FakeBillingRepository billing;

  Future<void> pump(WidgetTester tester, {List<Plan> seed = const []}) async {
    billing = FakeBillingRepository(seedPlans: seed);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [billingRepositoryProvider.overrideWithValue(billing)],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: PlansEditorScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows a plan with its price in pounds', (tester) async {
    await pump(tester, seed: [plan(priceMonthly: 25000)]);

    expect(
      tester.widget<TextField>(find.byKey(PlansEditorScreen.priceKey('basic'))).controller!.text,
      '250',
    );
  });

  testWidgets('editing a price saves it in piastres through the repository',
      (tester) async {
    await pump(tester, seed: [plan(priceMonthly: 25000)]);

    await tester.enterText(find.byKey(PlansEditorScreen.priceKey('basic')), '300');
    await tester.tap(find.byKey(PlansEditorScreen.saveKey('basic')));
    await tester.pumpAndSettle();

    final saved = (await billing.plans(includeInactive: true)).valueOrNull!.single;
    expect(saved.priceMonthly, 30000);
    expect(billing.audit.last['action'], 'savePlan');
  });

  testWidgets('a price the reader cannot read is refused, not saved', (tester) async {
    await pump(tester, seed: [plan()]);

    await tester.enterText(find.byKey(PlansEditorScreen.priceKey('basic')), '1,5');
    await tester.tap(find.byKey(PlansEditorScreen.saveKey('basic')));
    await tester.pumpAndSettle();

    final saved = (await billing.plans(includeInactive: true)).valueOrNull!.single;
    expect(saved.priceMonthly, 25000, reason: 'nothing was written');
  });

  testWidgets('an empty list of plans says so rather than showing nothing',
      (tester) async {
    await pump(tester, seed: []);

    expect(find.byKey(PlansEditorScreen.emptyKey), findsOneWidget);
    expect(find.text('مفيش خطط.'), findsOneWidget);
  });

  // The restyle listed a plan's feature flags as benefits. None of them is enforced by the
  // product, so the card no longer promises them — a list of benefits the app does not
  // deliver, on the screen the owner reads before selling a plan, is how a merchant gets
  // promised them.
  testWidgets('shows a plan without promising benefits the app does not deliver', (tester) async {
    await pump(
      tester,
      seed: [
        Plan(
          id: 'free',
          name: 'مجانية',
          priceMonthly: 0,
          features: const PlanFeatures(
            maxItems: 10,
            verifiedBadge: true,
            analytics: true,
          ),
          isActive: false,
        ),
      ],
    );

    expect(find.text('مجاني'), findsWidgets);
    expect(find.text('معطلة'), findsWidgets);
    expect(find.text('حتى 10 صنف'), findsNothing);
    expect(find.text('علامة توثيق للمحل'), findsNothing);
    expect(find.text('إحصائيات كاملة للمبيعات'), findsNothing);
  });

  testWidgets('renders cleanly on a phone screen without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pump(tester, seed: [plan(priceMonthly: 25000)]);

    expect(find.byKey(PlansEditorScreen.priceKey('basic')), findsOneWidget);
    expect(find.byKey(PlansEditorScreen.saveKey('basic')), findsOneWidget);
  });

  // 2026-09-17: the plan's benefits are enforced now, so the owner sets them here.
  testWidgets('sets what a plan gives: showing first, the badge, and the monthly counts',
      (tester) async {
    await pump(tester, seed: [
      const Plan(id: 'premium', name: 'مميزة', priceMonthly: 150000),
    ]);

    await tester.ensureVisible(find.byKey(PlansEditorScreen.boostKey('premium')));
    await tester.tap(find.byKey(PlansEditorScreen.boostKey('premium')));
    await tester.tap(find.byKey(PlansEditorScreen.verifiedKey('premium')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PlansEditorScreen.bannersKey('premium')), '2');
    await tester.enterText(find.byKey(PlansEditorScreen.pushesKey('premium')), '1');
    await tester.ensureVisible(find.byKey(PlansEditorScreen.saveKey('premium')));
    await tester.tap(find.byKey(PlansEditorScreen.saveKey('premium')));
    await tester.pumpAndSettle();

    final saved = (await billing.plans(includeInactive: true)).valueOrNull!.single;
    expect(saved.features.boostRank, isTrue);
    expect(saved.features.verifiedBadge, isTrue);
    expect(saved.features.homeBannerSlots, 2);
    expect(saved.features.monthlyPromotionCount, 1);
  });
}
