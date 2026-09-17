import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:postgrest/postgrest.dart';

void main() {
  group('StaffApplication model', () {
    test('fromRow maps snake_case postgres row into StaffApplication', () {
      final now = DateTime.parse('2026-09-27T10:30:00Z');
      final row = {
        'id': 'app-1',
        'kind': 'courier',
        'name': 'محمود',
        'phone': '01000000100',
        'note': 'بغطي إدكو بحري والوسط',
        'status': 'pending',
        'created_at': now.toIso8601String(),
        'reviewed_at': null,
        'reviewed_by': null,
        'review_note': null,
        'staff_uid': null,
      };

      final app = StaffApplication.fromRow(row);
      expect(app.id, 'app-1');
      expect(app.kind, StaffApplicationKind.courier);
      expect(app.name, 'محمود');
      expect(app.phone, '01000000100');
      expect(app.note, 'بغطي إدكو بحري والوسط');
      expect(app.status, StaffApplicationStatus.pending);
      expect(app.isPending, isTrue);
      expect(app.isApproved, isFalse);
      expect(app.isRejected, isFalse);
      expect(app.createdAt, now.toLocal());
      expect(app.reviewedAt, isNull);
      expect(app.reviewedBy, isNull);
      expect(app.reviewNote, isNull);
      expect(app.staffUid, isNull);
    });

    test('fromRow maps restaurant and homeKitchen kinds and decided statuses', () {
      final rowRestaurant = {
        'id': 'app-2',
        'kind': 'restaurant',
        'name': 'مطعم الشاطئ',
        'phone': '01000000101',
        'status': 'approved',
        'reviewed_at': '2026-09-27T12:00:00Z',
        'reviewed_by': 'admin-1',
        'review_note': 'تم التواصل والاتفاق',
        'staff_uid': 'staff-1',
      };
      final appRestaurant = StaffApplication.fromRow(rowRestaurant);
      expect(appRestaurant.kind, StaffApplicationKind.restaurant);
      expect(appRestaurant.status, StaffApplicationStatus.approved);
      expect(appRestaurant.isApproved, isTrue);
      expect(appRestaurant.staffUid, 'staff-1');

      final rowKitchen = {
        'id': 'app-3',
        'kind': 'homeKitchen',
        'name': 'مطبخ أم أحمد',
        'phone': '01000000102',
        'status': 'rejected',
        'reviewed_at': '2026-09-27T13:00:00Z',
        'reviewed_by': 'admin-1',
        'review_note': 'خارج نطاق التغطية حالياً',
      };
      final appKitchen = StaffApplication.fromRow(rowKitchen);
      expect(appKitchen.kind, StaffApplicationKind.homeKitchen);
      expect(appKitchen.status, StaffApplicationStatus.rejected);
      expect(appKitchen.isRejected, isTrue);
    });
  });

  group('FakeStaffApplicationRepository', () {
    late FakeStaffApplicationRepository repo;

    setUp(() {
      repo = FakeStaffApplicationRepository();
    });

    tearDown(() {
      repo.dispose();
    });

    test('apply creates a pending application and normalizes the phone number', () async {
      final res = await repo.apply(
        kind: StaffApplicationKind.courier,
        name: ' محمود ',
        phone: ' ٠١٠٠٠٠٠٠١٠٠ ',
        note: ' سواق موتوسيكل ',
      );

      expect(res.isOk, isTrue);
      expect(repo.all, hasLength(1));
      final app = repo.all.first;
      expect(app.kind, StaffApplicationKind.courier);
      expect(app.name, 'محمود');
      expect(app.phone, '01000000100');
      expect(app.note, 'سواق موتوسيكل');
      expect(app.status, StaffApplicationStatus.pending);
    });

    test('apply treats empty note as null', () async {
      final res = await repo.apply(
        kind: StaffApplicationKind.restaurant,
        name: 'مطعم جديد',
        phone: '01000000200',
        note: '   ',
      );

      expect(res.isOk, isTrue);
      expect(repo.all.first.note, isNull);
    });

    test('refuses a second open application from the same number', () async {
      await repo.apply(
        kind: StaffApplicationKind.courier,
        name: 'محمود',
        phone: '01000000100',
      );

      final second = await repo.apply(
        kind: StaffApplicationKind.restaurant,
        name: 'محمود تاني',
        phone: '٠١٠٠٠٠٠٠١٠٠',
      );

      expect(second.isOk, isFalse);
      expect(second.failureOrNull, isA<AlreadyAppliedFailure>());
    });

    test('allows a number to apply again once the previous application was decided', () async {
      await repo.apply(
        kind: StaffApplicationKind.courier,
        name: 'محمود',
        phone: '01000000100',
      );
      final firstId = repo.all.first.id;

      await repo.review(firstId, status: StaffApplicationStatus.rejected, note: 'غير متاح');

      final second = await repo.apply(
        kind: StaffApplicationKind.courier,
        name: 'محمود بعد فترة',
        phone: '01000000100',
      );

      expect(second.isOk, isTrue);
      expect(repo.all, hasLength(2));
    });

    test('watchPending streams pending applications newest first', () async {
      final stream = repo.watchPending();

      final firstEmit = await stream.first;
      expect(firstEmit, isEmpty);

      await repo.apply(
        kind: StaffApplicationKind.courier,
        name: 'أول متقدم',
        phone: '01000000001',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await repo.apply(
        kind: StaffApplicationKind.restaurant,
        name: 'تاني متقدم',
        phone: '01000000002',
      );

      final queue = await repo.watchPending().first;
      expect(queue, hasLength(2));
      expect(queue[0].name, 'تاني متقدم');
      expect(queue[1].name, 'أول متقدم');
    });

    test('review rejects and removes from pending queue', () async {
      await repo.apply(
        kind: StaffApplicationKind.courier,
        name: 'محمود',
        phone: '01000000100',
      );
      final id = repo.all.first.id;

      final reviewRes = await repo.review(
        id,
        status: StaffApplicationStatus.rejected,
        note: 'اتكلمنا ومش مناسب',
      );

      expect(reviewRes.isOk, isTrue);
      final decided = repo.all.first;
      expect(decided.status, StaffApplicationStatus.rejected);
      expect(decided.reviewNote, 'اتكلمنا ومش مناسب');
      expect(decided.staffUid, isNull);
      expect(decided.reviewedAt, isNotNull);

      final pending = await repo.watchPending().first;
      expect(pending, isEmpty);
    });

    // 2026-09-18: approving through `review` is what stamped the first real merchant
    // `approved` and created nobody. The server refuses it now, and so does this.
    test('review cannot approve any more — approval makes the account', () async {
      await repo.apply(
        kind: StaffApplicationKind.restaurant,
        name: 'ابو حاتم',
        phone: '01000000100',
        applicantUid: 'u-1',
      );
      final id = repo.all.first.id;

      final refused = await repo.review(
        id,
        status: StaffApplicationStatus.approved,
        staffUid: 'staff-new',
      );

      expect(refused.failureOrNull, isA<ConflictFailure>());
      expect(repo.all.first.status, StaffApplicationStatus.pending);
      expect(repo.accounts, isEmpty);
    });

    test('approve makes one account per person, and refuses a second', () async {
      await repo.apply(
        kind: StaffApplicationKind.restaurant,
        name: 'ابو حاتم',
        phone: '01000000100',
        applicantUid: 'u-1',
      );
      final first = repo.all.first.id;

      expect((await repo.approve(first, zoneId: 'z1')).isOk, isTrue);
      expect(repo.accounts, {'u-1': null});
      expect(repo.all.first.staffUid, 'u-1');

      // The same person applying again after being approved: the server answers «that
      // person already has a staff account».
      await repo.apply(
        kind: StaffApplicationKind.restaurant,
        name: 'ابو حاتم',
        phone: '01000000101',
        applicantUid: 'u-1',
      );
      final second =
          repo.all.firstWhere((a) => a.isPending && a.phone == '01000000101').id;
      final refused = await repo.approve(second, zoneId: 'z1');
      expect(refused.failureOrNull, isA<ConflictFailure>());
    });

    test('approve refuses an application with no account behind it', () async {
      await repo.apply(
        kind: StaffApplicationKind.restaurant,
        name: 'ابو حاتم',
        phone: '01000000100',
      );
      final id = repo.all.first.id;

      final refused = await repo.approve(id, zoneId: 'z1');
      expect(refused.failureOrNull, isA<ValidationFailure>());
      expect(repo.all.first.status, StaffApplicationStatus.pending);
    });

    test('review refuses to decide an already decided or missing application', () async {
      await repo.apply(
        kind: StaffApplicationKind.courier,
        name: 'محمود',
        phone: '01000000100',
      );
      final id = repo.all.first.id;
      await repo.review(id, status: StaffApplicationStatus.rejected);

      final secondReview = await repo.review(id, status: StaffApplicationStatus.rejected);
      expect(secondReview.failureOrNull, isA<NotFoundFailure>());

      final missingReview =
          await repo.review('non-existent', status: StaffApplicationStatus.rejected);
      expect(missingReview.failureOrNull, isA<NotFoundFailure>());
    });

    test('review note limit rejects atomically and counts Unicode characters', () async {
      await repo.apply(kind: StaffApplicationKind.courier,
        name: 'Rider', phone: '01000000100');
      final id = (await repo.watchPending().first).single.id;
      final refused = await repo.review(id,
        status: StaffApplicationStatus.rejected, note: '😀' * 501);
      expect(refused.failureOrNull, isA<ConflictFailure>());
      final pending = (await repo.watchPending().first).single;
      expect(pending.reviewedAt, isNull);
      expect(pending.reviewNote, isNull);

      final accepted = await repo.review(id,
        status: StaffApplicationStatus.rejected, note: '  ${'😀' * 500}  ');
      expect(accepted.isOk, isTrue);
      expect(await repo.watchPending().first, isEmpty);
    });
  });

  group('Failure classification and ErrorView', () {
    test('Failure.from maps unique constraint on staff_applications_one_open to AlreadyAppliedFailure', () {
      final pgError = PostgrestException(
        message: 'duplicate key value violates unique constraint "staff_applications_one_open"',
        code: '23505',
      );

      final failure = Failure.from(pgError);
      expect(failure, isA<AlreadyAppliedFailure>());
    });

    testWidgets('LuqmaErrorView renders specific Arabic sentence for AlreadyAppliedFailure', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: LuqmaErrorView(failure: AlreadyAppliedFailure()),
            ),
          ),
        ),
      );

      expect(find.text('في طلب متقدم بالرقم ده بالفعل — حد من الإدارة هيكلمك'), findsOneWidget);
    });
  });
}
