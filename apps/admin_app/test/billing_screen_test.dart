// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:admin_app/src/billing/merchant_billing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

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
  late FakeSettlementRepository settlementRepo;
  late FakeMerchantRepository merchants;

  Future<void> pump(
    WidgetTester tester, {
    Merchant? seed,
    List<Subscription> subscriptions = const [],
    List<OrderSettlement> settlements = const [],
    Failure? settlementFailure,
    Failure? collectFailure,

    /// A repository of the test's own, for the cases about *retrying* a collection —
    /// where what happened on the first attempt is the whole question.
    FakeSettlementRepository? settlementRepoOverride,

    /// Who is looking. Left null, the identity is whatever the admin session above
    /// resolves to — which is how every test before the moderator's was written.
    StaffIdentity? who,

    /// A window tall enough for every card to be built at once. A lazy `ListView` never
    /// builds a card below the fold, so a test that asserts a control is *absent* would
    /// pass on a card that simply was not there yet.
    bool tall = false,
  }) async {
    settlementRepo = settlementRepoOverride ??
        FakeSettlementRepository(
          seed: settlements,
          failure: settlementFailure,
          writeFailure: collectFailure,
          owedStart: (seed ?? merchant()).commissionOwed,
        );
    // A phone, not the runner's 800x600 default — which is wider than it is tall and
    // unlike anything this ships on. `ListView` builds lazily, so a card below the fold
    // of a window that shape is not merely off-screen: it does not exist, and every
    // assertion about it reads as "the screen does not draw this".
    tester.view.physicalSize = Size(1080, tall ? 9000 : 2340);
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
          if (who != null) staffIdentityProvider.overrideWithValue(who),
          merchantRepositoryProvider.overrideWithValue(merchants),
          billingRepositoryProvider.overrideWithValue(billing),
          settlementRepositoryProvider.overrideWithValue(settlementRepo),
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

  // A moderator is an admin except money (`20261101010000_a_moderator_cannot_move_money.sql`).
  // The server refuses every one of these four for a moderator; the screen's job is not to
  // offer a button that ends in «مااتحفظتش», and to say whose job it is instead.
  group('who may move the money', () {
    // Prepaid with a debt outstanding: the one shop where all four controls are drawn at
    // once — the model, the wallet's top-up, a subscription term, and «سجّل تحصيل».
    Merchant everyControl() =>
        merchant(model: RevenueModel.prepaid, value: 500, wallet: 2000, owed: 5000);

    final moneyControls = [
      MerchantBillingScreen.saveModelKey,
      MerchantBillingScreen.topUpKey,
      MerchantBillingScreen.recordKey,
      MerchantBillingScreen.collectKey,
    ];

    testWidgets('a moderator reads every figure and is offered none of the controls',
        (tester) async {
      await pump(
        tester,
        seed: everyControl(),
        tall: true,
        who: const StaffIdentity(
          uid: 'mod1',
          role: StaffRole.moderator,
          scope: StaffScope.platform,
          isAdmin: true,
        ),
      );

      // The figures, so the absences below are about the controls and not about a card
      // that was never built.
      expect(find.byKey(MerchantBillingScreen.currentModelKey(RevenueModel.prepaid)),
          findsOneWidget);
      expect(find.byKey(MerchantBillingScreen.walletKey), findsOneWidget);
      expect(find.byKey(MerchantBillingScreen.noTermKey), findsOneWidget);
      expect(find.byKey(MerchantBillingScreen.owedKey), findsOneWidget);
      expect(find.textContaining('50 ج'), findsWidgets);

      for (final control in moneyControls) {
        expect(find.byKey(control), findsNothing, reason: '$control is money');
      }
      expect(find.byKey(MerchantBillingScreen.moderatorNoteKey), findsWidgets);
    });

    testWidgets('a platform admin is offered all four', (tester) async {
      await pump(
        tester,
        seed: everyControl(),
        tall: true,
        who: const StaffIdentity(
          uid: 'admin1',
          role: StaffRole.admin,
          scope: StaffScope.platform,
          isAdmin: true,
        ),
      );

      for (final control in moneyControls) {
        expect(find.byKey(control), findsOneWidget, reason: '$control');
      }
      expect(find.byKey(MerchantBillingScreen.moderatorNoteKey), findsNothing);
    });

    // An identity that has not resolved is neither. Hiding on «not a platform admin» would
    // take the till away from the owner for the moment a token spends refreshing — with
    // cash in their hand.
    testWidgets('an identity still resolving takes nothing away', (tester) async {
      await pump(tester, seed: everyControl(), tall: true, who: StaffIdentity.none);

      for (final control in moneyControls) {
        expect(find.byKey(control), findsOneWidget, reason: '$control');
      }
    });
  });

  group('how this merchant pays', () {
    // Two, since 2026-09-19: a monthly amount is a plan, recorded from «الاشتراكات».
    testWidgets('commission and prepaid are offered', (tester) async {
      await pump(tester);

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
      // Its own rate: the one agreed with this shop, not the one every shop follows.
      await tester.tap(find.byKey(MerchantBillingScreen.customRateKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(MerchantBillingScreen.rateKey), '12');
      await tester.tap(find.byKey(MerchantBillingScreen.saveModelKey));
      await tester.pumpAndSettle();
      // How a shop is charged from the next order on is said back before it changes.
      await tester.tap(find.byKey(MerchantBillingScreen.confirmModelKey));
      await tester.pumpAndSettle();

      final saved = (await merchants.getMerchant('m1')).valueOrNull!;
      expect(saved.revenueModel, RevenueModel.commission);
      // Twelve per cent, in basis points — the unit the engine actually works in.
      expect(saved.revenueValue, 1200);
    });

    // 2026-09-19: one rate for every shop. A shop that follows it has nothing to type, and
    // saving puts it back on the one rate.
    testWidgets('following the one rate asks for no rate and saves as following',
        (tester) async {
      await pump(tester, seed: merchant(model: RevenueModel.prepaid, value: 500));

      await tester.tap(
        find.byKey(MerchantBillingScreen.modelKey(RevenueModel.commission)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(MerchantBillingScreen.rateKey), findsNothing);
      expect(find.textContaining('النسبة الموحّدة'), findsWidgets);

      await tester.tap(find.byKey(MerchantBillingScreen.saveModelKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantBillingScreen.confirmModelKey));
      await tester.pumpAndSettle();

      final saved = (await merchants.getMerchant('m1')).valueOrNull!;
      expect(saved.revenueModel, RevenueModel.commission);
      expect(saved.commissionCustom, isFalse);
      expect(saved.revenueValue, 500);
    });

    testWidgets('a monthly amount is not a choice here — plans are', (tester) async {
      await pump(tester);
      expect(
        find.byKey(MerchantBillingScreen.modelKey(RevenueModel.subscription)),
        findsNothing,
      );
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
      // Scrolled to rather than tapped where it happened to be. The screen body is a
      // `ListView` and this button sits below the fold on a 360x780 phone — it only used
      // to be reachable because the secondary text under every card was 13sp. Raising
      // that token to the 15 `docs/14` has always asked for pushed it eleven points past
      // the bottom, and the tap landed outside the render tree.
      await tester.ensureVisible(find.byKey(MerchantBillingScreen.recordKey));
      await tester.pumpAndSettle();
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


    testWidgets('billing reads the whole account beyond a hundred settlements', (tester) async {
      await pump(tester,
        seed: merchant(model: RevenueModel.commission, value: 1000),
        settlements: [
          for (var i = 0; i < 101; i++)
            settlement(orderId: 'o$i', amount: 200, platformOwes: 300),
          settlement(orderId: 'reversed', amount: 90000, platformOwes: 90000,
            reversedAt: DateTime(2026, 8, 25)),
        ]);
      expect(find.text('303 ج', skipOffstage: false), findsOneWidget);
      expect(find.text('202 ج', skipOffstage: false), findsOneWidget);
      expect(find.text('إجمالي الحساب من البداية', skipOffstage: false), findsOneWidget);
    });

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

  // Taking the money. Until this existed `commission_owed` only ever grew, and the first
  // merchant to pay in cash would have watched the figure on their own screen stay
  // exactly where it was.
  group('recording a collection', () {
    const offstage = false;

    Future<void> collect(WidgetTester tester, String amount) async {
      await tester.tap(find.byKey(MerchantBillingScreen.collectKey));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(MerchantBillingScreen.collectAmountKey), amount);
      await tester.tap(find.byKey(MerchantBillingScreen.confirmCollectKey));
      await tester.pumpAndSettle();
    }

    Future<void> pumpOwing(WidgetTester tester, int owed) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.commission, value: 1000, owed: owed),
      );
      await tester.drag(
        find.byKey(MerchantBillingScreen.listKey),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the button is there when something is owed', (tester) async {
      await pumpOwing(tester, 47500);

      expect(find.byKey(MerchantBillingScreen.collectKey, skipOffstage: offstage),
          findsOneWidget);
    });

    // Nothing to take. And handing money *back* is a different act, which this screen
    // must not be able to perform by accident.
    testWidgets('and gone when nothing is', (tester) async {
      await pumpOwing(tester, 0);

      expect(find.byKey(MerchantBillingScreen.collectKey, skipOffstage: offstage),
          findsNothing);
    });

    testWidgets('nor is it offered against a credit', (tester) async {
      await pumpOwing(tester, -2500);

      expect(find.byKey(MerchantBillingScreen.collectKey, skipOffstage: offstage),
          findsNothing);
    });

    // The wallet, the subscription and the courier screen all shut the door before the
    // dialog opens; this one did not. On a slow connection two taps stacked two dialogs,
    // the admin recorded the cash in the top one, and the one left underneath — empty —
    // read as "it did not take". Typed again, it minted a second receipt and the shop was
    // credited money it never paid.
    testWidgets('a repeated tap opens only one collection', (tester) async {
      // A pending record, so the dialog waits on the receipts before it opens — the
      // round trip a real phone spends on the network, and the window a second tap
      // lands in. With every fake answering at once there is no window, and the test
      // passed without the guard.
      await SharedPreferencesAsync().setString(
        'pending_payment_merchant_m1',
        jsonEncode({'receiptId': 'r-1', 'amount': 10000}),
      );
      final slow = _SlowReceipts(owedStart: 47500);
      await pump(
        tester,
        seed: merchant(model: RevenueModel.commission, value: 1000, owed: 47500),
        settlementRepoOverride: slow,
      );
      await tester.drag(
        find.byKey(MerchantBillingScreen.listKey),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();

      final button =
          find.byKey(MerchantBillingScreen.collectKey, skipOffstage: offstage);
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      slow.answer();
      await tester.pumpAndSettle();

      expect(
        find.byKey(MerchantBillingScreen.collectAmountKey, skipOffstage: false),
        findsOneWidget,
      );
    });

    // D8: another admin, or another device, collected since this screen loaded the
    // balance. Recording anyway turned the shop's debt into credit nobody meant.
    testWidgets('a balance that moved since the screen loaded is refused, and said',
        (tester) async {
      final elsewhere = FakeSettlementRepository(owedStart: 27500);
      await pump(
        tester,
        seed: merchant(model: RevenueModel.commission, value: 1000, owed: 47500),
        settlementRepoOverride: elsewhere,
      );
      await tester.drag(
        find.byKey(MerchantBillingScreen.listKey), const Offset(0, -900));
      await tester.pumpAndSettle();

      await collect(tester, '200');

      expect(elsewhere.owed, 27500, reason: 'nothing recorded');
      expect(find.textContaining('المستحق اتغيّر'), findsOneWidget);
      expect(
        await SharedPreferencesAsync().getString('pending_payment_merchant_m1'),
        isNull,
        reason: 'a refusal the server gave for good leaves no attempt pending');
    });

    // D10: a month's commission from a busy shop is not a meal, and ten thousand pounds
    // was refused as «اكتب مبلغ صحيح».
    testWidgets('a collection above ten thousand pounds is an ordinary collection',
        (tester) async {
      await pumpOwing(tester, 2000000);

      await collect(tester, '15000');

      expect(settlementRepo.recorded.single.amount, 1500000);
    });

    // D9: the attempt is written to the phone before the request (C-01). When that write
    // failed the dialog froze with every button disabled, cash in the admin's hand.
    testWidgets('a pending record that cannot be written stops the send, and says so',
        (tester) async {
      SharedPreferencesAsyncPlatform.instance = _UnwritablePrefs();
      await pumpOwing(tester, 47500);

      await collect(tester, '200');

      expect(settlementRepo.recorded, isEmpty, reason: 'no key on disk, no money moved');
      expect(find.textContaining('مقدرناش نحفظ'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
          find.byKey(MerchantBillingScreen.confirmCollectKey));
      expect(confirm.onPressed, isNotNull, reason: 'the dialog is not frozen');
    });

    testWidgets('recording one sends the figure that was typed', (tester) async {
      await pumpOwing(tester, 47500);

      await collect(tester, '300');

      expect(settlementRepo.recorded, hasLength(1));
      expect(settlementRepo.recorded.single.amount, 30000,
          reason: 'pounds on the screen, piastres in the database');
      expect(settlementRepo.owed, 17500);
    });

    // The admin is standing in a shop holding the cash. A collection that failed and one
    // that worked look identical if the only feedback is the screen refreshing.
    testWidgets('and says what is left', (tester) async {
      await pumpOwing(tester, 47500);

      await collect(tester, '300');

      expect(find.byKey(MerchantBillingScreen.collectedKey), findsOneWidget);
      expect(find.textContaining('175'), findsWidgets);
    });

    testWidgets('a collection that clears it says so', (tester) async {
      await pumpOwing(tester, 47500);

      await collect(tester, '475');

      expect(find.textContaining('الحساب مقفول'), findsOneWidget);
    });

    testWidgets('a refusal is said out loud rather than swallowed', (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.commission, value: 1000, owed: 47500),
        collectFailure: const PermissionFailure(),
      );
      await tester.drag(
        find.byKey(MerchantBillingScreen.listKey),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();

      await collect(tester, '300');

      // In its own words now (D4): a refusal the server gave for good is not «جرّب تاني».
      expect(find.textContaining('مش مسموح لك تسجّل تحصيل'), findsOneWidget);
    });

    // Negative means the merchant handed over more than they owed. Shown in words, not
    // as a minus sign, which reads as an error on a screen about money.
    testWidgets('a credit is named as one rather than shown as a minus', (tester) async {
      await pumpOwing(tester, -2500);

      expect(find.byKey(MerchantBillingScreen.creditKey, skipOffstage: offstage),
          findsOneWidget);
      expect(find.byKey(MerchantBillingScreen.owedKey, skipOffstage: offstage),
          findsNothing);
    });

    // The reply is lost on a phone in a shop, which is an ordinary thing. What must not
    // happen next is the admin typing a different figure, pressing again, and being told
    // that figure was recorded — because the server, correctly, answers a repeated
    // receipt with the receipt it already has and moves nothing.
    group('a retry after a lost reply', () {
      late _LostReply repo;

      Future<void> pumpLosing(WidgetTester tester, {bool landFirst = true}) async {
        repo = _LostReply(owedStart: 47500, landFirst: landFirst);
        await pump(
          tester,
          seed: merchant(model: RevenueModel.commission, value: 1000, owed: 47500),
          settlementRepoOverride: repo,
        );
        await tester.drag(
          find.byKey(MerchantBillingScreen.listKey),
          const Offset(0, -900),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('freezes the amount with the receipt', (tester) async {
        await pumpLosing(tester);

        await collect(tester, '100');
        expect(find.textContaining('مااتسجّلش'), findsOneWidget);
        expect(find.byKey(MerchantBillingScreen.pendingNoticeKey), findsOneWidget);

        final field = tester.widget<TextField>(
          find.byKey(MerchantBillingScreen.collectAmountKey),
        );
        expect(field.enabled, isFalse,
            reason: 'the receipt is sent; its amount is no longer anybody to change');

        // And the field refuses the new figure even when it is typed at.
        await tester.enterText(
            find.byKey(MerchantBillingScreen.collectAmountKey), '200');
        await tester.tap(find.byKey(MerchantBillingScreen.confirmCollectKey));
        await tester.pumpAndSettle();

        expect(repo.calls, hasLength(2));
        expect(repo.calls.first.receipt, isNotNull);
        expect(repo.calls.last.receipt, repo.calls.first.receipt,
            reason: 'one press, one receipt, however many attempts');
        expect(repo.calls.last.amount, 10000,
            reason: 'the amount the receipt was sent with, not the retyped one');
      });

      testWidgets('confirms the amount the server recorded, not the one on screen',
          (tester) async {
        await pumpLosing(tester);

        await collect(tester, '100');
        await tester.tap(find.byKey(MerchantBillingScreen.confirmCollectKey));
        await tester.pumpAndSettle();

        // One receipt for 100, from the attempt whose reply was lost.
        expect(repo.recorded, hasLength(1));
        expect(repo.recorded.single.amount, 10000);
        expect(repo.owed, 37500, reason: 'and the money moved exactly once');

        final said = tester
            .widget<Text>(find.byKey(MerchantBillingScreen.collectedKey))
            .data!;
        expect(said, contains('100'));
        expect(said, isNot(contains('200')));
      });

      // The notice used to say «اقفل وافتح تحصيل جديد», which did nothing at all:
      // reopening reloads the same frozen pair, because only a successful send of that
      // receipt clears it. So an admin whose 100 genuinely never landed, handed 250 a
      // week later, could leave the dialog only by recording the 100 — crediting a
      // merchant money they never paid, with no negative collection anywhere to undo it.
      testWidgets('a pending collection that never landed can be discarded',
          (tester) async {
        // Really never landed: since D8 a second collection is checked against the
        // balance the dialog opened on, and one that *had* landed would have moved it —
        // which is exactly the refusal an admin discarding a real payment ought to meet.
        await pumpLosing(tester, landFirst: false);

        await collect(tester, '100');
        expect(find.byKey(MerchantBillingScreen.pendingNoticeKey), findsOneWidget);

        await tester.tap(find.byKey(MerchantBillingScreen.discardPendingKey));
        await tester.pumpAndSettle();

        expect(find.byKey(MerchantBillingScreen.pendingNoticeKey), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byKey(MerchantBillingScreen.collectAmountKey))
              .enabled,
          isTrue,
          reason: 'the discarded attempt holds the field no longer',
        );

        await tester.enterText(
            find.byKey(MerchantBillingScreen.collectAmountKey), '250');
        await tester.tap(find.byKey(MerchantBillingScreen.confirmCollectKey));
        await tester.pumpAndSettle();

        expect(find.byKey(MerchantBillingScreen.collectedKey), findsOneWidget);
        expect(repo.calls.last.amount, 25000, reason: 'the cash actually handed over');
        expect(repo.calls.last.receipt, isNot(repo.calls.first.receipt),
            reason: 'a fresh receipt, or the server answers with the discarded one');
      });

      // A pending record means the *reply* was lost, not that the money was. Asking the
      // receipts first is what keeps an admin from being shown a notice — and a frozen
      // field — about a collection that has already succeeded.
      testWidgets('a pending record whose collection landed is cleared silently',
          (tester) async {
        await SharedPreferencesAsync().setString(
          'pending_payment_merchant_m1',
          jsonEncode({'receiptId': 'r-1', 'amount': 10000}),
        );

        final landed = FakeSettlementRepository(
          owedStart: 37500,
          payments: [
            CommissionPayment(
              id: 'pay-1',
              merchantId: 'm1',
              amount: 10000,
              recordedBy: 'admin1',
              recordedAt: DateTime(2026, 8, 30),
              clientPaymentId: 'r-1',
            ),
          ],
        );
        await pump(
          tester,
          seed: merchant(model: RevenueModel.commission, value: 1000, owed: 37500),
          settlementRepoOverride: landed,
        );
        await tester.drag(
          find.byKey(MerchantBillingScreen.listKey),
          const Offset(0, -900),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(MerchantBillingScreen.collectKey));
        await tester.pumpAndSettle();

        expect(find.byKey(MerchantBillingScreen.pendingNoticeKey), findsNothing);
        expect(
          tester
              .widget<TextField>(find.byKey(MerchantBillingScreen.collectAmountKey))
              .enabled,
          isTrue,
        );
        expect(
          await SharedPreferencesAsync().getString('pending_payment_merchant_m1'),
          isNull,
          reason: 'a record about a collection that landed is not kept',
        );
      });

      // The receipt and the figure asked for are allowed to differ, and when they do the
      // admin is reading a number they did not type. Said out loud, or it is a figure to
      // doubt rather than a receipt to read.
      testWidgets('says so when the receipt disagrees with what was asked for',
          (tester) async {
        final stale = _StaleReceipt(owedStart: 47500);
        await pump(
          tester,
          seed: merchant(model: RevenueModel.commission, value: 1000, owed: 47500),
          settlementRepoOverride: stale,
        );
        await tester.drag(
          find.byKey(MerchantBillingScreen.listKey),
          const Offset(0, -900),
        );
        await tester.pumpAndSettle();

        await collect(tester, '250');

        final said = tester
            .widget<Text>(find.byKey(MerchantBillingScreen.collectedKey))
            .data!;
        expect(said, contains('100'), reason: 'the receipt the server holds');
        expect(said, contains('250'), reason: 'and the figure that was not recorded');
        expect(said, contains('قبل كده'));
      });
    });

    // `PopScope` used to sit outside the `StatefulBuilder`, so it kept the `canPop` it
    // was built with — true — however many times the dialog rebuilt. Android Back took
    // the dialog away mid-save, and a collection that then succeeded exited at the
    // mounted check: no confirmation, no refreshed figures, and cash on the counter.
    testWidgets('Android back cannot dismiss the dialog mid-save', (tester) async {
      final completer = Completer<Result<CommissionCollection>>();
      final repo = _PendingCollection(completer, owedStart: 47500);

      await pump(
        tester,
        seed: merchant(model: RevenueModel.commission, value: 1000, owed: 47500),
        settlementRepoOverride: repo,
      );
      await tester.drag(
        find.byKey(MerchantBillingScreen.listKey),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(MerchantBillingScreen.collectKey));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(MerchantBillingScreen.collectAmountKey), '300');
      await tester.tap(find.byKey(MerchantBillingScreen.confirmCollectKey));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantBillingScreen.confirmCollectKey), findsOneWidget,
          reason: 'the dialog is still there, because the save is still running');

      completer.complete(
        const Result.ok(CommissionCollection(recorded: 30000, remaining: 17500)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantBillingScreen.collectedKey), findsOneWidget);
    });

    // A merchant moved to a subscription with a debt outstanding is exactly the case
    // where somebody has to be able to collect it.
    testWidgets('a debt survives a move to a subscription, and can still be taken',
        (tester) async {
      await pump(tester, seed: merchant(owed: 47500));
      await tester.drag(
        find.byKey(MerchantBillingScreen.listKey),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantBillingScreen.settlementsKey, skipOffstage: offstage),
          findsOneWidget);
      expect(find.byKey(MerchantBillingScreen.collectKey, skipOffstage: offstage),
          findsOneWidget);
    });
  });

  // QA review 2026-09-19: money written from this screen could be written twice, and a
  // wrong number made the button silently do nothing.
  group('money is said back, and written once', () {
    testWidgets('a wrong rate is said beside the field, and nothing is saved', (tester) async {
      await pump(tester);

      await tester.tap(
        find.byKey(MerchantBillingScreen.modelKey(RevenueModel.commission)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantBillingScreen.customRateKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(MerchantBillingScreen.rateKey), '150');
      await tester.tap(find.byKey(MerchantBillingScreen.saveModelKey));
      await tester.pumpAndSettle();

      expect(find.text('اكتب نسبة من 0 لـ 100'), findsOneWidget);
      expect(find.byKey(MerchantBillingScreen.confirmModelKey), findsNothing);
    });

    testWidgets('switching from a percentage to a fee does not carry the number across',
        (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.commission, value: 1000)
            .copyWith(commissionCustom: true),
      );

      await tester.tap(find.byKey(MerchantBillingScreen.modelKey(RevenueModel.prepaid)));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byKey(MerchantBillingScreen.rateKey));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('a top-up says it was recorded', (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.prepaid, value: 500, wallet: 2000),
      );
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

      expect(find.byKey(MerchantBillingScreen.toppedUpKey), findsOneWidget);
    });

    testWidgets('a failed top-up offers a retry, and the retry credits once', (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.prepaid, value: 500, wallet: 2000),
      );
      billing.failure = const OfflineFailure();
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

      expect(find.textContaining('مااتسجّلش'), findsOneWidget);
      expect(billing.walletOf('m1'), 2000);

      // The retry is the attempt itself, reopened — not a button on a SnackBar that
      // vanishes after a few seconds and does not survive the app being killed, which is
      // the failure this whole journal exists for.
      billing.failure = null;
      await tester.tap(find.byKey(MerchantBillingScreen.topUpKey));
      await tester.pumpAndSettle();

      // Named, with its figure frozen: 50 ج is not the admin's to change once the server
      // may already have credited it.
      expect(find.byKey(MerchantBillingScreen.pendingNoticeKey), findsOneWidget);
      expect(find.byKey(MerchantBillingScreen.amountKey), findsNothing);

      await tester.tap(find.text('أكّد'));
      await tester.pumpAndSettle();

      expect(billing.walletOf('m1'), 7000);
      expect(billing.topUpReceipts.length, 2,
          reason: 'both attempts went out');
      expect(billing.topUpReceipts.first, billing.topUpReceipts.last,
          reason: 'a retry that mints a new receipt credits the same cash twice');
    });

    // D4: a refusal the server gave for good left the attempt on the phone, so every
    // later tap opened «في عملية اتبعتت وماتأكدتش» about a top-up that never could land.
    testWidgets('a top-up refused for good says why and leaves nothing pending',
        (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.prepaid, value: 500, wallet: 2000),
      );
      billing.failure = const PermissionFailure();
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

      expect(find.textContaining('مش مسموح لك تسجّل شحن'), findsOneWidget);

      billing.failure = null;
      await tester.tap(find.byKey(MerchantBillingScreen.topUpKey));
      await tester.pumpAndSettle();
      expect(find.byKey(MerchantBillingScreen.pendingNoticeKey), findsNothing);
      expect(find.byKey(MerchantBillingScreen.amountKey), findsOneWidget);
    });

    testWidgets('a discarded top-up starts clean rather than resending', (tester) async {
      await pump(
        tester,
        seed: merchant(model: RevenueModel.prepaid, value: 500, wallet: 2000),
      );
      billing.failure = const OfflineFailure();
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

      // Somebody who knows the cash was never handed over has to be able to say so, or
      // the only way out of the dialog is to credit money nobody paid.
      billing.failure = null;
      await tester.tap(find.byKey(MerchantBillingScreen.topUpKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantBillingScreen.discardPendingKey));
      await tester.pumpAndSettle();

      expect(billing.walletOf('m1'), 2000, reason: 'nothing was credited');

      await tester.tap(find.byKey(MerchantBillingScreen.topUpKey));
      await tester.pumpAndSettle();
      expect(find.byKey(MerchantBillingScreen.pendingNoticeKey), findsNothing);
      expect(find.byKey(MerchantBillingScreen.amountKey), findsOneWidget);
    });

    testWidgets('a payment shows the amount and the new end date before recording',
        (tester) async {
      await pump(tester);

      await tester.ensureVisible(find.byKey(MerchantBillingScreen.recordKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantBillingScreen.recordKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantBillingScreen.planChoiceKey('basic')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(MerchantBillingScreen.monthsKey), '2');
      await tester.pumpAndSettle();

      final summary = tester.widget<Text>(find.byKey(MerchantBillingScreen.paymentSummaryKey));
      expect(summary.data, contains('500 ج'));
      expect(summary.data, contains('لحد'));
    });
  });
}

/// A collection that reaches the database and whose reply does not come back.
///
/// The write is a real one — `super.recordPayment` commits it — and only the answer is
/// lost, which is the shape of the failure this path exists for. A fake that refused the
/// write instead would test nothing: the whole question is what the *second* attempt is
/// told about a collection that already happened.
class _LostReply extends FakeSettlementRepository {
  _LostReply({required super.owedStart, this.landFirst = true});

  final List<({int amount, String? receipt})> calls = [];
  bool loseNextReply = true;

  /// Whether the first attempt reached the server before its reply was lost. False is a
  /// request that died on the way out.
  final bool landFirst;

  @override
  Future<Result<CommissionCollection>> recordPayment({
    required String merchantId,
    required int amount,
    String? note,
    String? clientPaymentId,
    int? expectedOwed,
  }) async {
    calls.add((amount: amount, receipt: clientPaymentId));
    if (loseNextReply && !landFirst) {
      loseNextReply = false;
      return const Result.err(UnknownFailure('the request never arrived'));
    }
    final result = await super.recordPayment(
      merchantId: merchantId,
      amount: amount,
      note: note,
      clientPaymentId: clientPaymentId,
      expectedOwed: expectedOwed,
    );
    if (loseNextReply) {
      loseNextReply = false;
      return const Result.err(UnknownFailure('the reply never arrived'));
    }
    return result;
  }
}

/// A server that answers with a receipt for a different amount than the one asked for —
/// what a retry of a collection that had already landed looks like from the screen.
class _StaleReceipt extends FakeSettlementRepository {
  _StaleReceipt({required super.owedStart});

  @override
  Future<Result<CommissionCollection>> recordPayment({
    required String merchantId,
    required int amount,
    String? note,
    String? clientPaymentId,
    int? expectedOwed,
  }) async =>
      const Result.ok(CommissionCollection(recorded: 10000, remaining: 37500));
}

/// A collection that is still in flight, so the dialog can be caught mid-save.
class _PendingCollection extends FakeSettlementRepository {
  _PendingCollection(this._completer, {required super.owedStart});

  final Completer<Result<CommissionCollection>> _completer;

  @override
  Future<Result<CommissionCollection>> recordPayment({
    required String merchantId,
    required int amount,
    String? note,
    String? clientPaymentId,
    int? expectedOwed,
  }) =>
      _completer.future;
}

/// Receipts that arrive only when the test says so — the network round trip a real phone
/// spends before the collection dialog opens.
class _SlowReceipts extends FakeSettlementRepository {
  _SlowReceipts({super.owedStart});

  final _gate = Completer<void>();

  void answer() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<Result<List<CommissionPayment>>> paymentsFor(String merchantId,
      {int limit = 100}) async {
    await _gate.future;
    return super.paymentsFor(merchantId, limit: limit);
  }
}

/// A phone whose preferences refuse to be written.
final class _UnwritablePrefs extends InMemorySharedPreferencesAsync {
  _UnwritablePrefs() : super.empty();

  @override
  Future<bool> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async =>
      throw StateError('disk full');
}
