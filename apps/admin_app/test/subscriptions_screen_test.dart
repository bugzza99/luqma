import 'package:admin_app/src/subscriptions/subscriptions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// الاشتراكات — who is on which plan, and the shops asking for one.
///
/// Built 2026-09-17: the owner could not tell which shop was subscribed to what, and no shop
/// could ask.
void main() {
  final now = DateTime(2026, 9, 17, 12);
  const basic = Plan(id: 'basic', name: 'أساسية', priceMonthly: 100000);

  late FakeSubscriptionRequestRepository requests;

  SubscriptionRequest pending(String id, String merchantId) => SubscriptionRequest(
        id: id,
        merchantId: merchantId,
        planId: 'basic',
        months: 3,
        quotedAmount: 300000,
        paymentMethod: SubscriptionPaymentMethod.transfer,
        transferReference: 'VF-1',
        status: SubscriptionRequestStatus.pending,
        createdAt: now,
      );

  Future<void> pump(
    WidgetTester tester, {
    List<SubscriptionRequest> seed = const [],
    List<SubscriptionOverviewRow> rows = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    requests = FakeSubscriptionRequestRepository(
      seed: seed,
      overviewRows: rows,
      clock: () => now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          subscriptionRequestRepositoryProvider.overrideWithValue(requests),
          billingRepositoryProvider.overrideWithValue(
            FakeBillingRepository(seedPlans: const [basic]),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: SubscriptionsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const rows = [
    SubscriptionOverviewRow(merchantId: 'm1', merchantName: 'مطعم البحر'),
    SubscriptionOverviewRow(merchantId: 'm2', merchantName: 'بيتزا الميدان'),
  ];

  testWidgets('a pending request shows the shop, the plan, the length, the amount and how it pays',
      (tester) async {
    await pump(tester, seed: [pending('r1', 'm1')], rows: rows);

    expect(find.text('مطعم البحر'), findsWidgets);
    expect(find.textContaining('أساسية'), findsWidgets);
    expect(find.textContaining('3 شهور'), findsOneWidget);
    expect(find.textContaining('3000 ج'), findsOneWidget);
    expect(find.textContaining('VF-1'), findsOneWidget);
  });

  testWidgets('activating with a discount sends the typed amount', (tester) async {
    await pump(tester, seed: [pending('r1', 'm1')], rows: rows);

    await tester.tap(find.byKey(SubscriptionsScreen.activateKey('r1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SubscriptionsScreen.amountKey), '2500');
    await tester.tap(find.byKey(SubscriptionsScreen.confirmKey));
    await tester.pumpAndSettle();

    expect(requests.activations.single, ('r1', 250000));
    expect(find.byKey(SubscriptionsScreen.activateKey('r1')), findsNothing);
  });

  testWidgets('rejecting needs a reason', (tester) async {
    await pump(tester, seed: [pending('r1', 'm1')], rows: rows);

    await tester.tap(find.byKey(SubscriptionsScreen.rejectKey('r1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(SubscriptionsScreen.reasonKey), 'التحويل موصلش');
    await tester.tap(find.byKey(SubscriptionsScreen.confirmKey));
    await tester.pumpAndSettle();

    expect(requests.all.single.status, SubscriptionRequestStatus.rejected);
    expect(requests.all.single.rejectReason, 'التحويل موصلش');
  });

  testWidgets('the shops tab says who is on what, and filters', (tester) async {
    await pump(tester, rows: [
      SubscriptionOverviewRow(
        merchantId: 'm1',
        merchantName: 'مطعم البحر',
        planId: 'basic',
        planName: 'أساسية',
        planExpiresAt: DateTime(2026, 11, 1),
      ),
      SubscriptionOverviewRow(
        merchantId: 'm2',
        merchantName: 'بيتزا الميدان',
        planId: 'basic',
        planName: 'أساسية',
        planExpiresAt: DateTime(2026, 9, 19),
      ),
      const SubscriptionOverviewRow(merchantId: 'm3', merchantName: 'كشري البلد'),
    ]);

    await tester.tap(find.byKey(SubscriptionsScreen.shopsTabKey));
    await tester.pumpAndSettle();

    expect(find.text('مطعم البحر'), findsOneWidget);
    expect(find.textContaining('لحد 1/11/2026'), findsOneWidget);
    expect(find.text('من غير باقة'), findsWidgets);

    await tester.tap(find.byKey(SubscriptionsScreen.filterKey(PlanStanding.endingSoon)));
    await tester.pumpAndSettle();
    expect(find.text('بيتزا الميدان'), findsOneWidget);
    expect(find.text('مطعم البحر'), findsNothing);
    expect(find.text('كشري البلد'), findsNothing);
  });

  // Found in review: the prefill dropped piastres, so confirming an unchanged 150.50 quote
  // sent a discount; and the meal-price cap refused a year of a plan.
  testWidgets('an unchanged quote with piastres activates at the quote, and a year is allowed',
      (tester) async {
    await pump(tester, seed: [
      SubscriptionRequest(
        id: 'r1',
        merchantId: 'm1',
        planId: 'basic',
        months: 1,
        quotedAmount: 15050,
        paymentMethod: SubscriptionPaymentMethod.cash,
        status: SubscriptionRequestStatus.pending,
        createdAt: now,
      ),
      SubscriptionRequest(
        id: 'r2',
        merchantId: 'm2',
        planId: 'basic',
        months: 12,
        quotedAmount: 1200000,
        paymentMethod: SubscriptionPaymentMethod.cash,
        status: SubscriptionRequestStatus.pending,
        createdAt: now,
      ),
    ], rows: rows);

    await tester.tap(find.byKey(SubscriptionsScreen.activateKey('r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SubscriptionsScreen.confirmKey));
    await tester.pumpAndSettle();
    expect(requests.activations.last, ('r1', null));

    await tester.tap(find.byKey(SubscriptionsScreen.activateKey('r2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SubscriptionsScreen.confirmKey));
    await tester.pumpAndSettle();
    expect(requests.activations.last, ('r2', null));
  });
}
