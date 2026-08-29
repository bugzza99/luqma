import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:postgrest/postgrest.dart';

/// The reason a typed failure exists at all: with cash on delivery and patchy mobile
/// data, "you're offline", "you're not allowed to do that" and "that meal just sold out"
/// have to reach the customer as three different sentences. A single catch block that
/// says "something went wrong" is what makes an app feel broken.
void main() {
  group('Failure.from', () {
    test('a Postgrest permission denial is a permission failure', () {
      final failure = Failure.from(
        PostgrestException(code: '42501', message: 'permission denied'),
      );
      expect(failure, isA<PermissionFailure>());
    });

    test('the order function raising P0002 is a not-found failure', () {
      final failure = Failure.from(
        PostgrestException(code: 'P0002', message: 'merchant not found'),
      );
      expect(failure, isA<NotFoundFailure>());
    });

    // Two people tapping the last portion at the same moment is a conflict — someone
    // got there first — and that is the sentence the customer is shown.
    test('sold out reads as a conflict', () {
      final failure = Failure.from(
        PostgrestException(code: 'P0001', message: 'sold out'),
      );
      expect(failure, isA<ConflictFailure>());
    });

    // A refused coupon now carries its own reason rather than collapsing into a
    // conflict - the checkout screen says which sentence to show.
    test('a refused coupon carries its reason as a coupon failure', () {
      final failure = Failure.from(
        PostgrestException(code: 'P0001', message: 'coupon: alreadyUsed'),
      );
      expect(failure, isA<CouponFailure>());
      expect((failure as CouponFailure).reason, CouponRejection.alreadyUsed);
    });

    // A daily meal that is no longer published refuses a reservation the same way a
    // sold-out one does: the customer is told somebody got there first, not shown a
    // generic failure.
    test('a closed or draft daily meal reads as a conflict', () {
      final failure = Failure.from(
        PostgrestException(
          code: 'P0001',
          message: 'meal not accepting reservations',
        ),
      );
      expect(failure, isA<ConflictFailure>());
    });

    // A merchant who does not serve the customer's zone refuses the order the same way
    // any other "the world changed" refusal does.
    test('an out-of-range zone reads as a conflict', () {
      final failure = Failure.from(
        PostgrestException(
          code: 'P0001',
          message: 'merchant does not deliver to this zone',
        ),
      );
      expect(failure, isA<ConflictFailure>());
    });

    // A coupon refusal names its reason, and the failure carries it to whichever
    // sentence the checkout screen shows.
    test('a named coupon refusal carries its reason', () {
      final failure = Failure.from(
        PostgrestException(code: 'P0001', message: 'coupon: expired'),
      );
      expect(failure, isA<CouponFailure>());
      expect((failure as CouponFailure).reason, CouponRejection.expired);
    });

    test('an unknown coupon reason falls back to notFound', () {
      final failure = Failure.from(
        PostgrestException(code: 'P0001', message: 'coupon: somethingNew'),
      );
      expect((failure as CouponFailure).reason, CouponRejection.notFound);
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

    test('guard turns a thrown Postgrest error into an err result', () async {
      final result = await Result.guard<int>(() async {
        throw const PostgrestException(code: '42501', message: 'permission denied');
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
