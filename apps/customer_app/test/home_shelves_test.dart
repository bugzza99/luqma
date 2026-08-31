import 'package:customer_app/src/home/see_all_screen.dart';
import 'package:customer_app/src/home/sections/item_tile.dart';
import 'package:customer_app/src/home/sections/merchant_list_section.dart';
import 'package:customer_app/src/home/sections/merchant_tile.dart';
import 'package:customer_app/src/home/sections/popular_items_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// What the customer's home is made of, after it stopped being a column of big cards.
///
/// Two changes, and they answer two different complaints. Shops are half-width tiles, so
/// six fit on a screen instead of two — a list of forty that only ever showed its first
/// two is a list nobody reaches the end of. And "الأكتر طلباً" is food rather than shops:
/// it used to be a second copy of the merchant list sorted by review count, which is not
/// ordering, under a heading that promised otherwise.
void main() {
  final openAllWeek = [
    // 1..7, never 0..6: `DateTime.weekday` is Monday 1 through Sunday 7, so the obvious
    // range leaves the fixture shut one day in seven.
    for (var d = 1; d <= 7; d++)
      OpeningWindow(weekday: d, openMinute: 0, closeMinute: 1439),
  ];

  Merchant shop(String id, String name, {String? description}) => Merchant(
        id: id,
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: name,
        description: description,
        zoneId: 'z1',
        phone: '0100',
        status: MerchantStatus.approved,
        openingHours: openAllWeek,
        ratingAvg: 4.5,
        ratingCount: 40,
      );

  MenuItem dish(
    String id,
    String name, {
    int price = 5000,
    int ordered = 0,
    String? merchantName,
  }) =>
      MenuItem(
        id: id,
        merchantId: 'm1',
        categoryId: 'c1',
        name: name,
        price: price,
        orderedCount: ordered,
        merchantName: merchantName,
      );

  const merchantList = HomeSection(
    key: 'list',
    type: 'merchantList',
    sortOrder: 0,
    cityId: 'edku',
  );
  const popular = HomeSection(
    key: 'popular',
    type: 'mostOrdered',
    sortOrder: 0,
    cityId: 'edku',
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    List<Merchant> merchants = const [],
    List<MenuItem> items = const [],
    Failure? itemsFailure,
  }) async {
    // A phone's shape, not the 800x600 default: the grid is two across at a phone's
    // width, and a wider-than-tall window is not a device this ships on.
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: merchants)),
          popularItemsRepositoryProvider.overrideWithValue(
            FakePopularItemsRepository(items: items, failure: itemsFailure),
          ),
          promotionRepositoryProvider
              .overrideWithValue(FakePromotionRepository()),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the shops shelf', () {
    testWidgets('two shops sit side by side rather than stacked', (tester) async {
      await pump(
        tester,
        const MerchantListSection(section: merchantList),
        merchants: [shop('m1', 'مطعم أ'), shop('m2', 'مطعم ب')],
      );

      final first = tester.getCenter(find.byKey(MerchantTile.tileKey('m1')));
      final second = tester.getCenter(find.byKey(MerchantTile.tileKey('m2')));

      expect(first.dy, second.dy, reason: 'same row');
      expect(first.dx, isNot(second.dx), reason: 'different columns');
    });

    // What a customer chooses on, in the space a tile has: whose shop it is, whether it
    // is any good, and what kind of food it sells.
    testWidgets('a shop says what it is', (tester) async {
      await pump(
        tester,
        const MerchantListSection(section: merchantList),
        merchants: [shop('m1', 'مطعم أ', description: 'مشويات وحلويات')],
      );

      expect(find.text('مطعم أ'), findsOneWidget);
      expect(find.byKey(MerchantTile.descriptionKey), findsOneWidget);
      expect(find.byKey(MerchantTile.ratingKey), findsOneWidget);
    });

    // A section showing six of forty shops with no way through is a screen that hides
    // its own contents.
    testWidgets('the heading opens the whole list', (tester) async {
      await pump(
        tester,
        const MerchantListSection(section: merchantList),
        merchants: [shop('m1', 'مطعم أ')],
      );

      await tester.tap(find.text('شوف الكل'));
      await tester.pumpAndSettle();

      expect(find.byType(SeeAllScreen), findsOneWidget);
      expect(find.byKey(SeeAllScreen.gridKey), findsOneWidget);
    });
  });

  group('the most-ordered shelf', () {
    testWidgets('shows dishes, not shops', (tester) async {
      await pump(
        tester,
        const PopularItemsSection(section: popular),
        items: [dish('i1', 'فراخ مشوية', ordered: 9, merchantName: 'مطعم أ')],
      );

      expect(find.byKey(ItemTile.tileKey('i1')), findsOneWidget);
      expect(find.text('فراخ مشوية'), findsOneWidget);
      expect(find.byType(MerchantTile), findsNothing);
    });

    // A dish on a shelf drawn from every shop in the city is a tap into somewhere the
    // customer did not choose unless it says whose food it is.
    testWidgets('and says which shop each one came from', (tester) async {
      await pump(
        tester,
        const PopularItemsSection(section: popular),
        items: [dish('i1', 'فراخ مشوية', merchantName: 'مطعم أ')],
      );

      expect(find.byKey(ItemTile.shopKey), findsOneWidget);
      expect(find.text('مطعم أ'), findsOneWidget);
    });

    testWidgets('most ordered comes first', (tester) async {
      await pump(
        tester,
        const PopularItemsSection(section: popular),
        items: [
          dish('quiet', 'صنف هادي', ordered: 1),
          dish('busy', 'صنف مطلوب', ordered: 30),
        ],
      );

      final order = tester
          .widgetList<ItemTile>(find.byType(ItemTile))
          .map((tile) => tile.item.id)
          .toList();

      expect(order, ['busy', 'quiet']);
    });

    // The home is assembled from independent pieces precisely so one failing feed costs
    // its own block and nothing else.
    testWidgets('a shelf that cannot be read is simply absent', (tester) async {
      await pump(
        tester,
        const PopularItemsSection(section: popular),
        itemsFailure: const OfflineFailure(),
      );

      expect(find.byType(ItemTile), findsNothing);
      expect(find.byType(LuqmaErrorView), findsNothing);
    });
  });
}
