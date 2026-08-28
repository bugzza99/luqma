import 'package:admin_app/src/cuisines/cuisines_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// الأقسام — the circles across the top of the customer's home.
///
/// Admin-only by design, and the reason is worth restating: a merchant who could tag
/// itself into a circle it does not belong in would have the cheapest promotion in the
/// product. So this screen is the only way a cuisine comes to exist, and it had no tests.
void main() {
  Cuisine cuisine({
    String id = 'c1',
    String name = 'مشويات',
    int sortOrder = 0,
  }) =>
      Cuisine(id: id, cityId: 'edku', name: name, sortOrder: sortOrder);

  late FakeCuisineRepository cuisines;

  Future<void> pump(
    WidgetTester tester, {
    List<Cuisine> seed = const [],
    Failure? failure,
  }) async {
    // A phone, not the runner's 800x600: that window is wider than it is tall and unlike
    // any device this ships on, and it has hidden real overflow in this project before.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    cuisines = FakeCuisineRepository(seed: seed, failure: failure);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [cuisineRepositoryProvider.overrideWithValue(cuisines)],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: CuisinesScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('with nothing yet, it says what these are for', (tester) async {
    await pump(tester);

    expect(find.byKey(CuisinesScreen.emptyKey), findsOneWidget);
    // An empty list that only says "empty" leaves the owner guessing what to type.
    expect(find.textContaining('الدواير'), findsOneWidget);
  });

  testWidgets('the cuisines that exist are listed', (tester) async {
    await pump(tester, seed: [
      cuisine(id: 'c1', name: 'مشويات'),
      cuisine(id: 'c2', name: 'كشري'),
    ]);

    expect(find.byKey(CuisinesScreen.rowKey), findsNWidgets(2));
    expect(find.text('مشويات'), findsOneWidget);
    expect(find.text('كشري'), findsOneWidget);
    expect(find.byKey(CuisinesScreen.emptyKey), findsNothing);
  });

  testWidgets('a list that will not load says so, with a way to try again',
      (tester) async {
    await pump(tester, failure: const OfflineFailure());

    expect(find.byType(LuqmaErrorView), findsOneWidget,
        reason: 'an empty screen and an unreachable one are not the same thing');
    expect(find.byKey(CuisinesScreen.emptyKey), findsNothing,
        reason: 'and it must not read as "there are none yet"');
  });

  testWidgets('a new cuisine is written through the repository', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(CuisinesScreen.addKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'حلويات');
    await tester.tap(find.text('احفظ'));
    await tester.pumpAndSettle();

    expect(cuisines.all.map((c) => c.name), contains('حلويات'));
    expect(find.text('حلويات'), findsOneWidget,
        reason: 'the list refreshes rather than waiting for the screen to be reopened');
  });

  testWidgets('a cuisine with no name is refused', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(CuisinesScreen.addKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '   ');
    await tester.tap(find.text('احفظ'));
    await tester.pumpAndSettle();

    expect(cuisines.all, isEmpty,
        reason: 'a nameless circle on the home screen is a tap into nothing');
    expect(find.text('احفظ'), findsOneWidget, reason: 'the sheet stays open to be fixed');
  });

  testWidgets('tapping one opens it with its name already in the field',
      (tester) async {
    await pump(tester, seed: [cuisine(id: 'c1', name: 'مشويات')]);

    await tester.tap(find.byKey(CuisinesScreen.rowKey));
    await tester.pumpAndSettle();

    final field = tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(field.initialValue, 'مشويات',
        reason: 'editing starts from what is there, not from a blank field');
  });

  testWidgets('a save that fails keeps the sheet open and says why', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(CuisinesScreen.addKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'حلويات');

    cuisines.failure = const OfflineFailure();
    await tester.tap(find.text('احفظ'));
    await tester.pumpAndSettle();

    // Closing on a failure would tell the owner it saved. They would find out it had not
    // the next time they opened the screen, having typed it once already.
    expect(find.text('احفظ'), findsOneWidget);
  });
}
