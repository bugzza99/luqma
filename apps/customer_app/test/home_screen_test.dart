import 'package:customer_app/src/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The screen the owner arranges and the customer opens.
void main() {
  const merchants = [
    Merchant(
      id: 'm1',
      cityId: 'edku',
      type: MerchantType.restaurant,
      name: 'مطعم الشاطئ',
      zoneId: 'z1',
      phone: '0100',
      status: MerchantStatus.approved,
      openingHours: [OpeningWindow(weekday: 1, openMinute: 0, closeMinute: 1439)],
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required List<HomeSection> sections,
    List<Merchant> seed = merchants,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeSectionRepositoryProvider
              .overrideWithValue(FakeHomeSectionRepository(seed: sections)),
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: seed)),
          // MerchantCard reads the rating-display threshold off the config, so the
          // config is a real dependency of this screen rather than incidental setup.
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
          cuisineRepositoryProvider.overrideWithValue(
            FakeCuisineRepository(seed: const [
              Cuisine(id: 'c1', cityId: 'edku', name: 'مشويات'),
            ]),
          ),
          // The card asks whether the shop is open, which is a question about the hour.
          clockProvider.overrideWithValue(() => DateTime(2026, 8, 27, 13)),
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

  HomeSection section(String type, {String key = 's', int sortOrder = 0}) =>
      HomeSection(key: key, type: type, sortOrder: sortOrder, cityId: 'edku');

  group('the fixed chrome', () {
    testWidgets('the brand is drawn, never typed', (tester) async {
      await pump(tester, sections: []);

      // Lemonada is not a bundled font, so a Text widget could not render the name
      // correctly even if someone tried. This asserts the asset is what is used.
      expect(find.byType(LuqmaLockup), findsOneWidget);
      expect(find.text('لقمة'), findsNothing);
    });

    testWidgets('the search field is always there, whatever the owner arranged',
        (tester) async {
      await pump(tester, sections: []);
      expect(find.byKey(HomeScreen.searchKey), findsOneWidget);
    });
  });

  group('what the owner arranged', () {
    testWidgets('sections render in their configured order', (tester) async {
      await pump(tester, sections: [
        section('merchantList', key: 'list', sortOrder: 1),
        section('categoryChips', key: 'chips', sortOrder: 0),
      ]);

      // The first cuisine circle, which is what `categoryChips` renders now — it used
      // to be an "all" chip, and the circles clear themselves by being pressed again.
      final chips = tester.getTopLeft(find.text('مشويات')).dy;
      final list = tester.getTopLeft(find.text('مطعم الشاطئ')).dy;
      expect(chips, lessThan(list));
    });

    testWidgets('a hidden section is not drawn', (tester) async {
      await pump(tester, sections: [
        section('categoryChips', key: 'chips'),
        HomeSection(
          key: 'list',
          type: 'merchantList',
          sortOrder: 1,
          isVisible: false,
          cityId: 'edku',
        ),
      ]);

      expect(find.text('مطعم الشاطئ'), findsNothing);
    });

    // The failure this whole boundary exists to contain.
    testWidgets('a section naming a type this build lacks costs only that section',
        (tester) async {
      await pump(tester, sections: [
        section('typoSection', key: 'bad', sortOrder: 0),
        section('merchantList', key: 'list', sortOrder: 1),
      ]);

      expect(find.text('مطعم الشاطئ'), findsOneWidget);
    });

    // A city whose home has not been arranged yet is a real state, not a fault.
    testWidgets('a home with nothing arranged still shows the chrome', (tester) async {
      await pump(tester, sections: []);

      expect(find.byType(LuqmaLockup), findsOneWidget);
      expect(find.byKey(HomeScreen.searchKey), findsOneWidget);
      expect(find.byKey(HomeScreen.emptyKey), findsOneWidget);
    });
  });

  group('merchants', () {
    testWidgets('a closed merchant is shown dimmed rather than hidden',
        (tester) async {
      await pump(
        tester,
        sections: [section('merchantList')],
        seed: const [
          Merchant(
            id: 'm2',
            cityId: 'edku',
            type: MerchantType.restaurant,
            name: 'فراخ الحاج',
            zoneId: 'z1',
            phone: '0100',
            status: MerchantStatus.approved,
            // No opening hours at all: closed right now.
          ),
        ],
      );

      // Hiding it would leave a customer wondering where their usual place went.
      expect(find.text('فراخ الحاج'), findsOneWidget);
      expect(find.text('مقفول دلوقتي'), findsOneWidget);
    });

    testWidgets('a rating is withheld until there are enough of them',
        (tester) async {
      await pump(
        tester,
        sections: [section('merchantList')],
        seed: const [
          Merchant(
            id: 'm3',
            cityId: 'edku',
            type: MerchantType.restaurant,
            name: 'مطعم جديد',
            zoneId: 'z1',
            phone: '0100',
            status: MerchantStatus.approved,
            ratingAvg: 2.0,
            ratingCount: 1,
          ),
        ],
      );

      // One bad review must not sink a new merchant in a town where everyone knows
      // everyone; the default threshold is ten.
      expect(find.text('2.0'), findsNothing);
    });
  });
}
