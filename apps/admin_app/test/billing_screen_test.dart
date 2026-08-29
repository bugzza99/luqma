import 'package:admin_app/src/billing/merchant_billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// How a merchant pays, and recording that they did.
///
/// Every number on this screen is cash somebody handed over in a shop. Nothing here is
/// inferred and nothing is undoable from the app — a mistake is corrected by recording
/// the opposite, the way a ledger works.
void main() {
  const plans = [
    Plan(id: 'free', name: 'مجانية', sortOrder: 0),
    Plan(
      id: 'basic',
      name: 'أساسية',
      priceMonthly: 25000,
      sortOrder: 1,
      features: PlanFeatures(verifiedBadge: true, analytics: true),
    ),
  ];

  Merchant merchant({
    RevenueModel model = RevenueModel.subscription,
    int value = 0,
    int wallet = 0,
    String? planId,
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
        revenueModel: model,
        revenueValue: value,
        walletBalance: wallet,
        planId: planId,
        commissionOwed: owed,
      );

  late FakeBillingRepository billing;
  late FakeMerchantRepository merchants;

  Future<void> pump(
    WidgetTester tester, {
    Merchant? seed,
    List<Subscription> subscriptions = const [],
    List<OrderSettlement> settlements = const [],
    Failure? settlementFailure,
  }) async {
    // A phone, not the runner's 800x600 default — which is wider than it is tall and
    // unlike anything this ships on. `ListView` builds lazily, so a card below the fold
    // of a window that shape is not merely off-screen: it does not exist, and every
    // assertion about it reads as "the screen does not draw this".
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final shop = seed ?? merchant();
    merchants = FakeMerchantRepository(seed: [shop]);
    billing = FakeBillingRepository(
      seedPlans: plans,
      seedSubscriptions: subscriptions,
      wallets: {'m1': shop.walletBalance},
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentIdentityProvider.overrideWith(
            (ref) => Stream.value(
              const LuqmaIdentity(uid: 'admin1', claims: {'admin': true}),
            ),
          ),
          merchantRepositoryProvider.overrideWithValue(merchants),
          billingRepositoryProvider.overrideWithValue(billing),
          settlementRepositoryProvider.overrideWithValue(
            FakeSettlementRepository(
              seed: settlements,
              failure: settlementFailure,
            ),
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
            child: MerchantBillingScreen(merchantId: 'm1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Subscription term({
    DateTime? expires,
    String planId = 'basic',
  }) =>
      Subscription(
        id: 's1',
        merchantId: 'm1',
        planId: planId,
        amount: 25000,
        startedAt: DateTime.now().subtract(const Duration(days: 5)),
        expiresAt: expires ?? DateTime.now().add(const Duration(days: 25)),
        recordedBy: 'admin1',
      );

  group('how this merchant pays', () {
    testWidgets('the three models are offered', (tester) async {
      await pump(tester);

      expect(find.byKey(MerchantBillingScreen.modelKey(RevenueModel.subscription)),
          findsOneWidget);
      expect(find.byKey(MerchantBillingScreen.modelKey(RevenueModel.commission)),
          findsOneWidget);
      expect(find.byKey(MerchantBillingScreen.modelKey(RevenueModel.prepaid)),
          findsOneWidget);
    });

    testWidgets('the current one is marked', (tester) async {
      await pump(tester, seed: merchant(model: RevenueModel.commission, value: 1000));

      expect(
        find.byKey(MerchantBillingScreen.currentModelKey(RevenueModel.commission)),
        findsOneWidget,
      );
    });

    testWidgets('switching writes it to the merchant', (tester) async {
      await pump(tester);

      await tester.tap(
        find.byKey(MerchantBillingScreen.modelKey(RevenueModel.commission)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(MerchantBillingScreen.rateKey), '12');
      await tester.tap(find.byKey(MerchantBillingScreen.saveModelKey));
      await tester.pumpAndSettle();

      final saved = (await merchants.getMerchant('m1')).valueOrNull!;
      expect(saved.revenueModel, RevenueModel.commission);
      // Twelve per cent, in basis points — the unit the engine actually works in.
      expect(saved.revenueValue, 1200);
    });

    // A subscription has no rate. Asking for one would be asking a question with no
    // right answer, and storing whatever came back would be worse.
    testWidgets('a subscription asks for no rate', (tester) async {
      await pump(tester, seed: merchant(model: RevenueModel.commission, value: 1000));

      await tester.tap(
        find.byKey(MerchantBillingScreen.modelKey(RevenueModel.subscription)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantBillingScreen.rateKey), findsNothing);
    });
  });

  group('the subscription', () {
    testWidgets('says which plan and how long is left', (tester) async {
      await pump(tester, subscriptions: [term()]);

      expect(find.byKey(MerchantBillingScreen.termKey), findsOneWidget);
      expect(find.textContaining('أساسية'), findsWidgets);
    });

    // An expired term is not the same as never having paid. The first is a conversation
    // to have; the second is a merchant who has been on Free all along.
    testWidgets('an expired one says so rather than looking unpaid', (tester) async {
      await pump(
        tester,
        subscriptions: [term(expires: DateTime.now().subtract(const Duration(days: 3)))],
      );

      expect(find.byKey(MerchantBillingScreen.expiredKey), findsOneWidget);
    });

    testWidgets('a merchant who never paid says that instead', (tester) async {
      await pump(tester);

      expect(find.byKey(MerchantBillingScreen.noTermKey), findsOneWidget);
      expect(find.byKey(MerchantBillingScreen.expiredKey), findsNothing);
    });
  });

  group('recording a payment', () {
    Future<void> record(WidgetTester tester, {String months = '1'}) async {
      await tester.tap(find.byKey(MerchantBillingScreen.recordKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantBillingScreen.planChoiceKey('basic')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(MerchantBillingScreen.monthsKey), months);
      await tester.tap(find.byKey(MerchantBillingScreen.confirmPaymentKey));
      await tester.pumpAndSettle();
    }

    testWidgets('writes a term for the plan chosen', (tester) async {
      await pump(tester);

      await record(tester);

      final saved = billing.subscriptionOf('m1');
      expect(saved?.planId, 'basic');
      expect(saved?.amount, 25000);
    });

    testWidgets('several months multiply the amount', (tester) async {
      await pump(tester);

      await record(tester, months: '3');

      expect(billing.subscriptionOf('m1')?.amount, 75000);
    });

    // Cash that moved between two people, written down by a third.
    testWidgets('names the admin who took the money', (tester) async {
      await pump(tester);

      await record(tester);

      expect(billing.audit.single['by'], 'admin1');
    });

    testWidgets('refuses zero months', (tester) async {
      await pump(tester);

      await record(tester, months: '0');

      expect(billing.audit, isEmpty);
    });
  });

  group('the prepaid wallet', () {
    testWidgets('is only shown for a merchant on prepaid', (tester) async {
      await pump(tester);
      expect(find.byKey(MerchantBillingScreen.walletKey), findsNothing);

      await pump(
        tester,
        seed: merchant(model: RevenueModel.prepaid, value: 500, wallet: 2000),
      );
      expect(find.byKey(MerchantBillingScreen.walletKey), findsOneWidget);
    });

    testWidgets('shows the balance', (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.prepaid, value: 500, wallet: 2000),
      );

      expect(find.textContaining('20 ج'), findsWidgets);
    });

    testWidgets('a top-up adds to it', (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.prepaid, value: 500, wallet: 2000),
      );

      // Below the fold on a test-sized screen: the revenue models sit above it.
      await tester.scrollUntilVisible(
        find.byKey(MerchantBillingScreen.topUpKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantBillingScreen.topUpKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(MerchantBillingScreen.amountKey), '50');
      await tester.tap(find.byKey(MerchantBillingScreen.confirmTopUpKey));
      await tester.pumpAndSettle();

      expect(billing.walletOf('m1'), 7000);
    });

    // An empty wallet stops the merchant taking orders at all, so it cannot be a number
    // sitting quietly in a corner.
    testWidgets('an exhausted wallet is called out', (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.prepaid, value: 500, wallet: 200),
      );

      expect(find.byKey(MerchantBillingScreen.exhaustedKey), findsOneWidget);
    });

    testWidgets('a funded wallet is not', (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.prepaid, value: 500, wallet: 5000),
      );

      expect(find.byKey(MerchantBillingScreen.exhaustedKey), findsNothing);
    });
  });

  // Collecting what a merchant owes is a person with a receipt, and the person needs a
  // number to ask for. `commission_owed` was a column since the first schema that no
  // screen displayed, and `platform_owes` had nowhere to be read at all.
  group('the account on the orders', () {
    /// Scrolls the account card into view.
    ///
    /// It sits below the plan, the wallet and the term, and `find.byKey` skips offstage
    /// widgets by default — so a card that is built but scrolled past reads as one the
    /// screen never draws. Scrolling asserts the stronger thing anyway: that an admin can
    /// actually reach it.
    /// Everything below asserts with `skipOffstage: false`.
    ///
    /// The card is the last of four in a `ListView`, so in a test window it is built but
    /// scrolled past — and `find.byKey` skips offstage widgets, which reads as "the
    /// screen does not draw this". Scrolling to it instead was tried and is the wrong
    /// tool here: this screen has several nested scrollables, `scrollUntilVisible` picks
    /// one by `single` and throws `Bad state: Too many elements`, and there is nothing on
    /// this card to tap anyway. What is worth pinning is that it is in the list with the
    /// right figures; that a `ListView` scrolls is Flutter's problem.
    const offstageToo = false;

    /// Drags the list far enough that the last card is built.
    ///
    /// `skipOffstage: false` finds a widget that exists and is scrolled past; it cannot
    /// find one a lazy `ListView` never built, which is what happens under prepaid where
    /// the wallet card pushes this one further down. Dragging the keyed list is
    /// unambiguous where `scrollUntilVisible` is not.
    Future<void> toTheBottom(WidgetTester tester) async {
      await tester.drag(
        find.byKey(MerchantBillingScreen.listKey),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
    }

    OrderSettlement settlement({
      String orderId = 'o1',
      int amount = 2000,
      int platformOwes = 0,
      DateTime? reversedAt,
    }) =>
        OrderSettlement(
          orderId: orderId,
          merchantId: 'm1',
          model: RevenueModel.commission,
          basis: 20000,
          amount: amount,
          platformOwes: platformOwes,
          settledAt: DateTime(2026, 8, 24),
          reversedAt: reversedAt,
        );

    testWidgets('a commission merchant shows what is outstanding', (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.commission, value: 1000, owed: 47500),
        settlements: [settlement()],
      );

      expect(find.byKey(MerchantBillingScreen.settlementsKey,
          skipOffstage: offstageToo), findsOneWidget);
      expect(find.byKey(MerchantBillingScreen.owedKey, skipOffstage: offstageToo),
          findsOneWidget);
      expect(find.textContaining('475', skipOffstage: offstageToo), findsWidgets);
    });

    // Under a subscription nothing is taken per order, so there is no account to read —
    // the term is the whole arrangement, and a card of zeroes beside it invites the
    // question of which one is right.
    testWidgets('a subscription merchant has no such card', (tester) async {
      await pump(tester, seed: merchant());

      // `skipOffstage: false`: the card must not exist at all, not merely be out of
      // view. Scrolling for it would loop rather than fail, since it is not there.
      expect(
        find.byKey(MerchantBillingScreen.settlementsKey, skipOffstage: offstageToo),
        findsNothing,
      );
    });

    // Under prepaid the money was taken in advance, so there is nothing outstanding —
    // a line reading "المستحق" would be a debt the merchant does not have.
    testWidgets('a prepaid merchant has the card but nothing outstanding',
        (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.prepaid, value: 500, wallet: 3000),
        settlements: [settlement(amount: 500)],
      );

      await toTheBottom(tester);
      expect(find.byKey(MerchantBillingScreen.settlementsKey,
          skipOffstage: offstageToo), findsOneWidget);
      expect(find.byKey(MerchantBillingScreen.owedKey, skipOffstage: offstageToo),
          findsNothing);
    });

    testWidgets('what the platform owes back is its own figure', (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.commission, value: 1000),
        settlements: [settlement(platformOwes: 3000)],
      );

      // Kept apart from the commission on purpose: netting them into one number is how a
      // merchant stops being able to check either.
      expect(
          find.byKey(MerchantBillingScreen.platformOwesKey, skipOffstage: offstageToo),
          findsOneWidget);
    });

    // "Nothing has been delivered yet" and "the figures failed to load" look identical
    // as a blank space, and one of them is a reason to phone somebody.
    testWidgets('no delivered orders says so rather than showing nothing',
        (tester) async {
      await pump(tester, seed: merchant(model: RevenueModel.commission, value: 1000));

      expect(
          find.byKey(MerchantBillingScreen.noSettlementsKey, skipOffstage: offstageToo),
          findsOneWidget);
    });

    testWidgets('and a failed read offers a retry', (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.commission, value: 1000),
        settlementFailure: const OfflineFailure(),
      );

      expect(find.byType(LuqmaErrorView, skipOffstage: offstageToo), findsOneWidget);
    });
  });
}
