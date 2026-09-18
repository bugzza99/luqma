import 'package:admin_app/src/auth/admin_access.dart';
import 'package:admin_app/src/merchants/merchants_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  const testMerchant = Merchant(
    id: 'm1',
    cityId: 'edku',
    type: MerchantType.restaurant,
    name: 'مطعم الشاطئ',
    zoneId: 'z1',
    phone: '01000000000',
    status: MerchantStatus.approved,
  );

  late FakeCuisineRepository cuisinesRepo;

  Future<void> pumpSheet(
    WidgetTester tester, {
    List<Cuisine> seed = const [],
    Map<String, Set<String>> members = const {},
    Failure? failure,
    Merchant merchant = testMerchant,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    cuisinesRepo = FakeCuisineRepository(
      seed: seed,
      members: members,
      failure: failure,
    );

    final router = GoRouter(
      initialLocation: '/test',
      routes: [
        GoRoute(
          path: '/test',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open_sheet'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => MerchantCuisinesSheet(merchant: merchant),
                ),
                child: const Text('افتح'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: Routes.cuisines,
          builder: (context, _) => const Scaffold(
            body: Text('صفحة شرائح الفئات'),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cuisineRepositoryProvider.overrideWithValue(cuisinesRepo),
        ],
        child: MaterialApp.router(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          supportedLocales: LuqmaStrings.supportedLocales,
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open_sheet')));
    await tester.pumpAndSettle();
  }

  group('MerchantCuisinesSheet', () {
    testWidgets('(a) chips load pre-selected from cuisinesOf', (tester) async {
      await pumpSheet(
        tester,
        seed: const [
          Cuisine(id: 'c1', cityId: 'edku', name: 'مشويات'),
          Cuisine(id: 'c2', cityId: 'edku', name: 'صيدليات'),
          Cuisine(id: 'c3', cityId: 'edku', name: 'سوبرماركت'),
        ],
        members: const {
          'c1': {'m1'},
          'c3': {'m1'},
        },
      );

      final chip1 = tester.widget<FilterChip>(
        find.byKey(MerchantCuisinesSheet.chipKey('c1')),
      );
      final chip2 = tester.widget<FilterChip>(
        find.byKey(MerchantCuisinesSheet.chipKey('c2')),
      );
      final chip3 = tester.widget<FilterChip>(
        find.byKey(MerchantCuisinesSheet.chipKey('c3')),
      );

      expect(chip1.selected, isTrue);
      expect(chip2.selected, isFalse);
      expect(chip3.selected, isTrue);
    });

    testWidgets(
        '(b) toggling + save calls setMerchantCuisines with the new set (assert fake membership)',
        (tester) async {
      await pumpSheet(
        tester,
        seed: const [
          Cuisine(id: 'c1', cityId: 'edku', name: 'مشويات'),
          Cuisine(id: 'c2', cityId: 'edku', name: 'صيدليات'),
          Cuisine(id: 'c3', cityId: 'edku', name: 'سوبرماركت'),
        ],
        members: const {
          'c1': {'m1'},
        },
      );

      // Select c2
      await tester.tap(find.byKey(MerchantCuisinesSheet.chipKey('c2')));
      await tester.pumpAndSettle();

      // Unselect c1
      await tester.tap(find.byKey(MerchantCuisinesSheet.chipKey('c1')));
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.byKey(MerchantCuisinesSheet.saveKey));
      await tester.pumpAndSettle();

      // Assert fake's stored membership
      final updated = await cuisinesRepo.cuisinesOf('m1');
      expect(updated.isOk, isTrue);
      expect(updated.valueOrNull, equals({'c2'}));

      // Success SnackBar shown
      expect(find.text('اتحفظت الفئات'), findsOneWidget);
    });

    testWidgets('(c) empty chip list shows the go-to-cuisines button and navigates',
        (tester) async {
      await pumpSheet(tester, seed: const []);

      expect(find.text('مفيش فئات لسه'), findsOneWidget);

      final goButton = find.text('شرائح الفئات');
      expect(goButton, findsOneWidget);

      await tester.tap(goButton);
      await tester.pumpAndSettle();

      expect(find.text('صفحة شرائح الفئات'), findsOneWidget);
    });

    testWidgets('error state is distinct from empty state', (tester) async {
      await pumpSheet(
        tester,
        seed: const [],
        failure: const OfflineFailure(),
      );

      expect(find.byType(LuqmaErrorView), findsOneWidget);
      expect(find.text('مفيش فئات لسه'), findsNothing);
    });

    testWidgets('save failure keeps sheet open and shows SnackBar', (tester) async {
      await pumpSheet(
        tester,
        seed: const [
          Cuisine(id: 'c1', cityId: 'edku', name: 'مشويات'),
        ],
      );

      cuisinesRepo.failure = const OfflineFailure();

      await tester.tap(find.byKey(MerchantCuisinesSheet.saveKey));
      await tester.pumpAndSettle();

      expect(find.text('مفيش نت — جرّب تاني.'), findsOneWidget);
      expect(find.byKey(MerchantCuisinesSheet.saveKey), findsOneWidget);
    });

    testWidgets('open control in merchant header has key and opens sheet',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final fakeMerchants = FakeMerchantRepository(
        seed: [testMerchant],
      );
      cuisinesRepo = FakeCuisineRepository(
        seed: const [
          Cuisine(id: 'c1', cityId: 'edku', name: 'مشويات'),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            merchantRepositoryProvider.overrideWithValue(fakeMerchants),
            cuisineRepositoryProvider.overrideWithValue(cuisinesRepo),
            menuRepositoryProvider.overrideWithValue(
              FakeMenuRepository(
                categories: const [],
                items: const [],
              ),
            ),
            geographyRepositoryProvider.overrideWithValue(
              FakeGeographyRepository(zones: const [
                Zone(id: 'z1', cityId: 'edku', name: 'المعمورة'),
              ]),
            ),
          ],
          child: MaterialApp(
            theme: LuqmaTheme.light,
            locale: const Locale('ar'),
            supportedLocales: LuqmaStrings.supportedLocales,
            localizationsDelegates: LuqmaStrings.localizationsDelegates,
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: MerchantsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Choose the merchant to view detail
      await tester.tap(find.text('مطعم الشاطئ').first);
      await tester.pumpAndSettle();

      // Open control is visible in header
      final openButton = find.byKey(MerchantCuisinesSheet.openKey);
      expect(openButton, findsOneWidget);
      expect(find.text('الفئات'), findsWidgets);

      // Tap open control
      await tester.tap(openButton);
      await tester.pumpAndSettle();

      // Sheet is open and chip is visible
      expect(find.byKey(MerchantCuisinesSheet.chipKey('c1')), findsOneWidget);
      expect(find.byKey(MerchantCuisinesSheet.saveKey), findsOneWidget);
    });
  });
}
