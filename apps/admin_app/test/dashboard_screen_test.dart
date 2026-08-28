import 'package:admin_app/src/dashboard/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// النهارده — the four numbers the owner opens the app to read.
///
/// It used to be where an admin landed; it is a module inside the grid now, which makes
/// it somewhere they go on purpose. Either way it is read-only, so the risk is not a bad
/// write — it is a number that reads as something it is not, and the takings for the day
/// are the number most likely to be believed without checking.
void main() {
  AdminToday today({
    int ordersToday = 0,
    int moneyToday = 0,
    int openIssues = 0,
    List<NeedsAttentionItem> needsAttention = const [],
  }) =>
      AdminToday(
        ordersToday: ordersToday,
        moneyToday: moneyToday,
        needsAttention: needsAttention,
        openIssues: openIssues,
      );

  NeedsAttentionItem waiting({
    String id = 'o1',
    int number = 104,
    String merchantName = 'مطعم البحر',
  }) =>
      NeedsAttentionItem(
        id: id,
        number: number,
        merchantId: 'm1',
        merchantName: merchantName,
      );

  Future<void> pump(
    WidgetTester tester, {
    AdminToday? value,
    Failure? failure,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(
            FakeAdminRepository(todayValue: value ?? today(), failure: failure),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: DashboardScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String tileText(WidgetTester tester, Key key) => tester
      .widgetList<Text>(find.descendant(of: find.byKey(key), matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .join(' ');

  testWidgets('the day\'s counts are the counts it was given', (tester) async {
    await pump(tester, value: today(ordersToday: 37, openIssues: 4));

    expect(tileText(tester, DashboardScreen.ordersKey), contains('37'));
    expect(tileText(tester, DashboardScreen.issuesKey), contains('4'));
  });

  // Money is integer piastres everywhere in this product, and this is the figure an
  // owner reads at the end of a day and repeats to somebody. Printed raw it reads as a
  // hundred times the takings, and nothing about the screen would look wrong.
  testWidgets('the day\'s takings read as pounds, not piastres', (tester) async {
    await pump(tester, value: today(moneyToday: 452500));

    final shown = tileText(tester, DashboardScreen.moneyKey);
    expect(shown, contains('4525'));
    expect(shown, isNot(contains('452500')));
  });

  testWidgets('a quiet moment says so rather than showing an empty space',
      (tester) async {
    await pump(tester, value: today(ordersToday: 12));

    expect(find.text('مفيش حاجة محتاجة تدخل دلوقتي.'), findsOneWidget);
    expect(find.byKey(DashboardScreen.needsAttentionKey), findsNothing);
  });

  testWidgets('orders nobody answered are listed with their shop', (tester) async {
    await pump(tester, value: today(needsAttention: [
      waiting(id: 'o1', number: 104, merchantName: 'مطعم البحر'),
      waiting(id: 'o2', number: 105, merchantName: 'كشري التحرير'),
    ]));

    expect(find.byKey(DashboardScreen.needsAttentionKey), findsNWidgets(2));
    expect(find.text('أوردر #104'), findsOneWidget);
    // The shop's name beside the number is what makes the row actionable — an order
    // number alone tells the owner nothing about who to ring.
    expect(find.text('مطعم البحر'), findsOneWidget);
    expect(find.text('كشري التحرير'), findsOneWidget);
    expect(find.text('مفيش حاجة محتاجة تدخل دلوقتي.'), findsNothing);
  });

  testWidgets('a day that will not load says so, with a way to try again',
      (tester) async {
    await pump(tester, failure: const OfflineFailure());

    expect(find.byType(LuqmaErrorView), findsOneWidget);
    // Zeroes on a failed load are the dangerous outcome here: they read as a quiet day,
    // which is a thing that genuinely happens, so nobody would question them.
    expect(find.byKey(DashboardScreen.ordersKey), findsNothing);
    expect(find.byKey(DashboardScreen.moneyKey), findsNothing);
  });
}
