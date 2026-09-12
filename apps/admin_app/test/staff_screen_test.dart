import 'package:admin_app/src/staff/staff_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Creating a staff account from the screen, against the fake.
///
/// Whether the *server* refuses a non-admin caller is the Edge Function's question;
/// what is proven here is that the form checks its shape, sends what was typed, and
/// says the right sentence when the create comes back refused.
void main() {
  late FakeStaffRepository staff;
  late FakeCourierRosterRepository roster;

  const shore = Merchant(
    id: 'aaaaaaaa-0000-4000-8000-000000000001',
    cityId: 'edku',
    type: MerchantType.restaurant,
    name: 'مطعم الشاطئ',
    zoneId: 'z1',
    phone: '01000000000',
    status: MerchantStatus.approved,
  );
  const kitchen = Merchant(
    id: 'bbbbbbbb-0000-4000-8000-000000000002',
    cityId: 'edku',
    type: MerchantType.homeKitchen,
    name: 'مطبخ أم أحمد',
    zoneId: 'z1',
    phone: '01000000001',
    status: MerchantStatus.approved,
  );

  Future<void> pump(
    WidgetTester tester, {
    Size? size,
    FakeStaffRepository? staffRepo,
    FakeCourierRosterRepository? rosterRepo,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    staff = staffRepo ?? FakeStaffRepository();
    roster = rosterRepo ?? FakeCourierRosterRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffRepositoryProvider.overrideWithValue(staff),
          courierRosterRepositoryProvider.overrideWithValue(roster),
          merchantRepositoryProvider.overrideWithValue(
            FakeMerchantRepository(seed: const [shore, kitchen]),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: StaffScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openForm(WidgetTester tester) async {
    await tester.tap(find.byKey(StaffScreen.createKey));
    await tester.pumpAndSettle();
  }

  /// Picks a shop by the name the owner knows it by.
  Future<void> chooseMerchant(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const Key('staff.merchant')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  testWidgets('a filled form creates through the repository', (tester) async {
    await pump(tester);
    await openForm(tester);

    await tester.enterText(find.byKey(const Key('staff.email')), 'owner@luqma.test');
    await tester.enterText(find.byKey(const Key('staff.password')), 'luqma1234');
    await tester.enterText(find.byKey(const Key('staff.name')), 'صاحب الشاطئ');
    await chooseMerchant(tester, 'مطعم الشاطئ');
    await tester.tap(find.byKey(StaffScreen.submitKey));
    await tester.pumpAndSettle();

    expect(staff.all, hasLength(1));
    expect(staff.all.single.role, 'owner');
    expect(staff.all.single.scope, 'merchant');
  });

  // The field used to be a free-text box labelled "رقم المطعم (UUID)". No screen in the
  // app shows a merchant's uuid and none lets you copy one, so the owner had no way to
  // fill it — which is why no merchant or courier account could be created at all.
  testWidgets('the shop is chosen by name, and its id is what is sent', (tester) async {
    await pump(tester);
    await openForm(tester);

    await tester.enterText(find.byKey(const Key('staff.email')), 'cook@luqma.test');
    await tester.enterText(find.byKey(const Key('staff.password')), 'luqma1234');
    await tester.enterText(find.byKey(const Key('staff.name')), 'أم أحمد');
    await chooseMerchant(tester, 'مطبخ أم أحمد');
    await tester.tap(find.byKey(StaffScreen.submitKey));
    await tester.pumpAndSettle();

    expect(staff.all.single.merchantId, kitchen.id);
  });

  // A courier belongs to a shop exactly as an owner does, and is the other half of what
  // the owner said they could not create.
  testWidgets('a courier is created against the shop that was picked', (tester) async {
    await pump(tester);
    await openForm(tester);

    await tester.enterText(find.byKey(const Key('staff.email')), 'rider@luqma.test');
    await tester.enterText(find.byKey(const Key('staff.password')), 'luqma1234');
    await tester.enterText(find.byKey(const Key('staff.name')), 'محمود');
    await tester.tap(find.byKey(const Key('staff.role')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('دليفري').last);
    await tester.pumpAndSettle();
    await chooseMerchant(tester, 'مطعم الشاطئ');
    await tester.tap(find.byKey(StaffScreen.submitKey));
    await tester.pumpAndSettle();

    expect(staff.all.single.role, 'courier');
    expect(staff.all.single.merchantId, shore.id);
  });

  testWidgets('a merchant account with no shop picked never reaches the repository',
      (tester) async {
    await pump(tester);
    await openForm(tester);

    await tester.enterText(find.byKey(const Key('staff.email')), 'x@y.test');
    await tester.enterText(find.byKey(const Key('staff.password')), 'luqma1234');
    await tester.tap(find.byKey(StaffScreen.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('اختار المطعم'), findsOneWidget);
    expect(staff.all, isEmpty);
  });

  // A platform admin belongs to no shop, so the picker is not drawn and not required.
  testWidgets('a platform account asks for no shop at all', (tester) async {
    await pump(tester);
    await openForm(tester);

    await tester.tap(find.byKey(const Key('staff.scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المنصة').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('staff.merchant')), findsNothing);

    await tester.enterText(find.byKey(const Key('staff.email')), 'admin@luqma.test');
    await tester.enterText(find.byKey(const Key('staff.password')), 'luqma1234');
    await tester.tap(find.byKey(StaffScreen.submitKey));
    await tester.pumpAndSettle();

    expect(staff.all.single.scope, 'platform');
    expect(staff.all.single.merchantId, isNull);
  });

  testWidgets('a short password never reaches the repository', (tester) async {
    await pump(tester);
    await openForm(tester);

    await tester.enterText(find.byKey(const Key('staff.email')), 'x@y.test');
    await tester.enterText(find.byKey(const Key('staff.password')), 'short');
    await tester.tap(find.byKey(StaffScreen.submitKey));
    await tester.pumpAndSettle();

    // The dialog is still up, and nothing was sent.
    expect(find.text('8 حروف على الأقل'), findsOneWidget);
    expect(staff.all, isEmpty);
  });

  testWidgets('an address GoTrue already has earns its own sentence', (tester) async {
    await pump(tester);

    // Seed one account directly, as production would already have it.
    await staff.createAccount(
      email: 'taken@luqma.test',
      password: 'luqma1234',
      name: 'موجود',
      scope: 'merchant',
      role: 'owner',
      merchantId: 'm1',
    );

    await openForm(tester);
    await tester.enterText(find.byKey(const Key('staff.email')), 'taken@luqma.test');
    await tester.enterText(find.byKey(const Key('staff.password')), 'luqma1234');
    await chooseMerchant(tester, 'مطعم الشاطئ');
    await tester.tap(find.byKey(StaffScreen.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('الإيميل ده متسجل قبل كده.'), findsOneWidget);
  });

  group('courier detail and attachments', () {
    const phoneSize = Size(390, 844);
    const wideSize = Size(1200, 800);

    testWidgets('tapping an owner row does not open courier detail', (tester) async {
      final staffRepo = FakeStaffRepository();
      await staffRepo.createAccount(
        email: 'owner@luqma.test',
        password: 'password123',
        name: 'صاحب الشاطئ',
        scope: 'merchant',
        role: 'owner',
        merchantId: shore.id,
      );

      await pump(tester, size: phoneSize, staffRepo: staffRepo);

      expect(find.text('صاحب الشاطئ'), findsOneWidget);
      await tester.tap(find.text('صاحب الشاطئ'));
      await tester.pumpAndSettle();

      expect(find.text('إضافة محل'), findsNothing);
      expect(find.text('المنصة'), findsNothing);
    });

    testWidgets('tapping a courier row opens detail with active shop names and platform row',
        (tester) async {
      final staffRepo = FakeStaffRepository();
      final created = await staffRepo.createAccount(
        email: 'courier@luqma.test',
        password: 'password123',
        name: 'كابتن محمود',
        scope: 'merchant',
        role: 'courier',
        merchantId: shore.id,
      );
      final courierUid = (created as Ok<StaffMember>).value.uid;

      final rosterRepo = FakeCourierRosterRepository(
        seed: [
          CourierRosterItem(
            id: 'att-1',
            courierUid: courierUid,
            merchantId: null, // Platform row
            isActive: true,
          ),
          CourierRosterItem(
            id: 'att-2',
            courierUid: courierUid,
            merchantId: shore.id,
            merchantName: 'مطعم الشاطئ',
            isActive: true,
          ),
        ],
      );

      await pump(
        tester,
        size: phoneSize,
        staffRepo: staffRepo,
        rosterRepo: rosterRepo,
      );

      await tester.tap(find.text('كابتن محمود'));
      await tester.pumpAndSettle();

      expect(find.text('المنصة'), findsOneWidget);
      expect(find.text('مطعم الشاطئ'), findsWidgets);
      expect(find.text('إضافة محل'), findsOneWidget);
      // Already holds platform, so "إضافة للمنصة" should NOT be shown
      expect(find.text('إضافة للمنصة'), findsNothing);
    });

    testWidgets('add to platform button appears when platform is not held and attaches when tapped',
        (tester) async {
      final staffRepo = FakeStaffRepository();
      final created = await staffRepo.createAccount(
        email: 'courier@luqma.test',
        password: 'password123',
        name: 'كابتن كريم',
        scope: 'merchant',
        role: 'courier',
        merchantId: shore.id,
      );
      final courierUid = (created as Ok<StaffMember>).value.uid;

      final rosterRepo = FakeCourierRosterRepository(
        seed: [
          CourierRosterItem(
            id: 'att-1',
            courierUid: courierUid,
            merchantId: shore.id,
            merchantName: 'مطعم الشاطئ',
            isActive: true,
          ),
        ],
      );

      await pump(
        tester,
        size: phoneSize,
        staffRepo: staffRepo,
        rosterRepo: rosterRepo,
      );

      await tester.tap(find.text('كابتن كريم'));
      await tester.pumpAndSettle();

      // Platform not held yet, so button is present
      expect(find.text('إضافة للمنصة'), findsOneWidget);

      await tester.tap(find.text('إضافة للمنصة'));
      await tester.pumpAndSettle();

      // Platform row attached!
      expect(
        rosterRepo.all.any(
          (a) => a.courierUid == courierUid && a.merchantId == null && a.isActive,
        ),
        isTrue,
      );
      // Button disappears once platform is held
      expect(find.text('إضافة للمنصة'), findsNothing);
    });

    testWidgets('add shop reuses merchant picker and attaches courier to picked shop',
        (tester) async {
      final staffRepo = FakeStaffRepository();
      final created = await staffRepo.createAccount(
        email: 'courier@luqma.test',
        password: 'password123',
        name: 'كابتن يوسف',
        scope: 'merchant',
        role: 'courier',
        merchantId: shore.id,
      );
      final courierUid = (created as Ok<StaffMember>).value.uid;

      final rosterRepo = FakeCourierRosterRepository(
        seed: [
          CourierRosterItem(
            id: 'att-1',
            courierUid: courierUid,
            merchantId: shore.id,
            merchantName: 'مطعم الشاطئ',
            isActive: true,
          ),
        ],
      );

      await pump(
        tester,
        size: phoneSize,
        staffRepo: staffRepo,
        rosterRepo: rosterRepo,
      );

      await tester.tap(find.text('كابتن يوسف'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('إضافة محل'));
      await tester.pumpAndSettle();

      // Reuses _MerchantPicker
      await chooseMerchant(tester, 'مطبخ أم أحمد');
      await tester.tap(find.text('إضافة').last);
      await tester.pumpAndSettle();

      expect(
        rosterRepo.all.any(
          (a) => a.courierUid == courierUid && a.merchantId == kitchen.id && a.isActive,
        ),
        isTrue,
      );
      expect(find.text('مطبخ أم أحمد'), findsWidgets);
    });

    testWidgets('detach requires confirmation and deactivates the attachment',
        (tester) async {
      final staffRepo = FakeStaffRepository();
      final created = await staffRepo.createAccount(
        email: 'courier@luqma.test',
        password: 'password123',
        name: 'كابتن أحمد',
        scope: 'merchant',
        role: 'courier',
        merchantId: shore.id,
      );
      final courierUid = (created as Ok<StaffMember>).value.uid;

      final rosterRepo = FakeCourierRosterRepository(
        seed: [
          CourierRosterItem(
            id: 'att-1',
            courierUid: courierUid,
            merchantId: shore.id,
            merchantName: 'مطعم الشاطئ',
            isActive: true,
          ),
        ],
      );

      await pump(
        tester,
        size: phoneSize,
        staffRepo: staffRepo,
        rosterRepo: rosterRepo,
      );

      await tester.tap(find.text('كابتن أحمد'));
      await tester.pumpAndSettle();

      // Find detach button
      final detachBtn = find.byTooltip('إلغاء الربط');
      expect(detachBtn, findsOneWidget);

      // Tap detach -> confirmation dialog pops up
      await tester.tap(detachBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('هل أنت متأكد من إلغاء الربط؟ سيتوقف الكابتن عن استلام طلبات هذا المحل فوراً.'),
        findsOneWidget,
      );

      // Cancel first
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      // Still active
      expect(
        rosterRepo.all.firstWhere((a) => a.id == 'att-1').isActive,
        isTrue,
      );

      // Tap detach again and confirm
      await tester.tap(detachBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.text('تأكيد إلغاء الربط'));
      await tester.pumpAndSettle();

      // Now deactivated
      expect(
        rosterRepo.all.firstWhere((a) => a.id == 'att-1').isActive,
        isFalse,
      );
    });

    testWidgets('wide layout displays list and detail side by side without breaking',
        (tester) async {
      final staffRepo = FakeStaffRepository();
      final created = await staffRepo.createAccount(
        email: 'courier@luqma.test',
        password: 'password123',
        name: 'كابتن عادل',
        scope: 'merchant',
        role: 'courier',
        merchantId: shore.id,
      );
      final courierUid = (created as Ok<StaffMember>).value.uid;

      final rosterRepo = FakeCourierRosterRepository(
        seed: [
          CourierRosterItem(
            id: 'att-1',
            courierUid: courierUid,
            merchantId: null,
            isActive: true,
          ),
          CourierRosterItem(
            id: 'att-2',
            courierUid: courierUid,
            merchantId: shore.id,
            merchantName: 'مطعم الشاطئ',
            isActive: true,
          ),
        ],
      );

      await pump(
        tester,
        size: wideSize,
        staffRepo: staffRepo,
        rosterRepo: rosterRepo,
      );

      // On wide layout, tapping courier selects them into the detail pane
      await tester.tap(find.text('كابتن عادل'));
      await tester.pumpAndSettle();

      // Both the staff list and the detail pane are on screen simultaneously
      expect(find.text('فريق العمل'), findsOneWidget);
      expect(find.text('المنصة'), findsOneWidget);
      expect(find.text('مطعم الشاطئ'), findsWidgets);
      expect(find.text('إضافة محل'), findsOneWidget);
    });

    testWidgets('role filter chips filter the staff list and inactive member shows status',
        (tester) async {
      final staffRepo = FakeStaffRepository();
      await staffRepo.createAccount(
        email: 'admin@luqma.test',
        password: 'password123',
        name: 'مصطفى صلاح',
        scope: 'platform',
        role: 'admin',
      );
      final courierRes = await staffRepo.createAccount(
        email: 'courier@luqma.test',
        password: 'password123',
        name: 'يوسف عادل',
        scope: 'merchant',
        role: 'courier',
        merchantId: shore.id,
      );
      final courierUid = (courierRes as Ok<StaffMember>).value.uid;
      // Deactivate courier
      await staffRepo.setActive(courierUid, active: false);

      await pump(tester, size: phoneSize, staffRepo: staffRepo);

      // Inactive courier shows 'موقوف'
      expect(find.text('موقوف'), findsOneWidget);

      // Both admin and courier initially visible under 'الكل'
      expect(find.text('مصطفى صلاح'), findsOneWidget);
      expect(find.text('يوسف عادل'), findsOneWidget);

      // Tap 'أدمن' filter chip
      await tester.tap(find.text('أدمن').first);
      await tester.pumpAndSettle();

      expect(find.text('مصطفى صلاح'), findsOneWidget);
      expect(find.text('يوسف عادل'), findsNothing);

      // Tap 'كباتن' filter chip
      await tester.tap(find.text('كباتن').first);
      await tester.pumpAndSettle();

      expect(find.text('مصطفى صلاح'), findsNothing);
      expect(find.text('يوسف عادل'), findsOneWidget);
    });
  });
}
