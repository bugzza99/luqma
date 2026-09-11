import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/shop/courier_roster_screen.dart';
import 'package:merchant_app/src/shop/shop_screen.dart';

void main() {
  const merchantId = 'shop-fish';
  final fixedClock = DateTime(2026, 9, 23, 12, 0);

  late FakeCourierRosterRepository rosterRepo;
  late FakeMerchantRepository merchantRepo;

  final rider1 = CourierRosterItem(
    id: 'cm-1',
    courierUid: 'c-1',
    merchantId: merchantId,
    isActive: true,
    name: 'أحمد محمود',
    phone: '01000000001',
    pausedUntil: null, // Available
  );

  final rider2Paused = CourierRosterItem(
    id: 'cm-2',
    courierUid: 'c-2',
    merchantId: merchantId,
    isActive: true,
    name: 'إبراهيم علي',
    phone: '01000000002',
    pausedUntil: fixedClock.add(const Duration(minutes: 45)), // Paused until 12:45
  );

  final rider3Detached = CourierRosterItem(
    id: 'cm-3',
    courierUid: 'c-3',
    merchantId: merchantId,
    isActive: false, // Detached — must not appear on screen!
    name: 'صالح حسن',
    phone: '01000000003',
  );

  Future<void> pumpRoster(
    WidgetTester tester, {
    List<CourierRosterItem>? seed,
    Map<String, StaffMember>? staffByPhone,
    DateTime? clock,
    Failure? failure,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    rosterRepo = FakeCourierRosterRepository(
      seed: seed ?? [rider1, rider2Paused, rider3Detached],
      staffByPhone: staffByPhone ??
          {
            '01000000001': const StaffMember(
              uid: 'c-1',
              scope: 'merchant',
              role: 'courier',
              isActive: true,
              name: 'أحمد محمود',
              phone: '01000000001',
            ),
            '01000000002': const StaffMember(
              uid: 'c-2',
              scope: 'merchant',
              role: 'courier',
              isActive: true,
              name: 'إبراهيم علي',
              phone: '01000000002',
            ),
            '01000000005': const StaffMember(
              uid: 'c-5',
              scope: 'merchant',
              role: 'courier',
              isActive: true,
              name: 'كابتن جديد',
              phone: '01000000005',
            ),
          },
      failure: failure,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courierRosterRepositoryProvider.overrideWithValue(rosterRepo),
          clockProvider.overrideWithValue(() => clock ?? fixedClock),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: CourierRosterScreen(merchantId: merchantId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('CourierRosterScreen listing', () {
    testWidgets('displays active couriers with name, phone, and availability status',
        (tester) async {
      await pumpRoster(tester);

      // Rider 1 is active and available
      expect(find.text('أحمد محمود'), findsOneWidget);
      expect(find.text('01000000001'), findsOneWidget);
      expect(find.text('متاح'), findsOneWidget);

      // Rider 2 is active and paused until 12:45
      expect(find.text('إبراهيم علي'), findsOneWidget);
      expect(find.text('01000000002'), findsOneWidget);
      expect(find.textContaining('متوقف'), findsOneWidget);

      // Rider 3 is detached (isActive: false) -> must NOT be shown!
      expect(find.text('صالح حسن'), findsNothing);
      expect(find.text('01000000003'), findsNothing);
    });

    testWidgets('empty roster shows a dedicated empty state', (tester) async {
      await pumpRoster(tester, seed: []);

      expect(find.byKey(CourierRosterScreen.emptyKey), findsOneWidget);
    });

    testWidgets('error state shows retryable LuqmaErrorView', (tester) async {
      await pumpRoster(tester, failure: const OfflineFailure());

      expect(find.byType(LuqmaErrorView), findsOneWidget);
    });
  });

  group('CourierRosterScreen adding couriers', () {
    testWidgets('adds a courier by phone number successfully and clears input',
        (tester) async {
      await pumpRoster(tester);

      expect(find.text('كابتن جديد'), findsNothing);

      await tester.enterText(
        find.byKey(CourierRosterScreen.phoneFieldKey),
        '01000000005',
      );
      await tester.tap(find.byKey(CourierRosterScreen.addCourierKey));
      await tester.pumpAndSettle();

      // Successful add shows snackbar and displays rider
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('كابتن جديد'), findsOneWidget);
      // Input field was cleared
      final field = tester.widget<TextField>(
        find.byKey(CourierRosterScreen.phoneFieldKey),
      );
      expect(field.controller?.text, isEmpty);
    });

    testWidgets('refuses non-existent or inactive courier with actionable sentence',
        (tester) async {
      await pumpRoster(tester);

      await tester.enterText(
        find.byKey(CourierRosterScreen.phoneFieldKey),
        '01099999999', // Unknown phone
      );
      await tester.tap(find.byKey(CourierRosterScreen.addCourierKey));
      await tester.pumpAndSettle();

      // Must say no active courier has that number and accounts are opened by admin
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('مفيش كابتن نشط بالرقم ده. حسابات الكباتن بيفتحها مدير النظام.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('refuses permission denial gracefully without crashing',
        (tester) async {
      await pumpRoster(tester);

      rosterRepo.attachFailure = const PermissionFailure();

      await tester.enterText(
        find.byKey(CourierRosterScreen.phoneFieldKey),
        '01000000005',
      );
      await tester.tap(find.byKey(CourierRosterScreen.addCourierKey));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('handles offline / generic failure gracefully', (tester) async {
      await pumpRoster(tester);

      rosterRepo.attachFailure = const OfflineFailure();

      await tester.enterText(
        find.byKey(CourierRosterScreen.phoneFieldKey),
        '01000000005',
      );
      await tester.tap(find.byKey(CourierRosterScreen.addCourierKey));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('مفيش نت'), findsOneWidget);
    });
  });

  group('CourierRosterScreen removing couriers', () {
    testWidgets('tapping detach asks for confirmation before detaching',
        (tester) async {
      await pumpRoster(tester);

      final detachBtn = find.byKey(CourierRosterScreen.detachKey('c-1'));
      expect(detachBtn, findsOneWidget);

      await tester.tap(detachBtn);
      await tester.pumpAndSettle();

      // Confirmation dialog is shown
      expect(find.byKey(CourierRosterScreen.confirmDetachKey), findsOneWidget);
      expect(find.byKey(CourierRosterScreen.cancelDetachKey), findsOneWidget);

      // Cancelling keeps the courier
      await tester.tap(find.byKey(CourierRosterScreen.cancelDetachKey));
      await tester.pumpAndSettle();

      expect(find.text('أحمد محمود'), findsOneWidget);
      expect(rosterRepo.all.firstWhere((i) => i.courierUid == 'c-1').isActive, isTrue);
    });

    testWidgets('confirming detach sets is_active to false and removes from list',
        (tester) async {
      await pumpRoster(tester);

      await tester.tap(find.byKey(CourierRosterScreen.detachKey('c-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(CourierRosterScreen.confirmDetachKey));
      await tester.pumpAndSettle();

      // Removed from the screen
      expect(find.text('أحمد محمود'), findsNothing);

      // Row still exists in repository, but is_active = false
      final detached = rosterRepo.all.firstWhere((i) => i.courierUid == 'c-1');
      expect(detached.isActive, isFalse, reason: 'detaching deactivates, never deletes');
    });
  });

  group('ShopScreen navigation to CourierRosterScreen', () {
    testWidgets('shop tab offers courier roster tile and opens screen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      merchantRepo = FakeMerchantRepository(
        seed: [
          Merchant(
            id: merchantId,
            cityId: 'edku',
            name: 'مطعم السمك',
            type: MerchantType.restaurant,
            zoneId: 'z1',
            phone: '0100',
            status: MerchantStatus.approved,
            ratingAvg: 4.5,
            ratingCount: 10,
          ),
        ],
      );

      rosterRepo = FakeCourierRosterRepository(seed: [rider1]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            merchantRepositoryProvider.overrideWithValue(merchantRepo),
            courierRosterRepositoryProvider.overrideWithValue(rosterRepo),
            staffIdentityProvider.overrideWithValue(
              const StaffIdentity(
                uid: 'owner-1',
                email: 'owner@shop.com',
                role: StaffRole.owner,
                merchantId: merchantId,
              ),
            ),
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
              child: ShopScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the roster tile
      final tile = find.byKey(ShopScreen.rosterKey);
      expect(tile, findsOneWidget);

      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();

      await tester.tap(tile);
      await tester.pumpAndSettle();

      // CourierRosterScreen is displayed
      expect(find.byType(CourierRosterScreen), findsOneWidget);
      expect(find.text('أحمد محمود'), findsOneWidget);
    });
  });
}
