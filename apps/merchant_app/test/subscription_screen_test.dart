import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/shop/subscription_screen.dart';

/// الاشتراك — a shop asking for a plan.
///
/// Built 2026-09-17: plans had prices and an admin could record a payment, but no shop could
/// ask for one, so nobody was ever subscribed.
void main() {
  final now = DateTime(2026, 9, 17, 12);
  const basic = Plan(id: 'basic', name: 'أساسية', priceMonthly: 100000);
  const premium = Plan(id: 'premium', name: 'مميزة', priceMonthly: 150000, sortOrder: 1);

  late FakeSubscriptionRequestRepository requests;

  Future<void> pump(
    WidgetTester tester, {
    String? planId,
    DateTime? planExpiresAt,
    List<SubscriptionRequest> seed = const [],
  }) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    requests = FakeSubscriptionRequestRepository(
      plans: const [basic, premium],
      merchantId: 'm1',
      seed: seed,
      clock: () => now,
    );
    final shop = Merchant(
      id: 'm1',
      cityId: 'edku',
      type: MerchantType.restaurant,
      name: 'مطعم البحر',
      zoneId: 'z1',
      phone: '01000000000',
      revenueModel: RevenueModel.commission,
      revenueValue: 1000,
      planId: planId,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          subscriptionRequestRepositoryProvider.overrideWithValue(requests),
          billingRepositoryProvider.overrideWithValue(
            FakeBillingRepository(
              seedPlans: const [basic, premium],
              seedSubscriptions: [
                if (planId != null && planExpiresAt != null)
                  Subscription(
                    id: 's1',
                    merchantId: 'm1',
                    planId: planId,
                    amount: 100000,
                    startedAt: planExpiresAt.subtract(const Duration(days: 30)),
                    expiresAt: planExpiresAt,
                    recordedBy: 'admin-1',
                  ),
              ],
            ),
          ),
          merchantRepositoryProvider.overrideWithValue(FakeMerchantRepository(seed: [shop])),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: SubscriptionScreen(merchantId: 'm1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a shop with no plan is told its commission and offered the plans', (tester) async {
    await pump(tester);

    expect(find.text('مش مشترك في باقة'), findsOneWidget);
    expect(find.textContaining('10%'), findsOneWidget);
    expect(find.byKey(SubscriptionScreen.planKey('basic')), findsOneWidget);
    expect(find.byKey(SubscriptionScreen.planKey('premium')), findsOneWidget);
  });

  testWidgets('asking for three months by transfer sends that request', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(SubscriptionScreen.planKey('premium')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(SubscriptionScreen.monthsKey(3)));
    await tester.tap(find.byKey(SubscriptionScreen.monthsKey(3)));
    await tester.pumpAndSettle();
    expect(find.textContaining('4500 ج'), findsOneWidget);

    await tester.ensureVisible(find.byKey(SubscriptionScreen.transferKey));
    await tester.tap(find.byKey(SubscriptionScreen.transferKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(SubscriptionScreen.referenceKey));
    await tester.enterText(find.byKey(SubscriptionScreen.referenceKey), 'VF-778');
    await tester.ensureVisible(find.byKey(SubscriptionScreen.sendKey));
    await tester.tap(find.byKey(SubscriptionScreen.sendKey));
    await tester.pumpAndSettle();

    final sent = requests.all.single;
    expect(sent.planId, 'premium');
    expect(sent.months, 3);
    expect(sent.paymentMethod, SubscriptionPaymentMethod.transfer);
    expect(sent.transferReference, 'VF-778');
    expect(find.text('طلبك مستني تأكيد الإدارة'), findsOneWidget);
  });

  testWidgets('a pending request can be cancelled, and no second one is offered', (tester) async {
    await pump(tester, seed: [
      SubscriptionRequest(
        id: 'r1',
        merchantId: 'm1',
        planId: 'basic',
        months: 1,
        quotedAmount: 100000,
        paymentMethod: SubscriptionPaymentMethod.cash,
        status: SubscriptionRequestStatus.pending,
        createdAt: now,
      ),
    ]);

    expect(find.byKey(SubscriptionScreen.planKey('basic')), findsNothing);
    await tester.tap(find.byKey(SubscriptionScreen.cancelKey));
    await tester.pumpAndSettle();

    expect(requests.all.single.status, SubscriptionRequestStatus.cancelled);
    expect(find.byKey(SubscriptionScreen.planKey('basic')), findsOneWidget);
  });

  testWidgets('an active plan says there is no commission until its end', (tester) async {
    await pump(tester, planId: 'basic', planExpiresAt: DateTime(2026, 10, 17));

    expect(find.text('باقة أساسية شغالة'), findsOneWidget);
    expect(find.textContaining('17/10/2026'), findsOneWidget);
    expect(find.textContaining('مفيش عمولة'), findsWidgets);
  });

  testWidgets('a rejected request shows why', (tester) async {
    await pump(tester, seed: [
      SubscriptionRequest(
        id: 'r1',
        merchantId: 'm1',
        planId: 'basic',
        months: 1,
        quotedAmount: 100000,
        paymentMethod: SubscriptionPaymentMethod.transfer,
        status: SubscriptionRequestStatus.rejected,
        rejectReason: 'التحويل موصلش',
        createdAt: now,
      ),
    ]);

    expect(find.textContaining('التحويل موصلش'), findsOneWidget);
  });
}
