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
      // Starting today, so approving asks no question about the date — that path has
      // its own group below.
      await pump(tester, seed: [promotion(startAt: now)]);

      await tester.tap(find.byKey(PromotionsScreen.approveKey('p1')));
      await tester.pumpAndSettle();

      expect(promotions['p1']!.status, PromotionStatus.approved);
      expect(promotions['p1']!.approvedBy, 'admin1');
    });

    // Approved, not active. The campaign starts on its own date — and now that the
    // admin is *asked* which date is meant, keeping it is the answer that preserves the
    // rule.
    testWidgets('approving does not start it early', (tester) async {
      await pump(tester, seed: [promotion(startAt: DateTime(2026, 9, 10))]);

      await tester.tap(find.byKey(PromotionsScreen.approveKey('p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(PromotionsScreen.keepDateKey));
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
      await pump(tester, seed: [promotion(startAt: now)]);

      await tester.tap(find.byKey(PromotionsScreen.approveKey('p1')));
      await tester.pumpAndSettle();

      expect(find.byKey(PromotionsScreen.emptyKey), findsOneWidget);
    });
  });

  // The other half of the screen, and the half that did not exist: this was an
  // approve/reject queue only, so the owner could act on what merchants asked for and
  // could not put up a banner of their own. Announcing free delivery meant signing into
  // a merchant account to ask themselves for it first.
  group('putting one up', () {
    Future<void> openForm(WidgetTester tester) async {
      await tester.tap(find.byKey(PromotionsScreen.createKey));
      await tester.pumpAndSettle();
    }

    Future<void> chooseMerchant(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(PromotionsScreen.formMerchantKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    testWidgets('the screen offers a way to make one', (tester) async {
      await pump(tester);

      expect(find.byKey(PromotionsScreen.createKey), findsOneWidget);
    });

    testWidgets('a filled form creates it, already approved', (tester) async {
      await pump(tester);
      await openForm(tester);

      await chooseMerchant(tester, 'مطعم الشاطئ');
      await tester.enterText(
          find.byKey(PromotionsScreen.formTitleKey), 'التوصيل مجاني النهارده');
      await tester.tap(find.byKey(PromotionsScreen.formSubmitKey));
      await tester.pumpAndSettle();

      final made = promotions.all.single;
      expect(made.title, 'التوصيل مجاني النهارده');
      expect(made.merchantId, 'm1');
      // Approved on arrival: the admin writing it is the approval, and a queue entry
      // waiting for the person who just made it means nothing.
      expect(made.status, PromotionStatus.approved);
      expect(made.approvedBy, 'admin1');
    });

    // It does not then sit in the queue asking to be approved by whoever just approved
    // it — the queue is for what merchants asked for.
    testWidgets('and it does not land back in the queue', (tester) async {
      await pump(tester);
      await openForm(tester);

      await chooseMerchant(tester, 'مطعم الشاطئ');
      await tester.enterText(find.byKey(PromotionsScreen.formTitleKey), 'عرض');
      await tester.tap(find.byKey(PromotionsScreen.formSubmitKey));
      await tester.pumpAndSettle();

      expect(find.byKey(PromotionsScreen.emptyKey), findsOneWidget);
    });

    testWidgets('a banner with no words never reaches the repository', (tester) async {
      await pump(tester);
      await openForm(tester);

      await chooseMerchant(tester, 'مطعم الشاطئ');
      await tester.tap(find.byKey(PromotionsScreen.formSubmitKey));
      await tester.pumpAndSettle();

      expect(promotions.all, isEmpty);
    });

    testWidgets('and neither does one with no shop picked', (tester) async {
      await pump(tester);
      await openForm(tester);

      await tester.enterText(find.byKey(PromotionsScreen.formTitleKey), 'عرض');
      await tester.tap(find.byKey(PromotionsScreen.formSubmitKey));
      await tester.pumpAndSettle();

      expect(promotions.all, isEmpty);
    });

    // Silence after a tap is indistinguishable from a broken button.
    testWidgets('a refused create is said out loud', (tester) async {
      await pump(tester);
      await openForm(tester);

      await chooseMerchant(tester, 'مطعم الشاطئ');
      await tester.enterText(find.byKey(PromotionsScreen.formTitleKey), 'عرض');
      promotions.failNext = const PermissionFailure();
      await tester.tap(find.byKey(PromotionsScreen.formSubmitKey));
      await tester.pumpAndSettle();

      // The refusal earns its own sentence rather than a shrug: "you are not allowed"
      // and "it did not go through" ask for completely different next moves.
      expect(find.text('مش مسموحلك تحط إعلانات.'), findsOneWidget);
      expect(promotions.all, isEmpty);
    });
  });

  // The owner approved a banner and watched nothing happen. It was correct — the request
  // was dated tomorrow and `startAt` decides — but the code that set that date said "the
  // admin moves it when they approve", and the admin had no way to move anything.
  group('when a request starts later', () {
    Future<void> approve(WidgetTester tester) async {
      await tester.tap(find.byKey(PromotionsScreen.approveKey('p1')));
      await tester.pumpAndSettle();
    }

    testWidgets('approving one dated ahead asks which date is meant', (tester) async {
      await pump(tester, seed: [promotion(startAt: now.add(const Duration(days: 1)))]);

      await approve(tester);

      expect(find.byKey(PromotionsScreen.startNowKey), findsOneWidget);
      expect(find.byKey(PromotionsScreen.keepDateKey), findsOneWidget);
    });

    testWidgets('and starting it now makes it live immediately', (tester) async {
      await pump(tester, seed: [promotion(startAt: now.add(const Duration(days: 1)))]);

      await approve(tester);
      await tester.tap(find.byKey(PromotionsScreen.startNowKey));
      await tester.pumpAndSettle();

      final approved = promotions.all.single;
      expect(approved.status, PromotionStatus.approved);
      expect(approved.isLiveAt(now), isTrue);
    });

    // A campaign shortened for the crime of being approved would be a worse bug than the
    // one this fixes.
    testWidgets('and it keeps the length that was asked for', (tester) async {
      await pump(tester, seed: [
        promotion(startAt: now.add(const Duration(days: 1))),
      ]);
      final asked = promotions.all.single;
      final wanted = asked.endAt.difference(asked.startAt);

      await approve(tester);
      await tester.tap(find.byKey(PromotionsScreen.startNowKey));
      await tester.pumpAndSettle();

      final approved = promotions.all.single;
      expect(approved.endAt.difference(approved.startAt), wanted);
    });

    // The rule stands: a campaign genuinely meant for next week must not jump the queue.
    testWidgets('keeping the date leaves it dark until then', (tester) async {
      await pump(tester, seed: [promotion(startAt: now.add(const Duration(days: 1)))]);

      await approve(tester);
      await tester.tap(find.byKey(PromotionsScreen.keepDateKey));
      await tester.pumpAndSettle();

      final approved = promotions.all.single;
      expect(approved.status, PromotionStatus.approved);
      expect(approved.isLiveAt(now), isFalse);
    });

    // One that already starts now needs no question asked.
    testWidgets('a request that starts today is approved without a dialog',
        (tester) async {
      await pump(tester, seed: [promotion(startAt: now)]);

      await approve(tester);

      expect(find.byKey(PromotionsScreen.startNowKey), findsNothing);
      expect(promotions.all.single.status, PromotionStatus.approved);
    });
  });
}
