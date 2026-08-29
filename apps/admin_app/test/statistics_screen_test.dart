import 'package:admin_app/src/statistics/statistics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The owner's read on the platform: who is on it and how it is moving.
///
/// Read-only, so the risk here is not a bad write — it is a number that reads as
/// something it is not. Money is integer piastres everywhere in this product, and the
/// average order value is money: a screen that prints it raw shows 15000 where the owner
/// should read 150 ج, and the mistake looks exactly like a very good month.
void main() {
  AdminStatistics stats({
    int customers = 0,
    Map<String, int> merchantsByStatus = const {},
    int ordersTotal = 0,
    int avgOrderValue = 0,
    List<SeriesPoint> byWeek = const [],
    List<SeriesPoint> byMonth = const [],
  }) =>
      AdminStatistics(
        customers: customers,
        merchantsByStatus: merchantsByStatus,
        ordersTotal: ordersTotal,
        avgOrderValue: avgOrderValue,
        byWeek: byWeek,
        byMonth: byMonth,
      );

  Future<void> pump(
    WidgetTester tester, {
    AdminStatistics? value,
    Failure? failure,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(
            FakeAdminRepository(
              statisticsValue: value ?? stats(),
              failure: failure,
            ),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: StatisticsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The text rendered inside one of the big-number tiles.
  String tileText(WidgetTester tester, Key key) => tester
      .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .join(' ');

  testWidgets('the big numbers are the numbers it was given', (tester) async {
    await pump(tester, value: stats(customers: 412, ordersTotal: 1908));

    expect(tileText(tester, StatisticsScreen.customersKey), contains('412'));
    expect(tileText(tester, StatisticsScreen.ordersKey), contains('1908'));
  });

  // The one that would be believed if it were wrong.
  testWidgets('the average order is money, and reads as pounds', (tester) async {
    await pump(tester, value: stats(avgOrderValue: 15000));

    final shown = tileText(tester, StatisticsScreen.averageKey);
    expect(shown, contains('150'),
        reason: 'piastres are the storage unit, never the displayed one');
    expect(shown, isNot(contains('15000')),
        reason: 'a hundredfold error here looks exactly like a very good month');
  });

  testWidgets('merchant statuses are named in Arabic, not in column values',
      (tester) async {
    await pump(tester, value: stats(merchantsByStatus: {
      'pending': 3,
      'approved': 27,
      'suspended': 1,
    }));

    expect(find.text('مستنيين موافقة'), findsOneWidget);
    expect(find.text('معتمدين'), findsOneWidget);
    expect(find.text('موقوفين'), findsOneWidget);
    expect(find.text('27'), findsOneWidget);
  });

  testWidgets('a status nobody has translated still shows its count', (tester) async {
    await pump(tester, value: stats(merchantsByStatus: {'archived': 2}));

    // Falling back to the raw key is right: a status added to the schema and not to this
    // map must not make a row vanish, taking its count with it.
    expect(find.text('archived'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('a launch-day platform says so instead of showing empty boxes',
      (tester) async {
    await pump(tester, value: stats());

    expect(find.text('لسه مفيش مطاعم.'), findsOneWidget);
    expect(find.text('مفيش بيانات لسه.'), findsNWidgets(2),
        reason: 'both series — the weeks and the months — are honestly empty');
  });

  testWidgets('a growth series lists its points', (tester) async {
    await pump(tester, value: stats(byWeek: [
      SeriesPoint(starting: DateTime(2026, 8, 17), count: 12),
      SeriesPoint(starting: DateTime(2026, 8, 24), count: 19),
    ]));

    expect(find.text('12'), findsOneWidget);
    expect(find.text('19'), findsOneWidget);
    expect(find.text('مفيش بيانات لسه.'), findsOneWidget,
        reason: 'the months are still empty, and say so on their own');
  });

  testWidgets('statistics that will not load say so, with a way to try again',
      (tester) async {
    await pump(tester, failure: const OfflineFailure());

    expect(find.byType(LuqmaErrorView), findsOneWidget);
    expect(find.byKey(StatisticsScreen.customersKey), findsNothing,
        reason: 'zeroes on a failed load would read as a platform with nobody on it');
  });
}
