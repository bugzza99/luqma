import 'package:admin_app/src/customers/customers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// العملاء — searching, blocking, and the one way back from a forgotten password.
///
/// A customer signs in with their phone number and a password. There is no mailbox
/// behind the account and OTP is off, so "email me a link" and "text me a code" both
/// lead nowhere: somebody who forgets calls, and an admin does this. Which makes this
/// screen the only route back into a locked-out account — worth a test of its own.
void main() {
  late FakeCustomerRepository customers;

  final ahmed = CustomerSummary(
    id: 'u1',
    name: 'أحمد محمود',
    phone: '01012345678',
    isBlocked: false,
    rejectedOrdersCount: 0,
    createdAt: DateTime(2026, 8, 1),
  );

  Future<void> pump(WidgetTester tester, {Failure? failure}) async {
    customers = FakeCustomerRepository(seed: [ahmed], failure: failure);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [customerRepositoryProvider.overrideWithValue(customers)],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: CustomersScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The screen shows nothing until somebody searches.
  Future<void> search(WidgetTester tester) async {
    await tester.enterText(find.byKey(CustomersScreen.searchKey), 'أحمد');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
  }

  testWidgets('a search finds a customer by name', (tester) async {
    await pump(tester);
    await search(tester);

    expect(find.text('أحمد محمود'), findsOneWidget);
    // Scoped to the results: the search field's own hint is the same number.
    expect(
      find.descendant(
        of: find.byType(ListView),
        matching: find.text('01012345678'),
      ),
      findsOneWidget,
    );
  });

  group('a new password', () {
    // The old one stops working the moment this runs, so a mistyped tap on the wrong row
    // locks somebody out of their own account. Asked first, every time.
    testWidgets('is asked about before anything changes', (tester) async {
      await pump(tester);
      await search(tester);

      await tester.tap(find.byKey(CustomersScreen.resetKey));
      await tester.pumpAndSettle();

      expect(find.byKey(CustomersScreen.confirmResetKey), findsOneWidget);
      expect(customers.resetCalls, isEmpty, reason: 'nothing has happened yet');
    });

    testWidgets('is not made when the admin backs out', (tester) async {
      await pump(tester);
      await search(tester);

      await tester.tap(find.byKey(CustomersScreen.resetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('لا'));
      await tester.pumpAndSettle();

      expect(customers.resetCalls, isEmpty);
    });

    // Shown once and nowhere else: this is the only moment anybody can read it, which is
    // the point of it coming back rather than being stored.
    testWidgets('is shown so it can be read down the phone', (tester) async {
      await pump(tester);
      await search(tester);

      await tester.tap(find.byKey(CustomersScreen.resetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CustomersScreen.confirmResetKey));
      await tester.pumpAndSettle();

      expect(customers.resetCalls, ['u1']);
      expect(find.text('demo-pass-42'), findsOneWidget);
    });

    testWidgets('says so when it could not be made', (tester) async {
      await pump(tester);
      await search(tester);
      // Refused only after the search has already found the row — which is the shape of
      // the real case: the admin is looking at a customer when the reset is refused.
      customers.failure = const PermissionFailure();

      await tester.tap(find.byKey(CustomersScreen.resetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CustomersScreen.confirmResetKey));
      await tester.pumpAndSettle();

      expect(find.text('مقدرناش'), findsOneWidget);
      expect(find.text('demo-pass-42'), findsNothing);
    });

    // A staff account reached through the customers screen: the function refuses it, and
    // the screen says where those are managed rather than shrugging.
    testWidgets('a staff account is sent to the staff screen', (tester) async {
      await pump(tester);
      await search(tester);
      customers.failure = const ConflictFailure();

      await tester.tap(find.byKey(CustomersScreen.resetKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CustomersScreen.confirmResetKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('شاشة الموظفين'), findsOneWidget);
    });
  });
}
