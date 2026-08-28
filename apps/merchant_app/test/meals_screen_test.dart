import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/meals/meals_screen.dart';

/// Publishing today's meal.
///
/// Somebody cooked a fixed number of portions this morning. This screen is where they
/// say what it is, how many, and when it can be collected — and nothing else, because
/// they are doing it with one hand.
void main() {
  final now = DateTime(2026, 8, 23, 9);
  const today = '2026-08-23';

  DailyMeal meal({
    String id = 'd1',
    String name = 'محشي كرنب',
    String date = today,
    int remainingQty = 8,
    DailyMealStatus status = DailyMealStatus.published,
  }) =>
      DailyMeal(
        id: id,
        merchantId: 'm1',
        cityId: 'edku',
        name: name,
        price: 9000,
        date: date,
        totalQty: 20,
        remainingQty: remainingQty,
        pickupWindowStart: 13 * 60,
        pickupWindowEnd: 16 * 60,
        status: status,
      );

  late FakeDailyMealRepository meals;

  Future<void> pump(
    WidgetTester tester, {
    List<DailyMeal> seed = const [],
    Failure? failure,
  }) async {
    meals = FakeDailyMealRepository(seed: seed, failure: failure);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          authServiceProvider.overrideWithValue(
            FakeAuthService(
              restoring: const LuqmaIdentity(
                uid: 'cook1',
                claims: {'role': 'owner', 'scope': 'merchant', 'merchantId': 'm1'},
              ),
            ),
          ),
          dailyMealRepositoryProvider.overrideWithValue(meals),
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
            child: MealsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('what a cook sees', () {
    testWidgets('today\'s meal, with what is left of it', (tester) async {
      await pump(tester, seed: [meal()]);

      expect(find.text('محشي كرنب'), findsOneWidget);
      expect(find.byKey(MealsScreen.remainingKey('d1')), findsOneWidget);
    });

    // Yesterday's is history, not a mistake to correct. It stays, below today's.
    testWidgets('yesterday\'s below today\'s', (tester) async {
      await pump(tester, seed: [
        meal(id: 'old', name: 'ملوخية', date: '2026-08-22'),
        meal(),
      ]);

      final today = tester.getTopLeft(find.text('محشي كرنب')).dy;
      final yesterday = tester.getTopLeft(find.text('ملوخية')).dy;
      expect(today, lessThan(yesterday));
    });

    testWidgets('a day with nothing published invites one', (tester) async {
      await pump(tester);

      expect(find.byKey(MealsScreen.emptyKey), findsOneWidget);
      expect(find.byKey(MealsScreen.addKey), findsOneWidget);
    });

    testWidgets('a failed read never looks like a day off', (tester) async {
      await pump(tester, failure: const OfflineFailure());

      expect(find.byKey(MealsScreen.errorKey), findsOneWidget);
      expect(find.byKey(MealsScreen.emptyKey), findsNothing);
    });
  });

  group('publishing one', () {
    Future<void> fillIn(WidgetTester tester) async {
      await tester.enterText(find.byKey(MealsScreen.nameKey), 'ورق عنب');
      await tester.enterText(find.byKey(MealsScreen.priceKey), '75');
      await tester.enterText(find.byKey(MealsScreen.quantityKey), '15');
    }

    testWidgets('a new meal is for today by default', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MealsScreen.addKey));
      await tester.pumpAndSettle();
      await fillIn(tester);
      await tester.tap(find.byKey(MealsScreen.saveKey));
      await tester.pumpAndSettle();

      final saved = meals.all.single;
      expect(saved.name, 'ورق عنب');
      expect(saved.date, today);
      // Cooked already, so both counts start the same.
      expect(saved.totalQty, 15);
      expect(saved.remainingQty, 15);
    });

    testWidgets('the price is read as pounds and stored as piastres',
        (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MealsScreen.addKey));
      await tester.pumpAndSettle();
      await fillIn(tester);
      await tester.tap(find.byKey(MealsScreen.saveKey));
      await tester.pumpAndSettle();

      expect(meals.all.single.price, 7500);
    });

    // A meal with no portions is not a meal, and a meal with no price is one somebody
    // will be arguing about at the door.
    testWidgets('refuses a meal with nothing in it', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MealsScreen.addKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MealsScreen.saveKey));
      await tester.pumpAndSettle();

      expect(meals.all, isEmpty);
    });

    testWidgets('refuses a quantity of zero', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MealsScreen.addKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(MealsScreen.nameKey), 'ورق عنب');
      await tester.enterText(find.byKey(MealsScreen.priceKey), '75');
      await tester.enterText(find.byKey(MealsScreen.quantityKey), '0');
      await tester.tap(find.byKey(MealsScreen.saveKey));
      await tester.pumpAndSettle();

      expect(meals.all, isEmpty);
    });
  });

  group('taking one down early', () {
    testWidgets('closes it without touching what is left', (tester) async {
      await pump(tester, seed: [meal()]);

      await tester.tap(find.byKey(MealsScreen.closeKey('d1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MealsScreen.confirmCloseKey));
      await tester.pumpAndSettle();

      expect(meals['d1']!.status, DailyMealStatus.closed);
      expect(meals['d1']!.remainingQty, 8);
    });

    // Somebody who has sold ten of twenty and is closing up is throwing away sales.
    // Once is enough to ask.
    testWidgets('asks first', (tester) async {
      await pump(tester, seed: [meal()]);

      await tester.tap(find.byKey(MealsScreen.closeKey('d1')));
      await tester.pumpAndSettle();

      expect(find.byKey(MealsScreen.confirmCloseKey), findsOneWidget);
      expect(meals['d1']!.status, DailyMealStatus.published);
    });

    testWidgets('a closed meal offers no close button', (tester) async {
      await pump(tester, seed: [meal(status: DailyMealStatus.closed)]);

      expect(find.byKey(MealsScreen.closeKey('d1')), findsNothing);
    });
  });
}
