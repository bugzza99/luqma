import 'package:admin_app/src/billing/courier_billing_screen.dart';
import 'package:admin_app/src/billing/pending_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// حسابات المناديب, and the frozen pair underneath it.
///
/// Without this screen the platform charges couriers and can never say anybody paid, so a
/// balance only ever rises — the same shape as the eight phases spent recording what
/// would be charged and charging nothing, arrived at from the other side.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeCourierStatementRepository statement;

  CourierBalance owing({
    String uid = 'c1',
    String name = 'كابتن محمود',
    int owed = 4500,
    bool isActive = true,
  }) =>
      CourierBalance(
        uid: uid,
        name: name,
        phone: '01011111111',
        owed: owed,
        isActive: isActive,
      );

  Future<void> pump(
    WidgetTester tester, {
    List<CourierBalance> balances = const [],
    Map<String, int> owed = const {'c1': 4500},
    Failure? failure,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    statement = FakeCourierStatementRepository(
      balances: balances,
      owed: owed,
      failure: failure,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courierStatementRepositoryProvider.overrideWithValue(statement),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: CourierBillingScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the frozen pair', () {
    test('reads back what it wrote', () {
      const pending = PendingCollection(receiptId: 'r1', amount: 4500);

      expect(PendingCollection.decode(pending.encode())?.amount, 4500);
      expect(PendingCollection.decode(pending.encode())?.receiptId, 'r1');
    });

    test('refuses a record with only half of it', () {
      // The id is written first, so a half-written record leaves the id set and the
      // amount missing — an editable field and no notice, which is how a new figure gets
      // sent under an old receipt id. Both or neither.
      expect(PendingCollection.decode('{"receiptId":"r1"}'), isNull);
      expect(PendingCollection.decode('{"amount":4500}'), isNull);
      expect(PendingCollection.decode('{"receiptId":"r1","amount":"4500"}'), isNull);
      expect(PendingCollection.decode('{"receiptId":"","amount":4500}'), isNull);
    });

    test('treats unreadable storage as no record rather than throwing', () {
      expect(PendingCollection.decode('not json at all'), isNull);
      expect(PendingCollection.decode(null), isNull);
    });
  });

  group('who owes what', () {
    testWidgets('lists a courier with a balance', (tester) async {
      await pump(tester, balances: [owing()]);

      expect(find.byKey(CourierBillingScreen.rowKey('c1')), findsOneWidget);
      expect(find.text('كابتن محمود'), findsOneWidget);
      expect(find.text('عليه'), findsOneWidget);
    });

    testWidgets('says credit in words rather than with a minus sign', (tester) async {
      await pump(tester, balances: [owing(owed: -1000)]);

      expect(find.text('رصيد ليه'), findsOneWidget);
      expect(find.textContaining('-'), findsNothing);
      // Nothing to collect from somebody the platform owes.
      expect(find.byKey(CourierBillingScreen.collectKey('c1')), findsNothing);
    });

    testWidgets('marks a dismissed courier who still owes', (tester) async {
      // The debt survives them leaving. Saying so stops the owner ringing a dead number
      // and assuming the balance is a mistake.
      await pump(tester, balances: [owing(isActive: false)]);

      expect(find.text('موقوف'), findsOneWidget);
    });

    testWidgets('says everybody is square rather than drawing an empty page',
        (tester) async {
      await pump(tester, balances: const []);

      expect(find.byKey(CourierBillingScreen.emptyKey), findsOneWidget);
    });

    testWidgets('offers a way out when the list will not load', (tester) async {
      await pump(tester, failure: const OfflineFailure());

      expect(find.byType(LuqmaErrorView), findsOneWidget);
      expect(find.byKey(CourierBillingScreen.emptyKey), findsNothing);
    });
  });

  group('recording the cash', () {
    testWidgets('lowers the balance and says what is left', (tester) async {
      await pump(tester, balances: [owing()]);

      await tester.tap(find.byKey(CourierBillingScreen.collectKey('c1')));
      await tester.pumpAndSettle();
      // Prefilled with what is owed, because that is what the owner is usually handed.
      await tester.enterText(find.byKey(CourierBillingScreen.amountKey), '30');
      await tester.tap(find.byKey(CourierBillingScreen.confirmKey));
      await tester.pumpAndSettle();

      expect(statement.recorded.single.amount, 3000);
      expect(statement.recorded.single.courierUid, 'c1');
      expect(find.textContaining('فاضل عليه'), findsOneWidget);
    });

    testWidgets('a retry carries the first attempt’s receipt, not a new one',
        (tester) async {
      // The invariant, asserted directly. The reply not arriving is not the same as the
      // money not moving, so the second attempt has to reuse the id — that is what lets
      // the server answer with the receipt it already holds instead of collecting again.
      await pump(tester, balances: [owing()]);
      statement.failure = const OfflineFailure();

      await tester.tap(find.byKey(CourierBillingScreen.collectKey('c1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(CourierBillingScreen.amountKey), '45');
      await tester.tap(find.byKey(CourierBillingScreen.confirmKey));
      await tester.pumpAndSettle();

      statement.failure = null;
      await tester.tap(find.byKey(CourierBillingScreen.collectKey('c1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(CourierBillingScreen.confirmKey));
      await tester.pumpAndSettle();

      expect(statement.receiptIds.length, 2);
      expect(statement.receiptIds.first, isNotNull);
      expect(statement.receiptIds[1], statement.receiptIds.first,
          reason: 'a retry that mints a new id collects the same cash twice');
      // And the amount went with it: 45 ج, not whatever the field was reset to.
      expect(statement.recorded.single.amount, 4500);
    });

    testWidgets('keeps the attempt when the line drops, and freezes its amount',
        (tester) async {
      await pump(tester, balances: [owing()]);
      statement.failure = const OfflineFailure();

      await tester.tap(find.byKey(CourierBillingScreen.collectKey('c1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(CourierBillingScreen.amountKey), '45');
      await tester.tap(find.byKey(CourierBillingScreen.confirmKey));
      await tester.pumpAndSettle();

      expect(find.textContaining('التحصيل محفوظ'), findsOneWidget);

      // Reopening names the attempt and will not let its figure be edited: an editable
      // field on a retry is how a new amount gets sent under an old receipt id.
      statement.failure = null;
      await tester.tap(find.byKey(CourierBillingScreen.collectKey('c1')));
      await tester.pumpAndSettle();

      expect(find.byKey(CourierBillingScreen.frozenKey), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(CourierBillingScreen.amountKey),
      );
      expect(field.readOnly, isTrue);
    });

    testWidgets('refuses an empty or zero amount instead of sending it', (tester) async {
      await pump(tester, balances: [owing()]);

      await tester.tap(find.byKey(CourierBillingScreen.collectKey('c1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(CourierBillingScreen.amountKey), '0');
      await tester.tap(find.byKey(CourierBillingScreen.confirmKey));
      await tester.pumpAndSettle();

      expect(statement.recorded, isEmpty);
      // The dialog stays open rather than closing on a figure it refused to send.
      expect(find.byKey(CourierBillingScreen.confirmKey), findsOneWidget);
    });
  });
}
