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

  Future<void> pump(WidgetTester tester) async {
    staff = FakeStaffRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [staffRepositoryProvider.overrideWithValue(staff)],
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

  testWidgets('a filled form creates through the repository', (tester) async {
    await pump(tester);
    await openForm(tester);

    await tester.enterText(find.byKey(const Key('staff.email')), 'owner@luqma.test');
    await tester.enterText(find.byKey(const Key('staff.password')), 'luqma1234');
    await tester.enterText(find.byKey(const Key('staff.name')), 'صاحب الشاطئ');
    await tester.enterText(
      find.byKey(const Key('staff.merchant-id')),
      '00000000-0000-0000-0000-00000000m001',
    );
    await tester.tap(find.byKey(StaffScreen.submitKey));
    await tester.pumpAndSettle();

    expect(staff.all, hasLength(1));
    expect(staff.all.single.role, 'owner');
    expect(staff.all.single.scope, 'merchant');
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
    await tester.enterText(
      find.byKey(const Key('staff.merchant-id')),
      '00000000-0000-0000-0000-00000000m001',
    );
    await tester.tap(find.byKey(StaffScreen.submitKey));
    await tester.pumpAndSettle();

    expect(find.text('الإيميل ده متسجل قبل كده.'), findsOneWidget);
  });
}
