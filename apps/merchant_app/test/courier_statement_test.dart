import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:merchant_app/src/courier/courier_statement_screen.dart';

/// كشف حساب المندوب.
///
/// The owner's complaint on 2026-09-21, in one sentence: a rider could not see what they
/// delivered, what was charged on it, how much they owed, or whether last week's cash had
/// ever been credited. Every test here is one of those four questions.
void main() {
  late FakeCourierStatementRepository statement;

  CourierCharge charge({
    String orderId = 'o1',
    int basis = 2000,
    int amount = 200,
    int bps = 1000,
    CourierGround ground = CourierGround.platform,
    DateTime? reversedAt,
    int? orderNumber = 101,
    String? merchantName = 'مطعم الشاطئ',
  }) =>
      CourierCharge(
        orderId: orderId,
        basis: basis,
        bps: bps,
        amount: amount,
        ground: ground,
        settledAt: DateTime(2026, 9, 20, 14),
        reversedAt: reversedAt,
        orderNumber: orderNumber,
        merchantName: merchantName,
      );

  Future<void> pump(
    WidgetTester tester, {
    List<CourierCharge> charges = const [],
    List<CourierPayment> payments = const [],
    int owed = 0,
    Failure? failure,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    statement = FakeCourierStatementRepository(
      charges: charges,
      payments: payments,
      owed: {'c1': owed},
      failure: failure,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courierStatementRepositoryProvider.overrideWithValue(statement),
          authServiceProvider.overrideWithValue(
            FakeAuthService(restoring: const LuqmaIdentity(uid: 'c1')),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: CourierStatementScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('how much do I owe', () {
    testWidgets('says it plainly when there is a balance', (tester) async {
      await pump(tester, owed: 4500);

      expect(find.byKey(CourierStatementScreen.owedKey), findsOneWidget);
      expect(find.text('عليك للمنصة'), findsOneWidget);
    });

    testWidgets('says credit in words rather than with a minus sign', (tester) async {
      // A minus in front of a figure somebody is owed gets read as a debt at exactly the
      // wrong moment — the shop side already learned this.
      await pump(tester, owed: -1500);

      expect(find.byKey(CourierStatementScreen.creditKey), findsOneWidget);
      expect(find.text('رصيد ليك عندنا'), findsOneWidget);
      expect(find.textContaining('-'), findsNothing);
    });

    testWidgets('says so when the account is square', (tester) async {
      // Zero is an answer, and a blank space where a number belongs is not. A rider who
      // sees nothing assumes the screen failed.
      await pump(tester, owed: 0);

      expect(find.byKey(CourierStatementScreen.squareKey), findsOneWidget);
      expect(find.textContaining('مفيش عليك حاجة'), findsOneWidget);
    });
  });

  group('what was charged on what', () {
    testWidgets('names the shop and the order, not a uuid', (tester) async {
      await pump(tester, charges: [charge()]);

      expect(find.byKey(CourierStatementScreen.chargeKey('o1')), findsOneWidget);
      expect(find.textContaining('مطعم الشاطئ'), findsOneWidget);
      expect(find.textContaining('101'), findsOneWidget);
    });

    testWidgets('shows the sum behind the figure', (tester) async {
      // «ليه الرقم ده» answered on the line itself. Without it the only way to check a
      // charge is to ask somebody.
      await pump(tester, charges: [charge(basis: 2000, amount: 200)]);

      expect(find.textContaining('عمولة 10٪'), findsOneWidget);
    });

    testWidgets('explains a zero instead of leaving it bare', (tester) async {
      await pump(tester, charges: [
        charge(orderId: 'o2', amount: 0, ground: CourierGround.merchantDelivery),
      ]);

      expect(find.textContaining('توصيل المحل'), findsOneWidget);
    });

    testWidgets('marks a charge that was given back', (tester) async {
      await pump(tester, charges: [
        charge(orderId: 'o3', reversedAt: DateTime(2026, 9, 21)),
      ]);

      expect(find.byKey(CourierStatementScreen.reversedKey('o3')), findsOneWidget);
    });

    testWidgets('still shows a line whose order it cannot name', (tester) async {
      // The embed comes back null where the policy cannot reach the order, and the row
      // still belongs on the statement because the money moved.
      await pump(tester, charges: [
        charge(orderId: 'o4', orderNumber: null, merchantName: null),
      ]);

      expect(find.byKey(CourierStatementScreen.chargeKey('o4')), findsOneWidget);
      expect(find.text('توصيلة'), findsOneWidget);
    });

    testWidgets('says there is nothing rather than showing an empty page',
        (tester) async {
      await pump(tester);

      expect(find.byKey(CourierStatementScreen.noChargesKey), findsOneWidget);
    });
  });

  group('did my payments land', () {
    testWidgets('lists what was collected and adds it up', (tester) async {
      await pump(tester, owed: 500, payments: [
        CourierPayment(id: 'p1', amount: 3000, createdAt: DateTime(2026, 9, 19)),
        CourierPayment(id: 'p2', amount: 2000, createdAt: DateTime(2026, 9, 12)),
      ]);

      expect(find.byKey(CourierStatementScreen.paidKey), findsOneWidget);

      await tester.tap(find.byKey(CourierStatementScreen.paymentsTabKey));
      await tester.pumpAndSettle();

      expect(find.byKey(CourierStatementScreen.paymentKey('p1')), findsOneWidget);
      expect(find.byKey(CourierStatementScreen.paymentKey('p2')), findsOneWidget);
    });

    testWidgets('says nothing has been paid rather than drawing a blank tab',
        (tester) async {
      await pump(tester, owed: 500);

      await tester.tap(find.byKey(CourierStatementScreen.paymentsTabKey));
      await tester.pumpAndSettle();

      expect(find.byKey(CourierStatementScreen.noPaymentsKey), findsOneWidget);
    });
  });

  group('when the line drops', () {
    testWidgets('offers a way out rather than an empty statement', (tester) async {
      // An empty list and a failed read look identical to a rider, and one of them means
      // "you owe nothing". `LuqmaErrorView` takes an onRetry for exactly this.
      await pump(tester, failure: const OfflineFailure());

      expect(find.byType(LuqmaErrorView), findsWidgets);
      expect(find.byKey(CourierStatementScreen.noChargesKey), findsNothing);
    });
  });
}
