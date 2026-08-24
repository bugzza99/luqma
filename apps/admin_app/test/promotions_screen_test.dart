import 'package:admin_app/src/promotions/promotions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The queue where a merchant's request becomes a placement, or does not.
///
/// The one asymmetry the whole promotions design rests on: a merchant may ask, and only
/// an admin may approve. Unmoderated push is the fastest way to make customers disable
/// notifications — and the operational channel goes with it.
void main() {
  final now = DateTime(2026, 8, 24, 12);

  Promotion promotion({
    String id = 'p1',
    String merchantId = 'm1',
    PromotionChannel channel = PromotionChannel.homeBanner,
    PromotionStatus status = PromotionStatus.requested,
    String title = 'خصم النهارده',
    DateTime? startAt,
  }) =>
      Promotion(
        id: id,
        cityId: 'edku',
        merchantId: merchantId,
        channel: channel,
        status: status,
        title: title,
        body: 'كل الفراخ ١٥٪ أقل',
        startAt: startAt ?? DateTime(2026, 8, 25),
        endAt: DateTime(2026, 9, 25),
        price: 30000,
        requestedBy: 'owner1',
      );

  const merchants = [
    Merchant(
      id: 'm1',
      cityId: 'edku',
      type: MerchantType.restaurant,
      name: 'مطعم الشاطئ',
      zoneId: 'z1',
      phone: '0100',
      status: MerchantStatus.approved,
    ),
  ];

  late FakePromotionRepository promotions;

  Future<void> pump(WidgetTester tester, {List<Promotion> seed = const []}) async {
    promotions = FakePromotionRepository(seed: seed);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          currentIdentityProvider.overrideWith(
            (ref) => Stream.value(
              const LuqmaIdentity(uid: 'admin1', claims: {'admin': true}),
            ),
          ),
          promotionRepositoryProvider.overrideWithValue(promotions),
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: merchants)),
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
            child: PromotionsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the queue', () {
    testWidgets('shows what is waiting, with who asked and for what', (tester) async {
      await pump(tester, seed: [promotion()]);

      expect(find.text('خصم النهارده'), findsOneWidget);
      expect(find.textContaining('مطعم الشاطئ'), findsWidgets);
    });

    testWidgets('an empty queue says so', (tester) async {
      await pump(tester);
      expect(find.byKey(PromotionsScreen.emptyKey), findsOneWidget);
    });

    testWidgets('a failed read never looks like an empty queue', (tester) async {
      promotions = FakePromotionRepository(failure: const OfflineFailure());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            currentIdentityProvider.overrideWith(
              (ref) => Stream.value(
                const LuqmaIdentity(uid: 'admin1', claims: {'admin': true}),
              ),
            ),
            promotionRepositoryProvider.overrideWithValue(promotions),
            merchantRepositoryProvider
                .overrideWithValue(FakeMerchantRepository(seed: merchants)),
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
              child: PromotionsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(PromotionsScreen.errorKey), findsOneWidget);
      expect(find.byKey(PromotionsScreen.emptyKey), findsNothing);
    });

    // A push reaches somebody who is not looking at the app. It is the one channel that
    // can cost the platform every other notification it will ever send.
    testWidgets('a push request is marked apart from a banner', (tester) async {
      await pump(tester, seed: [promotion(channel: PromotionChannel.push)]);

      expect(find.byKey(PromotionsScreen.pushWarningKey('p1')), findsOneWidget);
    });

    testWidgets('a banner request is not', (tester) async {
      await pump(tester, seed: [promotion()]);

      expect(find.byKey(PromotionsScreen.pushWarningKey('p1')), findsNothing);
    });
  });

  group('deciding', () {
    testWidgets('approving names the admin who did it', (tester) async {
      await pump(tester, seed: [promotion()]);

      await tester.tap(find.byKey(PromotionsScreen.approveKey('p1')));
      await tester.pumpAndSettle();

      expect(promotions['p1']!.status, PromotionStatus.approved);
      expect(promotions['p1']!.approvedBy, 'admin1');
    });

    // Approved, not active. The campaign starts on its own date.
    testWidgets('approving does not start it early', (tester) async {
      await pump(tester, seed: [promotion(startAt: DateTime(2026, 9, 10))]);

      await tester.tap(find.byKey(PromotionsScreen.approveKey('p1')));
      await tester.pumpAndSettle();

      expect(promotions['p1']!.isLiveAt(now), isFalse);
    });

    testWidgets('rejecting asks why', (tester) async {
      await pump(tester, seed: [promotion()]);

      await tester.tap(find.byKey(PromotionsScreen.rejectKey('p1')));
      await tester.pumpAndSettle();

      expect(find.byKey(PromotionsScreen.reasonKey), findsOneWidget);
      expect(promotions['p1']!.status, PromotionStatus.requested);
    });

    // Without a reason the merchant has nothing to fix, and will ask again with the
    // same thing.
    testWidgets('a refusal with no reason is not sent', (tester) async {
      await pump(tester, seed: [promotion()]);

      await tester.tap(find.byKey(PromotionsScreen.rejectKey('p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PromotionsScreen.confirmRejectKey));
      await tester.pumpAndSettle();

      expect(promotions['p1']!.status, PromotionStatus.requested);
    });

    testWidgets('a reason carries through to the merchant', (tester) async {
      await pump(tester, seed: [promotion()]);

      await tester.tap(find.byKey(PromotionsScreen.rejectKey('p1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(PromotionsScreen.reasonKey),
        'الصورة مش واضحة',
      );
      await tester.tap(find.byKey(PromotionsScreen.confirmRejectKey));
      await tester.pumpAndSettle();

      expect(promotions['p1']!.status, PromotionStatus.rejected);
      expect(promotions['p1']!.rejectionReason, 'الصورة مش واضحة');
    });

    testWidgets('a decided request leaves the queue', (tester) async {
      await pump(tester, seed: [promotion()]);

      await tester.tap(find.byKey(PromotionsScreen.approveKey('p1')));
      await tester.pumpAndSettle();

      expect(find.byKey(PromotionsScreen.emptyKey), findsOneWidget);
    });
  });
}
