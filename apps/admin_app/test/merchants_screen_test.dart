import 'package:admin_app/src/merchants/merchants_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The screen the owner spends the launch inside.
///
/// Two jobs that pull in different directions: deciding on merchants waiting for
/// approval, which is occasional and careful, and entering menus, which is six hundred
/// items of repetitive typing. The list-and-detail layout is what lets the second one
/// happen without bouncing back to a list between every item.
void main() {
  Merchant merchant(
    String id, {
    String? name,
    MerchantStatus status = MerchantStatus.approved,
  }) =>
      Merchant(
        id: id,
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: name ?? id,
        zoneId: 'z1',
        phone: '01000000000',
        status: status,
        menuCategories: const [MenuCategory(id: 'c1', name: 'مشويات')],
      );

  late FakeMerchantRepository merchants;
  late FakeMenuRepository menus;

  Future<void> pump(
    WidgetTester tester, {
    List<Merchant>? seed,
    Map<String, int> orderCounts = const {},
    Size size = const Size(1400, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    merchants = FakeMerchantRepository(
      seed: seed ??
          [
            merchant('a', name: 'مطعم الشاطئ'),
            merchant('b', name: 'كشري المحطة', status: MerchantStatus.pending),
          ],
      orderCounts: orderCounts,
    );
    menus = FakeMenuRepository(
      categories: const [MenuCategory(id: 'c1', name: 'مشويات')],
      items: const [
        MenuItem(
          id: 'i1',
          merchantId: 'a',
          categoryId: 'c1',
          name: 'فراخ مشوية',
          price: 12000,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantRepositoryProvider.overrideWithValue(merchants),
          menuRepositoryProvider.overrideWithValue(menus),
          geographyRepositoryProvider.overrideWithValue(
            FakeGeographyRepository(zones: const [
              Zone(id: 'z1', cityId: 'edku', name: 'المعمورة'),
            ]),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: MerchantsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the list', () {
    testWidgets('shows every merchant, approved or not', (tester) async {
      await pump(tester);

      expect(find.text('مطعم الشاطئ'), findsWidgets);
      expect(find.text('كشري المحطة'), findsWidgets);
    });

    // The queue is the reason to open the screen, so it cannot be something to scroll for.
    testWidgets('marks the ones waiting for a decision', (tester) async {
      await pump(tester);

      expect(find.byKey(MerchantsScreen.pendingBadgeKey('b')), findsOneWidget);
      expect(find.byKey(MerchantsScreen.pendingBadgeKey('a')), findsNothing);
    });

    testWidgets('says so plainly when there are none yet', (tester) async {
      await pump(tester, seed: []);

      expect(find.byKey(MerchantsScreen.emptyKey), findsOneWidget);
    });
  });

  group('choosing one', () {
    testWidgets('opens its detail beside the list on a wide screen',
        (tester) async {
      await pump(tester);

      await tester.tap(find.text('مطعم الشاطئ').first);
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantsScreen.detailKey), findsOneWidget);
      // Both panes at once — the point of the layout.
      expect(find.text('كشري المحطة'), findsWidgets);
    });

    testWidgets('shows the merchant’s menu in the detail', (tester) async {
      await pump(tester);

      await tester.tap(find.text('مطعم الشاطئ').first);
      await tester.pumpAndSettle();

      expect(find.byType(MenuEditor), findsOneWidget);
      expect(find.text('فراخ مشوية'), findsOneWidget);
    });
  });

  group('approving', () {
    testWidgets('a pending merchant can be approved from its detail',
        (tester) async {
      await pump(tester);

      await tester.tap(find.text('كشري المحطة').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantsScreen.approveKey));
      await tester.pumpAndSettle();

      final saved = await merchants.watchAllMerchants(cityId: 'edku').first;
      expect(
        saved.firstWhere((m) => m.id == 'b').status,
        MerchantStatus.approved,
      );
    });

    testWidgets('an approved merchant offers suspension instead', (tester) async {
      await pump(tester);

      await tester.tap(find.text('مطعم الشاطئ').first);
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantsScreen.approveKey), findsNothing);
      expect(find.byKey(MerchantsScreen.suspendKey), findsOneWidget);
    });
  });

  group('adding one', () {
    testWidgets('a new merchant is created and left pending', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantsScreen.addKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(MerchantsScreen.nameFieldKey), 'مطعم جديد');
      await tester.enterText(find.byKey(MerchantsScreen.phoneFieldKey), '01099999999');
      await tester.tap(find.byKey(MerchantsScreen.saveKey));
      await tester.pumpAndSettle();

      final saved = await merchants.watchAllMerchants(cityId: 'edku').first;
      final added = saved.firstWhere((m) => m.name == 'مطعم جديد');
      // Created, not approved: the owner enters the data, and approving is a separate
      // decision made once the merchant is actually ready to receive orders.
      expect(added.status, MerchantStatus.pending);
      expect(added.zoneId, 'z1');
    });

    testWidgets('refuses a merchant with no name', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(MerchantsScreen.addKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantsScreen.saveKey));
      await tester.pumpAndSettle();

      final saved = await merchants.watchAllMerchants(cityId: 'edku').first;
      expect(saved, hasLength(2), reason: 'nothing was added');
    });
  });

  group('deleting a merchant', () {
    testWidgets('a merchant that never traded deletes cleanly', (tester) async {
      await pump(tester);

      await tester.tap(find.text('مطعم الشاطئ').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantsScreen.deleteKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantsScreen.confirmDeleteKey));
      await tester.pumpAndSettle();

      final saved = await merchants.watchAllMerchants(cityId: 'edku').first;
      expect(saved.where((m) => m.id == 'a'), isEmpty);
    });

    testWidgets('a merchant with orders cannot be deleted', (tester) async {
      await pump(tester, orderCounts: {'a': 7});

      await tester.tap(find.text('مطعم الشاطئ').first);
      await tester.pumpAndSettle();

      // The control is present but disabled: the reason is in the tooltip.
      final button = tester.widget<IconButton>(
        find.byKey(MerchantsScreen.deleteKey),
      );
      expect(button.onPressed, isNull);

      // The fallback — suspension — is still on offer.
      expect(find.byKey(MerchantsScreen.suspendKey), findsOneWidget);
    });
  });

  group('on a phone', () {
    // One pane: the detail replaces the list rather than being squeezed beside it.
    testWidgets('the detail takes the screen', (tester) async {
      await pump(tester, size: const Size(400, 900));

      await tester.tap(find.text('مطعم الشاطئ').first);
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantsScreen.detailKey), findsOneWidget);
      expect(find.text('كشري المحطة'), findsNothing);
    });
  });
}
