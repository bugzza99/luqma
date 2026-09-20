import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// A courier's papers, on the phone's side of the boundary.
///
/// The database owns the rules these tests care about — `supabase/test/local` and
/// `supabase/test/stack` are where retention and the policies are argued with. What is
/// left for here is the part a screen reads: how long is left, and whether the fake
/// refuses the things the server refuses. The second matters more than it looks:
/// a fake more permissive than Postgres is how this feature's predecessor got a green
/// suite for a screen nobody could use.
void main() {
  StaffDocuments papers({DateTime? purgeAfter, String uid = 'rider'}) => StaffDocuments(
        uid: uid,
        idFrontPath: '$uid/id-front.jpg',
        idBackPath: '$uid/id-back.jpg',
        selfiePath: '$uid/selfie.jpg',
        uploadedAt: DateTime(2026, 9, 1),
        purgeAfter: purgeAfter,
      );

  group('reading a row', () {
    test('takes the three paths and the clock off the row', () {
      final row = StaffDocuments.fromRow(const {
        'uid': 'rider',
        'id_front_path': 'rider/id-front.jpg',
        'id_back_path': 'rider/id-back.jpg',
        'selfie_path': 'rider/selfie.jpg',
        'uploaded_at': '2026-09-01T10:00:00Z',
        'purge_after': '2026-10-01T10:00:00Z',
      });

      expect(row.uid, 'rider');
      expect(row.paths, [
        'rider/id-front.jpg',
        'rider/id-back.jpg',
        'rider/selfie.jpg',
      ]);
      expect(row.purgeAfter, isNotNull);
    });

    test('a null clock is being kept, not a missing value', () {
      final row = StaffDocuments.fromRow(const {
        'uid': 'rider',
        'id_front_path': 'a',
        'id_back_path': 'b',
        'selfie_path': 'c',
        'uploaded_at': '2026-09-01T10:00:00Z',
        'purge_after': null,
      });

      expect(row.purgeAfter, isNull);
      expect(row.daysLeftAt(DateTime(2026, 9, 2)), isNull);
    });
  });

  group('how long is left', () {
    final now = DateTime(2026, 9, 20, 12);

    test('counts whole days, rounding up', () {
      // 29 days and an hour is "30 days left" to somebody reading a screen. Rounding
      // down would say 29 on the day they were told thirty.
      final left = papers(purgeAfter: now.add(const Duration(days: 29, hours: 1)))
          .daysLeftAt(now);

      expect(left, 30);
    });

    test('an exact number of days is that many', () {
      expect(papers(purgeAfter: now.add(const Duration(days: 7))).daysLeftAt(now), 7);
    });

    test('never goes below zero once the moment has passed', () {
      // The sweep runs nightly, so papers can outlive their own deadline by hours. A
      // negative number on that screen reads as a bug rather than as "any minute now".
      expect(
        papers(purgeAfter: now.subtract(const Duration(hours: 6))).daysLeftAt(now),
        0,
      );
    });

    test('says whether the clock is running at all', () {
      expect(papers(purgeAfter: now).isExpiringAt(now), isTrue);
      expect(papers().isExpiringAt(now), isFalse);
    });
  });

  group('the fake keeps the boundary the server keeps', () {
    Uint8List bytes() => Uint8List.fromList([1, 2, 3]);

    test('hands in three photographs for the signed-in person', () async {
      final repo = FakeStaffDocumentsRepository(signedInUid: 'rider');

      final result = await repo.handIn(
        idFront: bytes(),
        idBack: bytes(),
        selfie: bytes(),
      );

      expect(result.valueOrNull?.uid, 'rider');
      expect(repo.handIns, 1);
      expect((await repo.mine()).valueOrNull, isNotNull);
    });

    test('refuses a hand-in with nobody signed in', () async {
      final repo = FakeStaffDocumentsRepository();

      final result = await repo.handIn(
        idFront: bytes(),
        idBack: bytes(),
        selfie: bytes(),
      );

      expect(result.failureOrNull, isA<PermissionFailure>());
    });

    test('shows a person nothing of somebody else\'s', () async {
      final repo = FakeStaffDocumentsRepository(
        signedInUid: 'rider',
        seed: {'other': papers(uid: 'other')},
      );

      // Null rather than a refusal, because that is what a policy does: it filters the
      // row away rather than answering. A fake that threw here would let a screen be
      // written against an error state production never produces.
      expect((await repo.forPerson('other')).valueOrNull, isNull);
    });

    test('lets a reader the policy allows see them', () async {
      final repo = FakeStaffDocumentsRepository(
        signedInUid: 'admin',
        seed: {'other': papers(uid: 'other')},
      )..readable.add('other');

      expect((await repo.forPerson('other')).valueOrNull?.uid, 'other');
    });

    test('handing in again does not restart a clock already running', () async {
      // The database refuses to restart it; the fake has to agree or a screen tested
      // here will promise a reprieve the server will not give.
      final started = DateTime(2026, 10, 1);
      final repo = FakeStaffDocumentsRepository(
        signedInUid: 'rider',
        seed: {'rider': papers(purgeAfter: started)},
      );

      await repo.handIn(idFront: bytes(), idBack: bytes(), selfie: bytes());

      expect((await repo.mine()).valueOrNull?.purgeAfter, started);
    });

    test('reports a failure the way the real one does', () async {
      final repo = FakeStaffDocumentsRepository(signedInUid: 'rider')
        ..failWith = const OfflineFailure();

      final result = await repo.handIn(
        idFront: bytes(),
        idBack: bytes(),
        selfie: bytes(),
      );

      expect(result.failureOrNull, isA<OfflineFailure>());
    });

    test('signs a link that expires', () async {
      final repo = FakeStaffDocumentsRepository(signedInUid: 'rider');

      final url = (await repo.signedUrl('rider/selfie.jpg')).valueOrNull;

      expect(url, contains('rider/selfie.jpg'));
      expect(url, contains('expires='));
    });
  });
}
