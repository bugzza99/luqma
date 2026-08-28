import 'package:customer_app/src/home/home_screen.dart';
import 'package:customer_app/src/home/sections/home_kitchen_section.dart';
import 'package:customer_app/src/kitchen/meal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// أكل بيتي — the part of this product nobody else in Edku offers.
///
/// A restaurant list is table stakes. This is the reason somebody opens the app on a
/// Tuesday, and every decision below follows from one fact: a fixed number of portions
/// was cooked once, and when they are gone they are gone.
void main() {
  const today = '2026-08-23';
  // Inside the collection window, so "can this still be reserved" is a question about
  // the meal rather than about what time the suite happens to run.
  final now = DateTime(2026, 8, 23, 11);

  DailyMeal meal({
    String id = 'd1',
    String name = 'محشي كرنب',
    int remainingQty = 8,
    int totalQty = 20,
    String date = today,
    DailyMealStatus status = DailyMealStatus.published,
    DeliveryOption deliveryOption = DeliveryOption.pickup,
  }) =>
      DailyMeal(
        id: id,
        merchantId: 'm1',
        cityId: 'edku',
        name: name,
        description: 'اتعمل النهارده الصبح',
        price: 9000,
        date: date,
        totalQty: totalQty,
        remainingQty: remainingQty,
        pickupWindowStart: 13 * 60,
        pickupWindowEnd: 16 * 60,
        deliveryOption: deliveryOption,
        status: status,
      );

  const kitchen = Merchant(
    id: 'm1',
    cityId: 'edku',
    type: MerchantType.homeKitchen,
    name: 'مطبخ أم أحمد',
    zoneId: 'z1',
    phone: '01000000000',
    status: MerchantStatus.approved,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    List<DailyMeal> meals = const [],
    List<HomeSection> sections = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clockProvider.overrideWithValue(() => now),
          dailyMealRepositoryProvider
              .overrideWithValue(FakeDailyMealRepository(seed: meals)),
          merchantRepositoryProvider
              .overrideWithValue(FakeMerchantRepository(seed: const [kitchen])),
          homeSectionRepositoryProvider
              .overrideWithValue(FakeHomeSectionRepository(seed: sections)),
          remoteConfigServiceProvider
              .overrideWithValue(RemoteConfigService(FakeConfigFetcher({}))),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: Directionality(textDirection: TextDirection.rtl, child: screen),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const section = [
    HomeSection(
      key: 'kitchen',
      type: 'homeKitchenToday',
      sortOrder: 0,
      cityId: 'edku',
    ),
  ];

  group('the section on the home screen', () {
    testWidgets('shows today\'s meals', (tester) async {
      await pump(tester, const HomeScreen(), sections: section, meals: [meal()]);

      expect(find.text('محشي كرنب'), findsOneWidget);
    });

    // A day with no home cooking should not mention it at all. An empty band with a
    // heading reads as something broken.
    testWidgets('a day with none is not mentioned', (tester) async {
      await pump(tester, const HomeScreen(), sections: section);

      expect(find.textContaining('أكل بيتي'), findsNothing);
    });

    testWidgets('yesterday\'s meal is not today\'s', (tester) async {
      await pump(
        tester,
        const HomeScreen(),
        sections: section,
        meals: [meal(date: '2026-08-22')],
      );

      expect(find.text('محشي كرنب'), findsNothing);
    });

    // The two facts that decide whether somebody taps.
    testWidgets('each card says how many are left and when to collect',
        (tester) async {
      await pump(tester, const HomeScreen(), sections: section, meals: [meal()]);

      expect(find.byKey(MealCard.portionsKey('d1')), findsOneWidget);
      expect(find.byKey(MealCard.windowKey('d1')), findsOneWidget);
    });

    // "خلص" is information: it is what teaches somebody to order earlier tomorrow.
    // Dropping the card would make the whole section look like it was never there.
    testWidgets('a sold-out meal stays, marked', (tester) async {
      await pump(
        tester,
        const HomeScreen(),
        sections: section,
        meals: [meal(remainingQty: 0)],
      );

      expect(find.text('محشي كرنب'), findsOneWidget);
      expect(find.byKey(MealCard.soldOutKey('d1')), findsOneWidget);
    });
  });

  group('one meal', () {
    testWidgets('says who cooked it', (tester) async {
      await pump(tester, const MealScreen(mealId: 'd1'), meals: [meal()]);

      expect(find.text('مطبخ أم أحمد'), findsWidgets);
    });

    testWidgets('says how many are left and the collection window', (tester) async {
      await pump(tester, const MealScreen(mealId: 'd1'), meals: [meal()]);

      expect(find.byKey(MealScreen.portionsKey), findsOneWidget);
      expect(find.textContaining('1:00'), findsWidgets);
    });

    testWidgets('can be reserved while portions are left', (tester) async {
      await pump(
        tester,
        MealScreen(mealId: 'd1', onReserve: (_, _) {}),
        meals: [meal()],
      );

      final button = tester.widget<FilledButton>(
        find.byKey(MealScreen.reserveKey),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('cannot be reserved once it is gone', (tester) async {
      await pump(
        tester,
        MealScreen(mealId: 'd1', onReserve: (_, _) {}),
        meals: [meal(remainingQty: 0)],
      );

      final button = tester.widget<FilledButton>(
        find.byKey(MealScreen.reserveKey),
      );
      expect(button.onPressed, isNull);
    });

    // Nobody can reserve more than exists, so the stepper stops where the count does.
    testWidgets('cannot reserve more portions than are left', (tester) async {
      await pump(
        tester,
        const MealScreen(mealId: 'd1'),
        meals: [meal(remainingQty: 2)],
      );

      await tester.tap(find.byKey(MealScreen.moreKey));
      await tester.tap(find.byKey(MealScreen.moreKey));
      await tester.tap(find.byKey(MealScreen.moreKey));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsWidgets);
    });

    testWidgets('the price follows how many', (tester) async {
      await pump(tester, const MealScreen(mealId: 'd1'), meals: [meal()]);

      await tester.tap(find.byKey(MealScreen.moreKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('180 ج'), findsWidgets);
    });
  });

  group('how it reaches them', () {
    testWidgets('pickup says so plainly', (tester) async {
      await pump(tester, const MealScreen(mealId: 'd1'), meals: [meal()]);

      expect(find.byKey(MealScreen.fulfilmentKey), findsOneWidget);
      expect(find.textContaining('تستلمه'), findsWidgets);
    });

    // The seller and the customer sorting it out between themselves happens here.
    // Pretending it does not would only move it outside the app, where nobody can help.
    testWidgets('an arrangement with the seller says that instead', (tester) async {
      await pump(
        tester,
        const MealScreen(mealId: 'd1'),
        meals: [meal(deliveryOption: DeliveryOption.sellerArrangement)],
      );

      expect(find.byKey(MealScreen.fulfilmentKey), findsOneWidget);
      expect(find.textContaining('تستلمه'), findsNothing);
    });
  });

  group('a meal that is gone', () {
    testWidgets('an id that does not exist says so rather than spinning',
        (tester) async {
      await pump(tester, const MealScreen(mealId: 'missing'));

      expect(find.byKey(MealScreen.errorKey), findsOneWidget);
    });
  });
}
