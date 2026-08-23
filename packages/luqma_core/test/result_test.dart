import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The reason a typed failure exists at all: with cash on delivery and patchy mobile
/// data, "you're offline", "you're not allowed to do that" and "that meal just sold out"
/// have to reach the customer as three different sentences. A single catch block that
/// says "something went wrong" is what makes an app feel broken.
void main() {
  group('Failure.from', () {
    test('a Firestore unavailable error is an offline failure', () {
      final failure = Failure.from(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
      expect(failure, isA<OfflineFailure>());
    });

    test('a Firestore permission-denied error is a permission failure', () {
      final failure = Failure.from(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      expect(failure, isA<PermissionFailure>());
    });

    test('a Firestore not-found error is a not-found failure', () {
      final failure = Failure.from(
        FirebaseException(plugin: 'cloud_firestore', code: 'not-found'),
      );
      expect(failure, isA<NotFoundFailure>());
    });

    test('a network-request-failed auth error is also an offline failure', () {
      final failure = Failure.from(
        FirebaseAuthException(code: 'network-request-failed'),
      );
      expect(failure, isA<OfflineFailure>());
    });

    test('an unrecognised error keeps the original for the crash report', () {
      final original = StateError('something we have never seen');
      final failure = Failure.from(original);
      expect(failure, isA<UnknownFailure>());
      expect((failure as UnknownFailure).cause, same(original));
    });

    test('a failure passes through unchanged rather than being wrapped again', () {
      const original = OfflineFailure();
      expect(Failure.from(original), same(original));
    });
  });

  group('Result', () {
    test('ok carries the value', () {
      const result = Result<int>.ok(7);
      expect(result.valueOrNull, 7);
      expect(result.failureOrNull, isNull);
      expect(result.isOk, isTrue);
    });

    test('err carries the failure', () {
      const result = Result<int>.err(OfflineFailure());
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, isA<OfflineFailure>());
      expect(result.isOk, isFalse);
    });

    test('guard turns a thrown Firebase error into an err result', () async {
      final result = await Result.guard<int>(() async {
        throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
      });
      expect(result.failureOrNull, isA<PermissionFailure>());
    });

    test('guard returns ok when nothing throws', () async {
      final result = await Result.guard<int>(() async => 42);
      expect(result.valueOrNull, 42);
    });

    test('map transforms an ok value and leaves an err untouched', () {
      const ok = Result<int>.ok(3);
      const err = Result<int>.err(NotFoundFailure());
      expect(ok.map((v) => v * 2).valueOrNull, 6);
      expect(err.map((v) => v * 2).failureOrNull, isA<NotFoundFailure>());
    });
  });
}
