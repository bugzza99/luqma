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

  Future<void> pump(WidgetTester tester) async {
    staff = FakeStaffRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          staffRepositoryProvider.overrideWithValue(staff),
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
}
