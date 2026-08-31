import 'package:customer_app/src/home/sections/merchant_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// One merchant, as the customer meets it.
///
/// This is the card the whole home screen is made of, so what it says and what it leaves
/// out is most of what the app feels like. It carries four things — the picture, how good
/// it is, how long it takes and what delivery costs — and deliberately not a fifth.
void main() {
  final openAllWeek = [
    // 1..7, not 0..6. `DateTime.weekday` is Monday 1 through Sunday 7 and never 0, so
    // the obvious range covers Monday to Saturday and leaves every shop in the fixture
    // shut one day in seven — six runs green, and the seventh reads as a flake.
    for (var d = 1; d <= 7; d++)
      OpeningWindow(weekday: d, openMinute: 0, closeMinute: 1439),
  ];

  Merchant shop({
    String name = 'مطعم البحر',
    double ratingAvg = 4.5,
    int ratingCount = 40,
    int prepMinutes = 30,
    int minOrder = 0,
    List<OpeningWindow>? hours,
    String? coverUrl,
  }) =>
      Merchant(
        id: 'm1',
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: name,
        zoneId: 'z1',
        phone: '0100',
        status: MerchantStatus.approved,
        openingHours: hours ?? openAllWeek,
        coverUrl: coverUrl,
        ratingAvg: ratingAvg,
        ratingCount: ratingCount,
        prepMinutes: prepMinutes,
        minOrder: minOrder,
      );

  Future<void> pump(
    WidgetTester tester,
    Merchant merchant, {
    Map<String, Object> config = const {},
    DateTime? now,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher(config))),
          // Never DateTime.now(): whether a shop is open depends on the hour, and a test
          // that cannot move the clock can only be written by waiting for the evening.
          clockProvider.overrideWithValue(
            () => now ?? DateTime(2026, 8, 27, 13),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: MerchantCard(merchant: merchant)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('carries the name and a picture', (tester) async {
    await pump(tester, shop());

    expect(find.text('مطعم البحر'), findsOneWidget);
    expect(find.byType(LuqmaImage), findsOneWidget);
  });

  testWidgets('says how long the kitchen takes', (tester) async {
    await pump(tester, shop(prepMinutes: 25));

    expect(find.textContaining('25'), findsOneWidget);
  });

  group('the rating', () {
    testWidgets('is shown once enough people have rated', (tester) async {
      await pump(tester, shop(ratingAvg: 4.5, ratingCount: 40),
          config: {'min_ratings_to_show': 10});

      expect(find.byKey(MerchantCard.ratingKey), findsOneWidget);
    });

    // Three ratings is one bad evening, and a shop that opened last week should not wear
    // 2.0 in front of the whole city because of it.
    testWidgets('is hidden until then, rather than shown small', (tester) async {
      await pump(tester, shop(ratingAvg: 2.0, ratingCount: 3),
          config: {'min_ratings_to_show': 10});

      expect(find.byKey(MerchantCard.ratingKey), findsNothing);
    });
  });

  group('delivery', () {
    testWidgets('free delivery is said, not left blank', (tester) async {
      await pump(tester, shop());

      expect(find.byKey(MerchantCard.deliveryKey), findsOneWidget);
    });
  });

  // Four numbers on a small card is noise. The minimum is enforced in the basket and
  // stated on the merchant's own screen; the card is for choosing, not for the terms.
  testWidgets('does not carry the minimum order', (tester) async {
    await pump(tester, shop(minOrder: 5000));

    expect(find.textContaining('أقل طلب'), findsNothing);
  });

  group('when it is closed', () {
    // Open for the first minute of Monday only, so at any other moment it is shut.
    final closedNow = [
      const OpeningWindow(weekday: 0, openMinute: 0, closeMinute: 1),
    ];

    testWidgets('says so rather than disappearing', (tester) async {
      await pump(tester, shop(hours: closedNow));

      // Hiding it leaves the customer wondering where their usual place went.
      expect(find.text('مطعم البحر'), findsOneWidget);
      expect(find.byKey(MerchantCard.closedKey), findsOneWidget);
    });

    testWidgets('and is open again when the clock says so', (tester) async {
      await pump(tester, shop(), now: DateTime(2026, 8, 27, 13));

      expect(find.byKey(MerchantCard.closedKey), findsNothing);
    });
  });

  // The card passed `LuqmaImage(url: null)` — a literal, not a value — so a merchant who
  // uploaded a cover and had it approved still got the tinted placeholder. The whole
  // media pipeline worked and nothing the customer runs ever asked for the address.
  group('the shop photograph', () {
    testWidgets('an approved cover is what the card draws', (tester) async {
      await pump(tester, shop(coverUrl: 'https://example.test/cover.jpg'));

      final image = tester.widget<LuqmaImage>(find.byType(LuqmaImage));
      expect(image.url, 'https://example.test/cover.jpg');
    });

    // Null covers "never uploaded", "still in the queue" and "refused" alike — a
    // customer cannot act on the difference, and `LuqmaImage` draws the mark from the
    // shop's name rather than a broken frame.
    testWidgets('and no picture is still a card, not a gap', (tester) async {
      await pump(tester, shop());

      final image = tester.widget<LuqmaImage>(find.byType(LuqmaImage));
      expect(image.url, isNull);
      expect(find.byType(LuqmaImage), findsOneWidget);
    });
  });
}
