import 'package:admin_app/src/billing/courier_billing_screen.dart';
import 'package:admin_app/src/billing/pending_collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
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
  }) => CourierBalance(
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
    FakeCourierStatementRepository? repository,

    /// Who is looking. The owner, unless a test is about somebody else.
    StaffIdentity who = _platformAdmin,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();

    statement =
        repository ??
        FakeCourierStatementRepository(
          balances: balances,
          owed: owed,
          failure: failure,
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          courierStatementRepositoryProvider.overrideWithValue(statement),
          staffIdentityProvider.overrideWithValue(who),
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

  group('the frozen record', () {
    PendingCollection? read(
      String? json, {
      PendingKind kind = PendingKind.courier,
      String subject = 'c1',
    }) => PendingCollection.decode(json, kind: kind, subjectId: subject);

    test('reads back what it wrote', () {
      const pending = PendingCollection(
        receiptId: 'r1',
        kind: PendingKind.courier,
        subjectId: 'c1',
        amount: 4500,
        expectedBalance: 5000,
      );

      expect(read(pending.encode())?.amount, 4500);
      expect(read(pending.encode())?.receiptId, 'r1');
      expect(read(pending.encode())?.expectedBalance, 5000);
    });

    test('refuses a record with only half of it', () {
      // The id is written first, so a half-written record leaves the id set and the rest
      // missing — an editable field and no notice, which is how new figures get sent
      // under an old receipt id. All or nothing.
      expect(read('{"receiptId":"r1"}'), isNull);
      expect(read('{"amount":4500}'), isNull);
      expect(read('{"receiptId":"r1","amount":"4500"}'), isNull);
      expect(read('{"receiptId":"","amount":4500}'), isNull);
    });

    test('refuses a record belonging to another kind or another subject', () {
      // One receipt paying for the wrong thing is the failure this guards. A shop's
      // top-up must never be replayable as a courier's collection.
      const topUp = PendingCollection(
        receiptId: 'r1',
        kind: PendingKind.topUp,
        subjectId: 'm1',
        amount: 4500,
      );

      expect(
        read(topUp.encode()),
        isNull,
        reason: 'wrong kind and wrong subject',
      );
      expect(
        read(topUp.encode(), kind: PendingKind.topUp),
        isNull,
        reason: 'right kind, wrong subject',
      );
      expect(
        read(topUp.encode(), kind: PendingKind.topUp, subject: 'm1'),
        isNotNull,
      );
    });

    test('a subscription attempt without its term is not a record', () {
      // The server is told a plan and a number of months. An attempt that cannot say
      // both is one it cannot be told about, so it is corrupt rather than partial.
      expect(
        read(
          '{"receiptId":"r1","amount":4500}',
          kind: PendingKind.subscription,
          subject: 'm1',
        ),
        isNull,
      );
      expect(
        read(
          '{"receiptId":"r1","amount":4500,"planId":"p1","months":0}',
          kind: PendingKind.subscription,
          subject: 'm1',
        ),
        isNull,
      );
      expect(
        read(
          '{"receiptId":"r1","amount":4500,"planId":"p1","months":3}',
          kind: PendingKind.subscription,
          subject: 'm1',
        ),
        isNotNull,
      );
    });

    test('still reads a record written before kinds were stored', () {
      // An admin phone may be holding one right now. Its key already said which kind and
      // which subject, so it is trusted to be what its key says — losing it would mean
      // taking the same cash twice.
      expect(read('{"receiptId":"r1","amount":4500}')?.receiptId, 'r1');
    });

    test('treats unreadable storage as no record rather than throwing', () {
      expect(read('not json at all'), isNull);
      expect(read(null), isNull);
    });
  });

  group('who owes what', () {
    testWidgets('lists a courier with a balance', (tester) async {
      await pump(tester, balances: [owing()]);

      expect(find.byKey(CourierBillingScreen.rowKey('c1')), findsOneWidget);
      expect(find.text('كابتن محمود'), findsOneWidget);
      expect(find.text('عليه'), findsOneWidget);
    });

    testWidgets('says credit in words rather than with a minus sign', (
      tester,
    ) async {
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

    testWidgets('says everybody is square rather than drawing an empty page', (
      tester,
    ) async {
      await pump(tester, balances: const []);

      expect(find.byKey(CourierBillingScreen.emptyKey), findsOneWidget);
    });

    testWidgets('offers a way out when the list will not load', (tester) async {
      await pump(tester, failure: const OfflineFailure());

      expect(find.byType(LuqmaErrorView), findsOneWidget);
      expect(find.byKey(CourierBillingScreen.emptyKey), findsNothing);
    });
  });

  // The route is `adminOnly` in the navigation, but a route is reachable by its path —
  // and the server refuses `record_courier_payment` to a moderator, so a button here would
  // only ever end in «مقدرناش نسجّل التحصيل», which reads as a broken connection.
  group('who may record the cash', () {
    testWidgets('a moderator reads the balance and is offered no collection', (tester) async {
      await pump(
        tester,
        balances: [owing()],
        who: const StaffIdentity(
          uid: 'mod1',
          role: StaffRole.moderator,
          scope: StaffScope.platform,
          isAdmin: true,
        ),
      );

      expect(find.text('عليه'), findsOneWidget);
      expect(find.byKey(CourierBillingScreen.collectKey('c1')), findsNothing);
      expect(find.byKey(CourierBillingScreen.moderatorNoteKey), findsOneWidget);
    });

    testWidgets('a platform admin is offered it', (tester) async {
      await pump(tester, balances: [owing()]);

      expect(find.byKey(CourierBillingScreen.collectKey('c1')), findsOneWidget);
      expect(find.byKey(CourierBillingScreen.moderatorNoteKey), findsNothing);
    });

    // An identity still resolving is neither. Hiding on «not a platform admin» would take
    // the till from the owner for the moment a token spends refreshing, cash in hand.
    testWidgets('an identity still resolving takes nothing away', (tester) async {
      await pump(tester, balances: [owing()], who: StaffIdentity.none);

      expect(find.byKey(CourierBillingScreen.collectKey('c1')), findsOneWidget);
    });
  });

  group('recording the cash', () {
    testWidgets('a repeated tap opens only one collection', (tester) async {
      await pump(tester, balances: [owing()]);

      final button = find.byKey(CourierBillingScreen.collectKey('c1'));
      await tester.tap(button);
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        find.byKey(CourierBillingScreen.amountKey, skipOffstage: false),
        findsOneWidget,
      );
    });

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

    testWidgets('a retry carries the first attempt’s receipt, not a new one', (
      tester,
    ) async {
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
      expect(
        statement.receiptIds[1],
        statement.receiptIds.first,
        reason: 'a retry that mints a new id collects the same cash twice',
      );
      // And the amount went with it: 45 ج, not whatever the field was reset to.
      expect(statement.recorded.single.amount, 4500);
    });

    testWidgets('keeps the attempt when the line drops, and freezes its amount', (
      tester,
    ) async {
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

    testWidgets('refuses an empty or zero amount instead of sending it', (
      tester,
    ) async {
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

    testWidgets('rejects a stale balance and starts the next attempt fresh', (
      tester,
    ) async {
      final repo = _BalanceChangedOnce(
        balances: [owing()],
        owed: const {'c1': 4500},
      );
      await pump(tester, repository: repo);

      await tester.tap(find.byKey(CourierBillingScreen.collectKey('c1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(CourierBillingScreen.amountKey), '45');
      await tester.tap(find.byKey(CourierBillingScreen.confirmKey));
      await tester.pumpAndSettle();

      expect(
        repo.expectedBalances.single,
        4500,
        reason:
            'the server must compare the row with the figure the admin acted on',
      );
      expect(find.textContaining('الحساب اتغيّر'), findsOneWidget);

      await tester.tap(find.byKey(CourierBillingScreen.collectKey('c1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(CourierBillingScreen.frozenKey),
        findsNothing,
        reason:
            'a definite server rejection moved no money and must not be retried',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(CourierBillingScreen.amountKey))
            .readOnly,
        isFalse,
      );
    });
  });

  group('a reply has to be about this payment', () {
    test('a second call with the same receipt is marked as a replay', () async {
      // Where this is checkable. Through the screen it is not: a successful collection
      // clears the pending record, so the next tap is a genuinely new payment with a new
      // receipt. The replay is a server behaviour and the fake has to agree with it, or a
      // screen gets written against a reply production never sends.
      final repo = FakeCourierStatementRepository(owed: {'c1': 4500});

      final first = (await repo.recordPayment(
        courierUid: 'c1',
        amount: 4500,
        receiptId: 'r1',
      )).valueOrNull;
      final again = (await repo.recordPayment(
        courierUid: 'c1',
        amount: 4500,
        receiptId: 'r1',
      )).valueOrNull;

      expect(first?.repeated, isFalse);
      expect(
        again?.repeated,
        isTrue,
        reason: 'the server already held this receipt',
      );
      expect(
        again?.remaining,
        first?.remaining,
        reason: 'and nothing moved again',
      );
    });

    test('refuses a reply that names another receipt, courier or amount', () {
      // The whole point of H-13: a reply carrying only a balance cannot be checked, so a
      // stale pending record and a later collection look identical to the screen.
      const reply = CourierCollection(
        remaining: 0,
        receiptId: 'r1',
        courierUid: 'c1',
        amount: 4500,
        repeated: false,
      );

      expect(
        reply.answers(receiptId: 'r1', courierUid: 'c1', amount: 4500),
        isTrue,
      );
      expect(
        reply.answers(receiptId: 'r2', courierUid: 'c1', amount: 4500),
        isFalse,
      );
      expect(
        reply.answers(receiptId: 'r1', courierUid: 'c2', amount: 4500),
        isFalse,
      );
      expect(
        reply.answers(receiptId: 'r1', courierUid: 'c1', amount: 9000),
        isFalse,
      );
    });

    test('trusts a server too old to name the receipt', () {
      // An older server cannot be made to say it, and refusing every reply from one
      // would stop collections working the day an APK runs ahead of the database.
      const older = CourierCollection(
        remaining: 0,
        receiptId: null,
        courierUid: null,
        amount: null,
        repeated: false,
      );

      expect(
        older.answers(receiptId: 'r1', courierUid: 'c1', amount: 4500),
        isTrue,
      );
    });

    test('reads the identity off the reply', () {
      final reply = CourierCollection.fromJson(const {
        'receiptId': 'r1',
        'courierUid': 'c1',
        'amount': 4500,
        'remaining': 500,
        'repeated': true,
        'createdAt': '2026-09-21T10:00:00Z',
      });

      expect(reply.repeated, isTrue);
      expect(reply.amount, 4500);
      expect(reply.remaining, 500);
      expect(reply.createdAt, isNotNull);
    });
  });
}

const _platformAdmin = StaffIdentity(
  uid: 'admin1',
  role: StaffRole.admin,
  scope: StaffScope.platform,
  isAdmin: true,
);

class _BalanceChangedOnce extends FakeCourierStatementRepository {
  _BalanceChangedOnce({required super.balances, required super.owed});

  final List<int?> expectedBalances = [];
  bool _changed = true;

  @override
  Future<Result<CourierCollection>> recordPayment({
    required String courierUid,
    required int amount,
    String? note,
    String? receiptId,
    int? expectedBalance,
  }) async {
    expectedBalances.add(expectedBalance);
    if (_changed) {
      _changed = false;
      return const Result.err(ConflictFailure());
    }
    return super.recordPayment(
      courierUid: courierUid,
      amount: amount,
      note: note,
      receiptId: receiptId,
      expectedBalance: expectedBalance,
    );
  }
}
