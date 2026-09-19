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

  Future<void> pump(
    WidgetTester tester, {
    List<OrderIssue>? seed,
    OrderRepository? ordersRepo,
    Failure? failure,
    Size size = const Size(1080, 2340),
    double devicePixelRatio = 3.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);

    issues = FakeIssueRepository(seed: seed ?? [open], failure: failure);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          issueRepositoryProvider.overrideWithValue(issues),
          if (ordersRepo != null)
            orderRepositoryProvider.overrideWithValue(ordersRepo),
        ],
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

  testWidgets('tapping an issue opens its detail and returning goes back',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();

    expect(find.text('ما قاله العميل'), findsOneWidget);
    expect(find.text('الأكل وصل بارد'), findsWidgets);

    // Return back
    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();

    expect(find.text('الشكاوى'), findsOneWidget);
    expect(find.text('افتح'), findsOneWidget);
  });

  testWidgets('closing from the detail view closes the ticket', (tester) async {
    await pump(tester);

    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('issueDetail.close')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(IssuesScreen.confirmKey));
    await tester.pumpAndSettle();

    expect(await stillOpen(), isFalse);
  });

  testWidgets('wide layout displays queue and detail side by side',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
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

    // Before selection on wide screen, empty placeholder is shown beside list
    expect(find.text('اختر شكوى من القائمة لعرض التفاصيل.'), findsOneWidget);
    expect(find.text('الأكل وصل بارد'), findsOneWidget);

    // After selection, detail appears on right pane
    await tester.tap(find.text('افتح'));
    await tester.pumpAndSettle();

    expect(find.text('ما قاله العميل'), findsOneWidget);
    expect(find.text('الأكل وصل بارد'), findsWidgets);
  });

  group('QA review findings', () {
    testWidgets('closing issue failure keeps dialog open with input and shows error',
        (tester) async {
      await pump(tester);
      // The list loads; only the close that follows fails.
      issues.failure = const OfflineFailure();

      await tester.tap(find.byKey(IssuesScreen.closeKey).first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'ملاحظة الأدمن التجريبية');
      await tester.tap(find.byKey(IssuesScreen.confirmKey));
      await tester.pumpAndSettle();

      // Dialog stays open
      expect(find.text('ملاحظة الأدمن التجريبية'), findsOneWidget);
      expect(find.text('فشل إغلاق الشكوى، حاول مرة أخرى'), findsOneWidget);
    });

    testWidgets('list time displays date properly (النهارده / امبارح / تاريخ)',
        (tester) async {
      final now = DateTime.now();
      final todayIssue = OrderIssue(
        id: 'today',
        orderId: 'o_today',
        customerUid: 'c1',
        merchantId: 'm1',
        reason: 'شكوى اليوم',
        status: OrderIssue.open,
        createdAt: DateTime(now.year, now.month, now.day, 15, 40),
      );
      final yesterday = now.subtract(const Duration(days: 1));
      final yesterdayIssue = OrderIssue(
        id: 'yesterday',
        orderId: 'o_yest',
        customerUid: 'c1',
        merchantId: 'm1',
        reason: 'شكوى الأمس',
        status: OrderIssue.open,
        createdAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 15, 40),
      );
      final sepIssue = OrderIssue(
        id: 'sep',
        orderId: 'o_sep',
        customerUid: 'c1',
        merchantId: 'm1',
        reason: 'شكوى سبتمبر',
        status: OrderIssue.open,
        createdAt: DateTime(2025, 9, 12, 15, 40),
      );

      await pump(tester, seed: [todayIssue, yesterdayIssue, sepIssue]);

      expect(find.text('النهارده 3:40م'), findsOneWidget);
      expect(find.text('امبارح 3:40م'), findsOneWidget);
      expect(find.text('12 سبتمبر 3:40م'), findsOneWidget);
    });

    testWidgets('issue detail shows order number, shop name, customer name, phone with call button, and total',
        (tester) async {
      const order = Order(
        id: 'o1',
        cityId: 'edku',
        orderNumber: 104,
        customerName: 'محمود حسن',
        customerPhone: '01012345678',
        merchantId: 'm1',
        merchantName: 'مطعم الحوت',
        zoneId: 'z1',
        type: OrderType.instant,
        items: [],
        pricing: OrderPricing(subtotal: 7500, deliveryFee: 1500, total: 9000),
      );
      final ordersRepo = FakeOrderRepository(seed: [order]);

      await pump(tester, ordersRepo: ordersRepo);

      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();

      expect(find.text('طلب #104'), findsOneWidget);
      expect(find.text('المحل: مطعم الحوت'), findsOneWidget);
      expect(find.text('العميل: محمود حسن'), findsOneWidget);
      expect(find.text('الهاتف: 01012345678'), findsOneWidget);
      expect(find.byTooltip('اتصال بالعميل'), findsOneWidget);
      expect(find.text('الإجمالي: 90 ج'), findsOneWidget);
    });
  });
}

