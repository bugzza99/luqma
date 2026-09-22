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
    Failure? countsFail,
    List<Zone> zones = const [Zone(id: 'z1', cityId: 'edku', name: 'المعمورة')],
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
    )..orderCountsFailure = countsFail;
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
            FakeGeographyRepository(zones: zones),
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

  /// Adding a shop, which is what the owner does fifteen times in an afternoon.
  ///
  /// The dialog used to pop whichever way the save went, so a shop that was never created
  /// looked exactly like one that was — and took the name, the number and the zone with
  /// it. On the connection this is used on, that is the common case rather than the edge.
  group('adding a shop', () {
    Future<void> openAdd(WidgetTester tester) async {
      await tester.tap(find.byKey(MerchantsScreen.addKey));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(MerchantsScreen.nameFieldKey), 'مطعم جديد');
      await tester.enterText(
          find.byKey(MerchantsScreen.phoneFieldKey), '01000000009');
      await tester.pump();
    }

    testWidgets('stays open and keeps what was typed when the save fails',
        (tester) async {
      await pump(tester);
      await openAdd(tester);
      merchants.saveFailure = const OfflineFailure();

      await tester.tap(find.byKey(MerchantsScreen.saveKey));
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantsScreen.saveKey), findsOneWidget,
          reason: 'the dialog is still there');
      expect(find.byKey(MerchantsScreen.createErrorKey), findsOneWidget);
      expect(find.text('مطعم جديد'), findsWidgets,
          reason: 'and the name has not been thrown away');
    });

    testWidgets('says which failure it was, not "something went wrong"',
        (tester) async {
      await pump(tester);
      await openAdd(tester);
      merchants.saveFailure = const PermissionFailure();

      await tester.tap(find.byKey(MerchantsScreen.saveKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('مش من حقك'), findsOneWidget);
    });

    testWidgets('a retry after a lost reply adds one shop, not two',
        (tester) async {
      // The idempotency, and the only assertion that can show it: the same id twice.
      // Counting the shops afterwards passes just as happily against a create that
      // overwrote itself.
      await pump(tester);
      await openAdd(tester);
      merchants.saveFailure = const OfflineFailure();
      await tester.tap(find.byKey(MerchantsScreen.saveKey));
      await tester.pumpAndSettle();

      merchants.saveFailure = null;
      await tester.tap(find.byKey(MerchantsScreen.saveKey));
      await tester.pumpAndSettle();

      expect(merchants.createAttempts, hasLength(2), reason: 'it was tried twice');
      expect(merchants.createAttempts.toSet(), hasLength(1),
          reason: 'under one id, so the server can refuse the repeat');
    });

    testWidgets('will not save into a city with no zones', (tester) async {
      // A shop with no zone cannot be delivered to and has nothing to price a delivery
      // against. The form used to hide the picker and save an empty string, which the
      // database refuses — as an error nobody could act on.
      await pump(tester, zones: const []);

      await tester.tap(find.byKey(MerchantsScreen.addKey));
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantsScreen.noZonesKey), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(MerchantsScreen.saveKey))
            .onPressed,
        isNull,
      );
    });

    testWidgets('a second tap while the first is in flight is refused',
        (tester) async {
      await pump(tester);
      await openAdd(tester);
      merchants.holdSave = true;

      await tester.tap(find.byKey(MerchantsScreen.saveKey));
      await tester.pump();

      expect(
        tester
            .widget<FilledButton>(find.byKey(MerchantsScreen.saveKey))
            .onPressed,
        isNull,
        reason: 'a second shop on a slow connection is exactly what this prevents',
      );

      merchants.releaseSave();
      await tester.pumpAndSettle();
      expect(merchants.createAttempts, hasLength(1));
    });
  });

    testWidgets('the list asks for the counts once, not once per shop', (tester) async {
      // The N+1 this replaced. A test that only reads the right numbers off the screen
      // passes just as happily against one request per card, which is why this counts the
      // requests instead — with fifteen shops on a phone connection that was fifteen
      // round trips to draw a label.
      await pump(
        tester,
        seed: [
          merchant('a', name: 'مطعم الشاطئ'),
          merchant('b', name: 'كشري المحطة'),
          merchant('c', name: 'مطعم البحر'),
        ],
        orderCounts: {'a': 7, 'b': 2, 'c': 1},
      );

      expect(merchants.orderCountsCalls, 1,
          reason: 'three shops, one request');
      expect(find.textContaining('7'), findsWidgets, reason: 'and the label is right');
    });

    testWidgets('a card without the counts yet still draws', (tester) async {
      // The count is a detail under a shop's name. A list that refuses to render because
      // a label could not be fetched is worse than a list with no labels — and this is
      // the screen the owner approves shops on.
      await pump(tester, countsFail: const OfflineFailure());

      expect(find.text('مطعم الشاطئ'), findsWidgets);
      expect(find.byType(LuqmaErrorView), findsNothing,
          reason: 'a missing label is not a broken screen');
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

  group('searching and filtering', () {
    testWidgets('searching by name filters the merchants on a phone',
        (tester) async {
      await pump(tester, size: const Size(400, 900));

      await tester.enterText(find.byKey(MerchantsScreen.searchKey), 'الشاطئ');
      await tester.pumpAndSettle();

      expect(find.text('مطعم الشاطئ'), findsOneWidget);
      expect(find.text('كشري المحطة'), findsNothing);
    });

    testWidgets('searching by phone matches and filters on a phone',
        (tester) async {
      await pump(
        tester,
        seed: [
          merchant('a', name: 'مطعم الشاطئ').copyWith(phone: '01011111111'),
          merchant('b', name: 'كشري المحطة', status: MerchantStatus.pending)
              .copyWith(phone: '01022222222'),
        ],
        size: const Size(400, 900),
      );

      // Typing Western digits
      await tester.enterText(find.byKey(MerchantsScreen.searchKey), '0102222');
      await tester.pumpAndSettle();

      expect(find.text('كشري المحطة'), findsOneWidget);
      expect(find.text('مطعم الشاطئ'), findsNothing);

      // Typing Arabic-Indic digits normalizes to the same phone
      await tester.enterText(find.byKey(MerchantsScreen.searchKey), '٠١٠١١١١');
      await tester.pumpAndSettle();

      expect(find.text('مطعم الشاطئ'), findsOneWidget);
      expect(find.text('كشري المحطة'), findsNothing);
    });

    testWidgets('status filter chips narrow down merchants on a phone',
        (tester) async {
      await pump(
        tester,
        seed: [
          merchant('a', name: 'مطعم الشاطئ', status: MerchantStatus.approved),
          merchant('b', name: 'كشري المحطة', status: MerchantStatus.pending),
          merchant('c', name: 'فرن المدينة', status: MerchantStatus.suspended),
        ],
        size: const Size(400, 900),
      );

      // Initially all 3 are shown
      expect(find.text('مطعم الشاطئ'), findsOneWidget);
      expect(find.text('كشري المحطة'), findsOneWidget);
      expect(find.text('فرن المدينة'), findsOneWidget);

      // Tap pending chip
      await tester.ensureVisible(find.byKey(MerchantsScreen.filterPendingKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantsScreen.filterPendingKey));
      await tester.pumpAndSettle();

      expect(find.text('كشري المحطة'), findsOneWidget);
      expect(find.text('مطعم الشاطئ'), findsNothing);
      expect(find.text('فرن المدينة'), findsNothing);

      // Tap active/approved chip
      await tester.ensureVisible(find.byKey(MerchantsScreen.filterActiveKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantsScreen.filterActiveKey));
      await tester.pumpAndSettle();

      expect(find.text('مطعم الشاطئ'), findsOneWidget);
      expect(find.text('كشري المحطة'), findsNothing);
      expect(find.text('فرن المدينة'), findsNothing);

      // Tap suspended chip
      await tester.ensureVisible(find.byKey(MerchantsScreen.filterSuspendedKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantsScreen.filterSuspendedKey));
      await tester.pumpAndSettle();

      expect(find.text('فرن المدينة'), findsOneWidget);
      expect(find.text('مطعم الشاطئ'), findsNothing);
      expect(find.text('كشري المحطة'), findsNothing);

      // Tap all chip
      await tester.ensureVisible(find.byKey(MerchantsScreen.filterAllKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(MerchantsScreen.filterAllKey));
      await tester.pumpAndSettle();

      expect(find.text('مطعم الشاطئ'), findsOneWidget);
      expect(find.text('كشري المحطة'), findsOneWidget);
      expect(find.text('فرن المدينة'), findsOneWidget);
    });

    testWidgets('no matching results shows empty search view',
        (tester) async {
      await pump(tester, size: const Size(400, 900));

      await tester.enterText(
        find.byKey(MerchantsScreen.searchKey),
        'اسم غير موجود',
      );
      await tester.pumpAndSettle();

      expect(find.text('مفيش مطاعم مطابقة للبحث.'), findsOneWidget);
      expect(find.text('مطعم الشاطئ'), findsNothing);
    });
  });

  group('the delegation banner', () {
    testWidgets('renders delegation banner around menu editor on a phone',
        (tester) async {
      await pump(tester, size: const Size(400, 900));

      await tester.tap(find.text('مطعم الشاطئ').first);
      await tester.pumpAndSettle();

      expect(find.byKey(MerchantsScreen.delegationBannerKey), findsOneWidget);
      expect(
        // The banner must not claim edits are logged: nothing audits `menu_items`.
        find.text('بتعدّل منيو مطعم الشاطئ نيابة عنه — أي تعديل بيظهر للعملاء على طول'),
        findsOneWidget,
      );
      expect(find.byType(MenuEditor), findsOneWidget);
    });
  });
}
