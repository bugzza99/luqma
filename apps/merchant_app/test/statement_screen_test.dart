import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/shop/shop_screen.dart';
import 'package:merchant_app/src/shop/statement_screen.dart';

/// كشف الحساب — the merchant's own copy of what the platform took.
///
/// It exists in this app rather than only in AdminApp because the merchant is the person
/// whose money it is, and a figure somebody cannot check is a figure they will dispute
/// over a phone. Every assertion below is about a sentence a merchant reads before that
/// call happens.
void main() {
  const alwaysOpen = [
    OpeningWindow(weekday: 1, openMinute: 0, closeMinute: 1440),
  ];

  Merchant shop({
    RevenueModel model = RevenueModel.commission,
    int value = 1000,
    int wallet = 0,
    int owed = 0,
  }) =>
      Merchant(
        id: 'm1',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'مطعم الشاطئ',
        zoneId: 'z1',
        phone: '01000000000',
        status: MerchantStatus.approved,
        openingHours: alwaysOpen,
        revenueModel: model,
        revenueValue: value,
        walletBalance: wallet,
        commissionOwed: owed,
      );

  OrderSettlement settlement({
    String orderId = 'o1',
    int basis = 20000,
    int amount = 2000,
    int platformOwes = 0,
    DateTime? reversedAt,
  }) =>
      OrderSettlement(
        orderId: orderId,
        merchantId: 'm1',
        model: RevenueModel.commission,
        basis: basis,
        amount: amount,
        platformOwes: platformOwes,
        settledAt: DateTime(2026, 8, 24),
        reversedAt: reversedAt,
      );

  Future<void> pump(
    WidgetTester tester, {
    List<OrderSettlement> seed = const [],
    Merchant? merchant,
    Failure? failure,
  }) async {
    // A phone, not the runner's 800x600 default — which is wider than it is tall and
    // unlike any device this ships on.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settlementRepositoryProvider.overrideWithValue(
            FakeSettlementRepository(seed: seed, failure: failure),
          ),
          merchantRepositoryProvider.overrideWithValue(
            FakeMerchantRepository(seed: [merchant ?? shop()]),
          ),
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
            child: StatementScreen(merchantId: 'm1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the rows', () {
    testWidgets('a charge is shown with what it was charged on', (tester) async {
      await pump(tester, seed: [settlement()]);

      expect(find.byKey(StatementScreen.rowKey('o1')), findsOneWidget);
      // 200 EGP of food, 20 EGP taken. Both, because "why is it this much" is the only
      // question this screen exists to answer.
      expect(find.textContaining('200'), findsWidgets);
      expect(find.textContaining('20 '), findsWidgets);
    });

    // A merchant who saw a charge and then finds it gone has no way to tell whether it
    // was returned or whether the screen is wrong.
    testWidgets('a charge taken back stays, marked', (tester) async {
      await pump(tester, seed: [settlement(reversedAt: DateTime(2026, 8, 25))]);

      expect(find.byKey(StatementScreen.rowKey('o1')), findsOneWidget);
      expect(find.byKey(StatementScreen.reversedKey('o1')), findsOneWidget);
    });

    testWidgets('nothing delivered yet is a sentence, not a blank page',
        (tester) async {
      await pump(tester);

      expect(find.byKey(StatementScreen.emptyKey), findsOneWidget);
    });

    // `LuqmaErrorView` takes an `onRetry`, and this screen is one somebody opens on a
    // weak connection to check a figure they are about to argue about.
    testWidgets('a failed read offers a way out', (tester) async {
      await pump(tester, failure: const OfflineFailure());

      expect(find.byType(LuqmaErrorView), findsOneWidget);
    });
  });

  group('the summary', () {
    testWidgets('counts only what still stands', (tester) async {
      await pump(tester, seed: [
        settlement(orderId: 'o1', amount: 2000),
        settlement(orderId: 'o2', amount: 3000),
        settlement(orderId: 'o3', amount: 9000, reversedAt: DateTime(2026, 8, 25)),
      ]);

      // 50 EGP, not 140: a reversed charge counts for nothing in either direction.
      expect(find.textContaining('50 '), findsWidgets);
    });

    testWidgets('a commission merchant sees what they owe', (tester) async {
      await pump(
        tester,
        merchant: shop(owed: 47500),
        seed: [settlement()],
      );

      expect(find.byKey(StatementScreen.owedKey), findsOneWidget);
      expect(find.textContaining('475'), findsWidgets);
    });

    // Under prepaid nothing is owed — it was paid in advance — so a line reading
    // "المستحق" would be a debt the merchant does not have.
    testWidgets('a prepaid merchant does not', (tester) async {
      await pump(
        tester,
        merchant: shop(model: RevenueModel.prepaid, value: 500, wallet: 3000),
        seed: [settlement(amount: 500)],
      );

      expect(find.byKey(StatementScreen.owedKey), findsNothing);
      expect(find.textContaining('اتخصم من الرصيد'), findsOneWidget);
    });

    // The direction a merchant asks about first: a discount the platform funded is cash
    // that never reached their till.
    testWidgets('what the platform owes back is shown when there is any',
        (tester) async {
      await pump(tester, seed: [settlement(platformOwes: 3000)]);

      expect(find.byKey(StatementScreen.platformOwesKey), findsOneWidget);
    });

    testWidgets('and not drawn at all when there is none', (tester) async {
      await pump(tester, seed: [settlement()]);

      expect(find.byKey(StatementScreen.platformOwesKey), findsNothing);
    });
  });

  group('getting here', () {
    Future<void> pumpShop(WidgetTester tester, Merchant merchant) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

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
            merchantRepositoryProvider
                .overrideWithValue(FakeMerchantRepository(seed: [merchant])),
            settlementRepositoryProvider
                .overrideWithValue(FakeSettlementRepository()),
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
              child: ShopScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the billing card offers it under commission', (tester) async {
      await pumpShop(tester, shop());

      expect(find.byKey(ShopScreen.statementKey), findsOneWidget);
    });

    // Under a subscription nothing is taken per order, so the statement is a page of
    // zeroes — and a screen that says nothing every time is one somebody stops believing
    // when it finally has something to say.
    testWidgets('and not under a subscription', (tester) async {
      await pumpShop(tester, shop(model: RevenueModel.subscription, value: 0));

      expect(find.byKey(ShopScreen.statementKey), findsNothing);
    });

    testWidgets('and tapping it opens the statement', (tester) async {
      await pumpShop(tester, shop());

      await tester.tap(find.byKey(ShopScreen.statementKey));
      await tester.pumpAndSettle();

      expect(find.byType(StatementScreen), findsOneWidget);
    });
  });
}
