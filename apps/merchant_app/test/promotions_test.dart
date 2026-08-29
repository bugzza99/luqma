import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/promotions/promotions_screen.dart';

/// Asking for a placement, from the merchant's side.
///
/// One screen and one flow for all four channels, because to a merchant they are one
/// thing: paying to be seen. The differences between them are what the form asks for,
/// not four different journeys.
void main() {
  final now = DateTime(2026, 8, 24, 12);

  Promotion promotion({
    String id = 'p1',
    PromotionChannel channel = PromotionChannel.homeBanner,
    PromotionStatus status = PromotionStatus.requested,
    String? rejectionReason,
    DateTime? startAt,
    DateTime? endAt,
  }) =>
      Promotion(
        id: id,
        cityId: 'edku',
        merchantId: 'm1',
        channel: channel,
        status: status,
        title: 'خصم النهارده',
        rejectionReason: rejectionReason,
        startAt: startAt ?? DateTime(2026, 8, 20),
        endAt: endAt ?? DateTime(2026, 9, 20),
        requestedBy: 'owner1',
      );

  late FakePromotionRepository promotions;

  Future<void> pump(
    WidgetTester tester, {
    List<Promotion> seed = const [],
    Map<String, Object> config = const {},
  }) async {
    // The same fixed hour the fixtures are built around. Without it the fake answers the
    // push cap against the wall clock while every campaign here is dated relative to
    // `now`, so the seven-day window drifts off the fixtures and the test starts failing
    // on a particular day of a particular week.
    promotions = FakePromotionRepository(seed: seed, clock: () => now);

    // The service starts on the compiled-in defaults and only takes fetched values after
    // a refresh — which is the whole point of it, so a test that wants a different cap
    // has to do what the app does at start-up.
    final remoteConfig = RemoteConfigService(FakeConfigFetcher(config));
    await remoteConfig.refresh();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          authServiceProvider.overrideWithValue(
            FakeAuthService(
              restoring: const LuqmaIdentity(
                uid: 'owner1',
                claims: {'role': 'owner', 'scope': 'merchant', 'merchantId': 'm1'},
              ),
            ),
          ),
          promotionRepositoryProvider.overrideWithValue(promotions),
          remoteConfigServiceProvider.overrideWithValue(remoteConfig),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: MerchantPromotionsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('what a merchant sees of their own', () {
    testWidgets('every campaign, whatever became of it', (tester) async {
      await pump(tester, seed: [
        promotion(id: 'live', status: PromotionStatus.approved),
        promotion(id: 'waiting'),
      ]);

      expect(find.byKey(MerchantPromotionsScreen.cardKey('live')), findsOneWidget);
      expect(find.byKey(MerchantPromotionsScreen.cardKey('waiting')), findsOneWidget);
    });

    // The whole point of requiring a reason. A merchant who is told only "rejected"
    // asks again with the same thing.
    testWidgets('a refusal shows why', (tester) async {
      await pump(tester, seed: [
        promotion(
          status: PromotionStatus.rejected,
          rejectionReason: 'الصورة مش واضحة',
        ),
      ]);

      expect(find.text('الصورة مش واضحة'), findsOneWidget);
    });

    // Approved is not live: the merchant needs to know it starts on Tuesday, not that
    // something is wrong today.
    testWidgets('an approved campaign that has not started says when it will',
        (tester) async {
      await pump(tester, seed: [
        promotion(
          status: PromotionStatus.approved,
          startAt: DateTime(2026, 9, 1),
          endAt: DateTime(2026, 9, 30),
        ),
      ]);

      expect(find.byKey(MerchantPromotionsScreen.scheduledKey('p1')), findsOneWidget);
    });

    testWidgets('nothing bought yet invites a first one', (tester) async {
      await pump(tester);

      expect(find.byKey(MerchantPromotionsScreen.emptyKey), findsOneWidget);
      expect(find.byKey(MerchantPromotionsScreen.askKey), findsOneWidget);
    });
  });

  group('asking for one', () {
    Future<void> ask(
      WidgetTester tester, {
      PromotionChannel channel = PromotionChannel.homeBanner,
      String title = 'خصم النهارده',
    }) async {
      await tester.tap(find.byKey(MerchantPromotionsScreen.askKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantPromotionsScreen.channelKey(channel)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(MerchantPromotionsScreen.titleKey),
        title,
      );
      await tester.tap(find.byKey(MerchantPromotionsScreen.submitKey));
      await tester.pumpAndSettle();
    }

    testWidgets('a request lands as requested, never as live', (tester) async {
      await pump(tester);

      await ask(tester);

      expect(promotions.all.single.status, PromotionStatus.requested);
      expect(promotions.all.single.merchantId, 'm1');
    });

    // A boost has nothing to write. Asking for a headline would be asking for something
    // that is never shown.
    testWidgets('a boost needs no text at all', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantPromotionsScreen.askKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(MerchantPromotionsScreen.channelKey(PromotionChannel.boost)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantPromotionsScreen.titleKey), findsNothing);
    });

    testWidgets('a banner with no headline is not sent', (tester) async {
      await pump(tester);

      await ask(tester, title: '   ');

      expect(promotions.all, isEmpty);
    });
  });

  group('the weekly push cap', () {
    // Unmoderated, uncapped push is the fastest way to make customers disable
    // notifications — and every operational alert goes with them.
    testWidgets('push is offered while the city is under the cap', (tester) async {
      await pump(tester, config: {'marketing_push_per_week': 3});

      await tester.tap(find.byKey(MerchantPromotionsScreen.askKey));
      await tester.pumpAndSettle();

      expect(
        find.byKey(MerchantPromotionsScreen.channelKey(PromotionChannel.push)),
        findsOneWidget,
      );
    });

    testWidgets('and refused once the week is full', (tester) async {
      await pump(
        tester,
        config: {'marketing_push_per_week': 1},
        seed: [
          promotion(
            id: 'sent',
            channel: PromotionChannel.push,
            status: PromotionStatus.ended,
            startAt: now.subtract(const Duration(days: 2)),
            endAt: now.subtract(const Duration(days: 2)),
          ),
        ],
      );

      await tester.tap(find.byKey(MerchantPromotionsScreen.askKey));
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantPromotionsScreen.pushFullKey), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.byKey(MerchantPromotionsScreen.channelKey(PromotionChannel.push)),
      );
      expect(button.onPressed, isNull);
    });

    // The cap is on the week, not for ever. A merchant told "no" with no horizon
    // assumes it is permanent and stops asking.
    testWidgets('the banner channels stay open when push is full', (tester) async {
      await pump(
        tester,
        config: {'marketing_push_per_week': 1},
        seed: [
          promotion(
            id: 'sent',
            channel: PromotionChannel.push,
            status: PromotionStatus.ended,
            startAt: now.subtract(const Duration(days: 2)),
            endAt: now.subtract(const Duration(days: 2)),
          ),
        ],
      );

      await tester.tap(find.byKey(MerchantPromotionsScreen.askKey));
      await tester.pumpAndSettle();

      final banner = tester.widget<OutlinedButton>(
        find.byKey(
          MerchantPromotionsScreen.channelKey(PromotionChannel.homeBanner),
        ),
      );
      expect(banner.onPressed, isNotNull);
    });
  });

  // Whether a campaign is running is a question about the calendar, not about which of
  // two words the status field happens to hold. `approved` is the only one anything
  // ever writes — nothing on the server promotes it to `active` — so a label keyed on
  // the status told a merchant whose banner was live that it had merely been signed off.
  group('is it running right now', () {
    testWidgets('an approved campaign inside its dates says it is live', (tester) async {
      await pump(tester, seed: [
        promotion(
          id: 'running',
          status: PromotionStatus.approved,
          startAt: DateTime(2026, 8, 20),
          endAt: DateTime(2026, 9, 20),
        ),
      ]);

      expect(find.text('شغال دلوقتي'), findsOneWidget);
    });

    // Approved is not live. A campaign signed off today for next week must not tell the
    // merchant it is already running, or they will ask why it is not on their screen.
    testWidgets('one approved for next week says it is approved, not live',
        (tester) async {
      await pump(tester, seed: [
        promotion(
          id: 'later',
          status: PromotionStatus.approved,
          startAt: DateTime(2026, 9, 1),
          endAt: DateTime(2026, 9, 20),
        ),
      ]);

      expect(find.text('اتوافق عليه'), findsOneWidget);
      expect(find.text('شغال دلوقتي'), findsNothing);
    });

    testWidgets('one whose dates have passed does not claim to be live', (tester) async {
      await pump(tester, seed: [
        promotion(
          id: 'over',
          status: PromotionStatus.approved,
          startAt: DateTime(2026, 7, 1),
          endAt: DateTime(2026, 8, 1),
        ),
      ]);

      expect(find.text('شغال دلوقتي'), findsNothing);
    });

    testWidgets('one still waiting is never live, whatever its dates', (tester) async {
      await pump(tester, seed: [promotion(id: 'waiting')]);

      expect(find.text('تحت المراجعة'), findsOneWidget);
      expect(find.text('شغال دلوقتي'), findsNothing);
    });
  });
}
