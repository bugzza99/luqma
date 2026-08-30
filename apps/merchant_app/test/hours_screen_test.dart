import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/shop/hours_screen.dart';

/// مواعيد الشغل — the merchant setting when their own shop is open.
///
/// `merchants.opening_hours` has existed since the first schema and **no screen in any of
/// the three apps could write it**. Whether a shop takes orders is derived from those
/// hours, so a merchant whose hours were wrong — or empty — was shut with no way to open,
/// and the busy toggle correctly offered nothing because the schedule is not a thing a
/// pause can override.
///
/// The weekday numbers are the other half of it. `OpeningWindow.contains` matches
/// `DateTime.weekday`, which counts Monday=1 to Sunday=7 — a window written as `0` is
/// matched by nothing at all, and the seeded data said `0..6`, so every shop was shut on
/// Sundays and carried one dead entry.
void main() {
  const merchantId = 'm1';

  Merchant shop({List<OpeningWindow> hours = const []}) => Merchant(
        id: merchantId,
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: 'مطعم الشاطئ',
        zoneId: 'z1',
        phone: '01000000000',
        status: MerchantStatus.approved,
        openingHours: hours,
      );

  late FakeMerchantRepository merchants;

  Future<void> pump(WidgetTester tester, {List<OpeningWindow> hours = const []}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    merchants = FakeMerchantRepository(seed: [shop(hours: hours)]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantRepositoryProvider.overrideWithValue(merchants),
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
            child: HoursScreen(merchantId: merchantId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(HoursScreen.saveKey));
    await tester.pumpAndSettle();
  }

  List<OpeningWindow> savedHours() =>
      merchants.all.firstWhere((m) => m.id == merchantId).openingHours;

  group('every day of the week', () {
    testWidgets('all seven are offered, Saturday through Friday', (tester) async {
      await pump(tester);

      for (final day in ['السبت', 'الأحد', 'الاثنين', 'الثلاثاء',
                         'الأربعاء', 'الخميس', 'الجمعة']) {
        expect(find.text(day), findsOneWidget, reason: day);
      }
    });

    // The whole reason this screen exists: a shop with no hours takes no orders and had
    // no way to say otherwise.
    testWidgets('a shop with no hours starts with every day off', (tester) async {
      await pump(tester);

      for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
        final toggle = tester.widget<Switch>(
          find.byKey(HoursScreen.dayKey(weekday)),
        );
        expect(toggle.value, isFalse, reason: 'weekday $weekday');
      }
    });
  });

  group('what gets saved', () {
    testWidgets('turning a day on writes a window for it', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(HoursScreen.dayKey(DateTime.sunday)));
      await tester.pumpAndSettle();
      await save(tester);

      expect(savedHours(), hasLength(1));
      expect(savedHours().single.weekday, DateTime.sunday);
    });

    // Monday=1 … Sunday=7, matching `DateTime.weekday`, which is what
    // `OpeningWindow.contains` compares against. A window written as 0 is matched by
    // nothing — the seeded data said `0..6` and every shop in the city was shut on
    // Sundays because of it.
    testWidgets('and Sunday is 7, never 0', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(HoursScreen.dayKey(DateTime.sunday)));
      await tester.pumpAndSettle();
      await save(tester);

      expect(savedHours().single.weekday, 7);
      expect(savedHours().map((w) => w.weekday), isNot(contains(0)));
    });

    testWidgets('turning a day off removes its window', (tester) async {
      await pump(tester, hours: const [
        OpeningWindow(weekday: DateTime.monday, openMinute: 0, closeMinute: 1439),
        OpeningWindow(weekday: DateTime.tuesday, openMinute: 0, closeMinute: 1439),
      ]);

      await tester.tap(find.byKey(HoursScreen.dayKey(DateTime.monday)));
      await tester.pumpAndSettle();
      await save(tester);

      expect(savedHours().map((w) => w.weekday), [DateTime.tuesday]);
    });

    testWidgets('existing hours are shown as they are', (tester) async {
      await pump(tester, hours: const [
        OpeningWindow(weekday: DateTime.friday, openMinute: 600, closeMinute: 1380),
      ]);

      final friday =
          tester.widget<Switch>(find.byKey(HoursScreen.dayKey(DateTime.friday)));
      expect(friday.value, isTrue);
      expect(find.textContaining('10:00'), findsWidgets);
      expect(find.textContaining('23:00'), findsWidgets);
    });
  });

  group('saying what happened', () {
    // A merchant who taps save and sees nothing has no idea whether their shop will take
    // orders tonight.
    testWidgets('a refused save is said out loud', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      merchants = FakeMerchantRepository(
        seed: [shop()],
        saveFailure: const OfflineFailure(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            merchantRepositoryProvider.overrideWithValue(merchants),
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
              child: HoursScreen(merchantId: merchantId),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HoursScreen.dayKey(DateTime.sunday)));
      await tester.pumpAndSettle();
      await save(tester);

      expect(find.textContaining('جرّب تاني'), findsOneWidget);
    });
  });
}
