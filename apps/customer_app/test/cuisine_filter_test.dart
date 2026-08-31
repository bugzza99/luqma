import 'package:customer_app/src/home/sections/category_chips_section.dart';
import 'package:customer_app/src/home/sections/merchant_tile.dart';
import 'package:customer_app/src/home/sections/merchant_list_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Pressing a cuisine circle narrows the list of merchants.
///
/// The two halves of this live in different sections — the circles are `categoryChips`,
/// the list is `merchantList` — and the home builds each from a registry, independently,
/// in whatever order the admin arranged them. Neither can reach the other, so the filter
/// is a provider they both read.
///
/// This test is the reason that provider exists rather than a field smuggled into one of
/// the two sections: it renders both, the way the home does, and presses one.
void main() {
  final openAllWeek = [
    // 1..7, not 0..6. `DateTime.weekday` is Monday 1 through Sunday 7 and never 0, so
    // the obvious range covers Monday to Saturday and leaves every shop in the fixture
    // shut one day in seven — six runs green, and the seventh reads as a flake.
    for (var d = 1; d <= 7; d++)
      OpeningWindow(weekday: d, openMinute: 0, closeMinute: 1439),
  ];

  Merchant shop(String id, String name) => Merchant(
        id: id,
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: name,
        zoneId: 'z1',
        phone: '0100',
        status: MerchantStatus.approved,
        openingHours: openAllWeek,
      );

  const grill = Cuisine(id: 'c1', cityId: 'edku', name: 'مشويات');
  const fish = Cuisine(id: 'c2', cityId: 'edku', name: 'أسماك');

  const section = HomeSection(
    key: 'list',
    type: 'merchantList',
    sortOrder: 0,
    cityId: 'edku',
  );
  const chips = HomeSection(
    key: 'chips',
    type: 'categoryChips',
    sortOrder: 0,
    cityId: 'edku',
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantRepositoryProvider.overrideWithValue(
            FakeMerchantRepository(seed: [
              shop('m1', 'مطعم البحر'),
              shop('m2', 'كشري الأمير'),
            ]),
          ),
          cuisineRepositoryProvider.overrideWithValue(
            FakeCuisineRepository(
              seed: const [grill, fish],
              // Only the first shop is grilled meat.
              members: {'c1': {'m1'}, 'c2': {}},
            ),
          ),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
          clockProvider.overrideWithValue(() => DateTime(2026, 8, 27, 13)),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Column(
                children: [
                  CategoryChipsSection(section: chips),
                  Expanded(child: SingleChildScrollView(
                    child: MerchantListSection(section: section),
                  )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the circles are the cuisines, not four compiled-in words',
      (tester) async {
    await pump(tester);

    expect(find.text('مشويات'), findsOneWidget);
    expect(find.text('أسماك'), findsOneWidget);
  });

  testWidgets('everything shows until a circle is pressed', (tester) async {
    await pump(tester);

    expect(find.byType(MerchantTile), findsNWidgets(2));
  });

  testWidgets('pressing one narrows the list', (tester) async {
    await pump(tester);

    await tester.tap(find.text('مشويات'));
    await tester.pumpAndSettle();

    expect(find.byType(MerchantTile), findsOneWidget);
    expect(find.text('مطعم البحر'), findsOneWidget);
  });

  // The same gesture in and out, so nobody has to hunt for a separate "all" to escape a
  // filter they did not mean to press.
  testWidgets('pressing it again releases it', (tester) async {
    await pump(tester);

    await tester.tap(find.text('مشويات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مشويات'));
    await tester.pumpAndSettle();

    expect(find.byType(MerchantTile), findsNWidgets(2));
  });

  // Empty and "no filter" are different answers. Collapsing them would show the whole
  // city under a circle that should have been empty.
  testWidgets('a cuisine with nobody in it shows nobody', (tester) async {
    await pump(tester);

    await tester.tap(find.text('أسماك'));
    await tester.pumpAndSettle();

    expect(find.byType(MerchantTile), findsNothing);
  });
}
