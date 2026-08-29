import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/shop/busy_toggle.dart';

/// "Busy" — the control a merchant reaches for during a rush.
///
/// It sets a timestamp, never a flag. A flag produces merchants stuck closed for days
/// because nobody remembered to undo it, and the support calls that follow.
void main() {
  const alwaysOpen = [
    OpeningWindow(weekday: DateTime.monday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.tuesday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.wednesday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.thursday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.friday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.saturday, openMinute: 0, closeMinute: 1440),
    OpeningWindow(weekday: DateTime.sunday, openMinute: 0, closeMinute: 1440),
  ];

  Merchant shop({
    DateTime? pausedUntil,
    MerchantStatus status = MerchantStatus.approved,
    RevenueModel revenueModel = RevenueModel.subscription,
    int revenueValue = 0,
    int walletBalance = 0,
  }) =>
      Merchant(
        id: 'm1',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'مطعم الشاطئ',
        zoneId: 'z1',
        phone: '01000000000',
        status: status,
        openingHours: alwaysOpen,
        pausedUntil: pausedUntil,
        revenueModel: revenueModel,
        revenueValue: revenueValue,
        walletBalance: walletBalance,
      );

  late FakeMerchantRepository merchants;

  Future<void> pump(WidgetTester tester, {Merchant? seed}) async {
    merchants = FakeMerchantRepository(seed: [seed ?? shop()]);

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
          merchantRepositoryProvider.overrideWithValue(merchants),
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
            child: Scaffold(body: BusyToggle()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('an open shop', () {
    testWidgets('says it is taking orders', (tester) async {
      await pump(tester);
      expect(find.byKey(BusyToggle.openKey), findsOneWidget);
    });

    testWidgets('offers to pause', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(BusyToggle.pauseKey));
      await tester.pumpAndSettle();

      expect(find.byKey(BusyToggle.sheetKey), findsOneWidget);
    });

    testWidgets('a chosen stretch sets a time, not a flag', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(BusyToggle.pauseKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(BusyToggle.choiceKey(60)));
      await tester.pumpAndSettle();

      final paused = (await merchants.getMerchant('m1')).valueOrNull!;
      expect(paused.pausedUntil, isNotNull);
      // Roughly an hour out. Exactness is not the point; a timestamp that lapses is.
      final minutes = paused.pausedUntil!.difference(DateTime.now()).inMinutes;
      expect(minutes, inInclusiveRange(58, 61));
    });
  });

  group('a paused shop', () {
    testWidgets('says so, and says until when', (tester) async {
      await pump(
        tester,
        seed: shop(pausedUntil: DateTime.now().add(const Duration(minutes: 45))),
      );

      expect(find.byKey(BusyToggle.pausedKey), findsOneWidget);
    });

    // Somebody who cleared the rush should not have to wait out a timer they set.
    testWidgets('can reopen before the time is up', (tester) async {
      await pump(
        tester,
        seed: shop(pausedUntil: DateTime.now().add(const Duration(minutes: 45))),
      );

      await tester.tap(find.byKey(BusyToggle.resumeKey));
      await tester.pumpAndSettle();

      expect((await merchants.getMerchant('m1')).valueOrNull!.pausedUntil, isNull);
      expect(find.byKey(BusyToggle.openKey), findsOneWidget);
    });

    // The whole reason it is a timestamp: a pause that has run out is not a pause.
    testWidgets('a pause that has lapsed reads as open', (tester) async {
      await pump(
        tester,
        seed: shop(pausedUntil: DateTime.now().subtract(const Duration(minutes: 1))),
      );

      expect(find.byKey(BusyToggle.openKey), findsOneWidget);
      expect(find.byKey(BusyToggle.pausedKey), findsNothing);
    });
  });

  group('a shop outside its hours', () {
    // Closed and paused are different things and must not be conflated: one is the
    // schedule the owner set, the other is a decision made two minutes ago.
    testWidgets('says it is closed, not that it is busy', (tester) async {
      await pump(
        tester,
        seed: Merchant(
          id: 'm1',
          cityId: 'edku',
          type: MerchantType.restaurant,
          name: 'مطعم الشاطئ',
          zoneId: 'z1',
          phone: '01000000000',
          status: MerchantStatus.approved,
          openingHours: const [],
        ),
      );

      expect(find.byKey(BusyToggle.closedKey), findsOneWidget);
      expect(find.byKey(BusyToggle.pauseKey), findsNothing);
    });
  });

  // This bar answered "are we open" from the schedule alone, while `place_order` answers
  // it from `Merchant.acceptsOrdersAt` — which also refuses a shop that is not approved
  // and a prepaid shop whose wallet has run out.
  //
  // So a merchant whose credit had gone read a green bar saying مفتوح وبتستقبل طلبات
  // while every customer in the city was refused with "merchant not accepting orders".
  // They would have spent the evening certain the app was broken, and been right that
  // something was — just not the thing they could see.
  group('open by the clock, refused by the server', () {
    testWidgets('an empty prepaid wallet is not open for business',
        (tester) async {
      await pump(
        tester,
        seed: shop(
          revenueModel: RevenueModel.prepaid,
          revenueValue: 500,
          walletBalance: 100,
        ),
      );

      expect(find.byKey(BusyToggle.blockedKey), findsOneWidget);
      expect(find.byKey(BusyToggle.openKey), findsNothing);
    });

    testWidgets('and neither is a suspended shop', (tester) async {
      await pump(tester, seed: shop(status: MerchantStatus.suspended));

      expect(find.byKey(BusyToggle.blockedKey), findsOneWidget);
      expect(find.byKey(BusyToggle.openKey), findsNothing);
    });

    testWidgets('a prepaid shop with credit is open as usual', (tester) async {
      // The guard has to let the ordinary case through, or it is just a broken screen.
      await pump(
        tester,
        seed: shop(
          revenueModel: RevenueModel.prepaid,
          revenueValue: 500,
          walletBalance: 5000,
        ),
      );

      expect(find.byKey(BusyToggle.openKey), findsOneWidget);
      expect(find.byKey(BusyToggle.blockedKey), findsNothing);
    });
  });
}
