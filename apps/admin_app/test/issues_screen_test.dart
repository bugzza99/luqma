import 'package:admin_app/src/issues/issues_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// الشكاوى — the tickets a customer raised that nobody has closed.
///
/// Closing one is the only write on this screen, and it is not reversible from here: a
/// closed ticket leaves the list. So the dialog that asks about it has to mean what it
/// says, which is exactly what was wrong with it.
void main() {
  late FakeIssueRepository issues;

  final open = OrderIssue(
    id: 'i1',
    orderId: 'o1',
    customerUid: 'c1',
    merchantId: 'm1',
    reason: 'الأكل وصل بارد',
    status: OrderIssue.open,
    createdAt: DateTime(2026, 8, 27, 12),
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    issues = FakeIssueRepository(seed: [open]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [issueRepositoryProvider.overrideWithValue(issues)],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: IssuesScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Whether the ticket is still open, asked of the repository rather than the screen.
  Future<bool> stillOpen() async =>
      (await issues.watchIssues().first)
          .any((i) => i.id == 'i1' && i.isOpen);

  testWidgets('shows an open ticket', (tester) async {
    await pump(tester);

    expect(find.text('الأكل وصل بارد'), findsOneWidget);
  });

  // The bug this file was written for. The guard read
  // `if (note == null && !context.mounted) return;` — with `and`, it only returned when
  // the dialog was cancelled *and* the screen had gone. Cancelling while still looking
  // at it fell straight through and closed the ticket, which is the opposite of what the
  // person just asked for.
  testWidgets('cancelling the dialog leaves the ticket open', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(IssuesScreen.closeKey).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(IssuesScreen.cancelKey));
    await tester.pumpAndSettle();

    expect(await stillOpen(), isTrue, reason: 'they said no');
  });

  testWidgets('confirming closes it', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(IssuesScreen.closeKey).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(IssuesScreen.confirmKey));
    await tester.pumpAndSettle();

    expect(await stillOpen(), isFalse);
  });
}
