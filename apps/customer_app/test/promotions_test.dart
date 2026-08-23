import 'package:customer_app/src/home/home_screen.dart';
import 'package:customer_app/src/home/sections/ad_slot_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Paid placements, as the customer meets them.
///
/// Two rules run through all of it: a banner never costs the screen space it cannot
/// fill, and a lift never reshuffles the merchants who paid for nothing.
void main() {
  final now = DateTime(2026, 8, 24, 12);

  Promotion promotion({
    String id = 'p1',
    String merchantId = 'm1',
    PromotionChannel channel = PromotionChannel.homeBanner,
    PromotionStatus status = PromotionStatus.active,
    PromotionRender render = PromotionRender.text,
    String title = 'خصم النهارده',
    String? mediaId,
    String? sectionKey,
    int priority = 0,
    DateTime? startAt,
    DateTime? endAt,
  }) =>
      Promotion(
        id: id,
        cityId: 'edku',
        merchantId: merchantId,
        channel: channel,
        status: status,
        renderMode: render,
        title: title,
        body: 'كل الفراخ ١٥٪ أقل',
        mediaId: mediaId,
        sectionKey: sectionKey,
        priority: priority,
        startAt: startAt ?? DateTime(2026, 8, 1),
        endAt: endAt ?? DateTime(2026, 9, 1),
        requestedBy: 'owner1',
      );

  Merchant merchant(String id, {String name = ''}) => Merchant(
        id: id,
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: name.isEmpty ? id : name,
        zoneId: 'z1',
        phone: '0100',
        status: MerchantStatus.approved,
      );

  Future<void> pump(
    WidgetTester tester, {
    List<Promotion> promotions = const [],
    List<HomeSection> sections = const [],
    List<Merchant> merchants = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          promotionRepositoryProvider
              .overrideWithValue(FakePromotionRepository(seed: promotions)),
          homeSectionRepositoryProvider
              .overrideWithValue(FakeHomeSectionRepository(seed: sections)),
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: merchants)),
          dailyMealRepositoryProvider
              .overrideWithValue(FakeDailyMealRepository()),
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
            child: HomeScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  HomeSection slot({String key = 'top', int maxAds = 1}) => HomeSection(
        key: key,
        type: 'adSlot',
        sortOrder: 0,
        cityId: 'edku',
        params: {'maxAds': maxAds},
      );

  const merchantList = HomeSection(
    key: 'list',
    type: 'merchantList',
    sortOrder: 1,
    cityId: 'edku',
  );

  group('a banner slot', () {
    testWidgets('shows a live banner', (tester) async {
      await pump(tester, sections: [slot()], promotions: [promotion()]);

      expect(find.text('خصم النهارده'), findsOneWidget);
    });

    // A merchant who has not bought a banner should cost the customer no space, and an
    // empty band on the home screen reads as a broken image.
    testWidgets('with nothing sold takes no space at all', (tester) async {
      await pump(tester, sections: [slot()]);

      expect(find.byKey(AdSlotSection.slotKey('top')), findsNothing);
    });

    testWidgets('shows nothing for a campaign that has not started', (tester) async {
      await pump(
        tester,
        sections: [slot()],
        promotions: [
          promotion(
            startAt: DateTime(2026, 9, 1),
            endAt: DateTime(2026, 9, 30),
          ),
        ],
      );

      expect(find.byKey(AdSlotSection.slotKey('top')), findsNothing);
    });

    // A banner promising a picture and carrying none is a broken box on every customer's
    // home screen. It simply does not render.
    testWidgets('refuses to draw an image banner with no image', (tester) async {
      await pump(
        tester,
        sections: [slot()],
        promotions: [promotion(render: PromotionRender.image)],
      );

      expect(find.byKey(AdSlotSection.slotKey('top')), findsNothing);
    });

    testWidgets('a text banner needs no artwork at all', (tester) async {
      await pump(tester, sections: [slot()], promotions: [promotion()]);

      expect(find.byKey(AdSlotSection.bannerKey('p1')), findsOneWidget);
    });

    // Two slots on one screen, told apart by key. A banner pinned to the top one must
    // not appear in the other.
    testWidgets('a banner pinned to one slot stays out of the other', (tester) async {
      await pump(
        tester,
        sections: [slot(), slot(key: 'bottom')],
        promotions: [promotion(sectionKey: 'top')],
      );

      expect(find.byKey(AdSlotSection.slotKey('top')), findsOneWidget);
      expect(find.byKey(AdSlotSection.slotKey('bottom')), findsNothing);
    });

    testWidgets('a slot shows no more banners than it sells', (tester) async {
      await pump(
        tester,
        sections: [slot(maxAds: 1)],
        promotions: [
          promotion(id: 'p1', priority: 1),
          promotion(id: 'p2', priority: 9, title: 'عرض تاني'),
        ],
      );

      // Whoever paid more for the slot gets it.
      expect(find.text('عرض تاني'), findsOneWidget);
      expect(find.text('خصم النهارده'), findsNothing);
    });
  });

  group('a boost', () {
    testWidgets('lifts the merchant who paid for it', (tester) async {
      await pump(
        tester,
        sections: [merchantList],
        merchants: [merchant('a', name: 'مطعم أ'), merchant('b', name: 'مطعم ب')],
        promotions: [
          promotion(channel: PromotionChannel.boost, merchantId: 'b'),
        ],
      );

      final boosted = tester.getTopLeft(find.text('مطعم ب')).dy;
      final other = tester.getTopLeft(find.text('مطعم أ')).dy;
      expect(boosted, lessThan(other));
    });

    // A boost is a lift, not a badge. Telling customers which merchant paid would make
    // the placement worth less than it cost.
    testWidgets('says nothing about itself on the card', (tester) async {
      await pump(
        tester,
        sections: [merchantList],
        merchants: [merchant('a', name: 'مطعم أ')],
        promotions: [
          promotion(channel: PromotionChannel.boost, merchantId: 'a'),
        ],
      );

      expect(find.textContaining('إعلان'), findsNothing);
      expect(find.textContaining('مموّل'), findsNothing);
    });

    // A boost whose dates have passed is a merchant who stopped paying.
    testWidgets('that has expired lifts nobody', (tester) async {
      await pump(
        tester,
        sections: [merchantList],
        merchants: [merchant('a', name: 'مطعم أ'), merchant('b', name: 'مطعم ب')],
        promotions: [
          promotion(
            channel: PromotionChannel.boost,
            merchantId: 'b',
            startAt: DateTime(2026, 7, 1),
            endAt: DateTime(2026, 8, 1),
          ),
        ],
      );

      final first = tester.getTopLeft(find.text('مطعم أ')).dy;
      final second = tester.getTopLeft(find.text('مطعم ب')).dy;
      expect(first, lessThan(second));
    });
  });

  group('when promotions cannot be read at all', () {
    // One failing feed costs its own block and nothing else. The home is assembled from
    // independent pieces precisely so that a paid placement failing does not take the
    // restaurants down with it.
    testWidgets('the rest of the home still renders', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            clockProvider.overrideWithValue(() => now),
            promotionRepositoryProvider.overrideWithValue(
              FakePromotionRepository(failure: const OfflineFailure()),
            ),
            homeSectionRepositoryProvider.overrideWithValue(
              FakeHomeSectionRepository(seed: [slot(), merchantList]),
            ),
            merchantRepositoryProvider.overrideWithValue(
              FakeMerchantRepository(seed: [merchant('a', name: 'مطعم أ')]),
            ),
            dailyMealRepositoryProvider
                .overrideWithValue(FakeDailyMealRepository()),
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
              child: HomeScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('مطعم أ'), findsOneWidget);
      expect(find.byKey(AdSlotSection.slotKey('top')), findsNothing);
    });
  });
}
