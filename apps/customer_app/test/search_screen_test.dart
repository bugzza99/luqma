import 'dart:async';

import 'package:customer_app/src/home/sections/merchant_card.dart';
import 'package:customer_app/src/search/search_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Looking for something to eat.
///
/// `docs/04` decided against a categories tab because thirty merchants cannot fill one
/// and "search covers the rest". The box then shipped read-only with an empty onTap — so
/// the tab was removed and nothing took its place. This is the thing that takes its
/// place, and these are the properties it has to have to actually do that job.
void main() {
  final openAllWeek = [
    for (var d = 0; d < 7; d++)
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

  MenuItem dish(String id, String merchantId, String name) => MenuItem(
        id: id,
        merchantId: merchantId,
        categoryId: 'c1',
        name: name,
        price: 12000,
      );

  Future<void> pump(
    WidgetTester tester, {
    Failure? failure,
    Completer<void>? gate,
  }) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          searchRepositoryProvider.overrideWithValue(
            FakeSearchRepository(
              failure: failure,
              gate: gate,
              merchants: [shop('m1', 'مطعم البحر'), shop('m2', 'كشري الأمير')],
              menus: {
                'm1': [dish('i1', 'm1', 'سمك مشوي')],
                'm2': [dish('i2', 'm2', 'كشري بالعدس')],
              },
            ),
          ),
          cuisineRepositoryProvider.overrideWithValue(
            FakeCuisineRepository(seed: const [
              Cuisine(id: 'c1', cityId: 'edku', name: 'مشويات'),
            ]),
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
            child: SearchScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Types [text] and lets the debounce elapse.
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(SearchScreen.fieldKey), text);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on a prompt, not an empty list', (tester) async {
    await pump(tester);

    expect(find.byKey(SearchScreen.emptyKey), findsOneWidget);
  });

  testWidgets('finds a shop by name', (tester) async {
    await pump(tester);
    await type(tester, 'البحر');

    expect(find.byType(MerchantCard), findsOneWidget);
    expect(find.text('مطعم البحر'), findsWidgets);
  });

  // The reason this searches dishes at all: somebody typing here wants food, not a
  // building. "كشري" has to find whoever makes it.
  testWidgets('finds a dish, and says which shop makes it', (tester) async {
    await pump(tester);
    await type(tester, 'سمك');

    expect(find.byKey(SearchScreen.dishesKey), findsOneWidget);
    expect(find.text('سمك مشوي'), findsOneWidget);
    expect(find.text('مطعم البحر'), findsWidgets,
        reason: 'a dish with no shop beside it cannot be acted on');
  });

  testWidgets('shops and dishes stay in separate lists', (tester) async {
    await pump(tester);
    await type(tester, 'كشري');

    // "كشري الأمير" the shop, and "كشري بالعدس" the dish — two answers to two
    // questions, and interleaving them makes the customer sort them out by eye.
    expect(find.byKey(SearchScreen.merchantsKey), findsOneWidget);
    expect(find.byKey(SearchScreen.dishesKey), findsOneWidget);
  });

  testWidgets('says plainly when there is nothing', (tester) async {
    await pump(tester);
    await type(tester, 'بيتزا');

    expect(find.byKey(SearchScreen.noResultsKey), findsOneWidget);
    expect(find.textContaining('بيتزا'), findsWidgets,
        reason: 'saying what was not found beats a bare shrug');
  });

  testWidgets('clearing it goes back to the prompt', (tester) async {
    await pump(tester);
    await type(tester, 'البحر');
    await type(tester, '');

    expect(find.byKey(SearchScreen.emptyKey), findsOneWidget);
  });

  // Errors are never a dead end in this product — LuqmaErrorView is the only error state
  // in all three apps and it always takes a way out.
  testWidgets('a failed search offers another go', (tester) async {
    await pump(tester, failure: const OfflineFailure());
    await type(tester, 'البحر');

    expect(find.byType(LuqmaErrorView), findsOneWidget);
  });

  // A response for a query the customer has already deleted.
  //
  // `_run` guards on `query != _lastQuery` to drop a stale answer, and clearing the box
  // cancelled the debounce and emptied the list — but left `_lastQuery` set. So a search
  // already in the air passed that guard when it landed and repopulated the results
  // under an empty box, with nothing to explain where they came from.
  testWidgets('clearing the box also discards what is already in the air',
      (tester) async {
    final gate = Completer<void>();
    await pump(tester, gate: gate);

    await tester.enterText(find.byKey(SearchScreen.fieldKey), 'كشري');
    await tester.pump(const Duration(milliseconds: 400));

    // The request is out and waiting on the gate. Now the customer clears the box.
    await tester.enterText(find.byKey(SearchScreen.fieldKey), '');
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(MerchantCard), findsNothing);
    expect(find.byKey(SearchScreen.emptyKey), findsOneWidget);
  });
}
