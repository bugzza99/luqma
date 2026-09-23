import 'package:postgrest/postgrest.dart' show PostgrestException;

import 'models/coupon.dart' show CouponRejection;


/// Why something failed, in the only granularity the interface actually acts on.
///
/// Repositories never throw across their boundary; they return a [Result]. Each variant
/// here exists because the user is told a different thing: being offline is a "try again
/// in a moment", a permission denial is "this isn't yours to do", and a conflict is
/// "someone got there first". Collapsing them into one error is what produces the
/// "something went wrong" screen that tells a person nothing.
sealed class Failure {
  const Failure();

  /// Classifies anything thrown beneath a repository.
  ///
  /// Already-classified failures pass straight through, so a failure that crosses two
  /// layers is not wrapped twice and reduced to [UnknownFailure] on the way.
  /// Errors that mean the request never reached a server.
  ///
  /// Matched by type *name* rather than by type, deliberately. `SocketException` and
  /// `HandshakeException` live in `dart:io`, which AdminApp cannot import — it runs in a
  /// browser, where the owner types six hundred menu items on a real keyboard. Importing
  /// it here would take the whole shared package off the web to classify an error.
  ///
  /// This mattered more than it looks. `OfflineFailure` was declared and read in five
  /// places — "مفيش نت — جرّب تاني" on the error view, the media picker, the admin gate —
  /// and nothing produced it, so that sentence was unreachable and every dropped
  /// connection said "حصل خطأ" instead. Worse: `CourierWriteQueue` queues a write only
  /// when the failure `is OfflineFailure`, so the one class built to keep a courier's
  /// "delivered" tap alive through a dead connection rejected every real one.
  static const _offlineTypes = {
    'SocketException',
    'HandshakeException',
    'ClientException',
    'TimeoutException',
    'AuthRetryableFetchException',
  };

  /// Every refusal `place_order` raises by name, as the message it raises it with.
  ///
  /// Exact strings, read back from the function's current body, not fragments: four of
  /// these were matched with `contains` and five were not matched at all, so a dish that
  /// was switched off or a basket under the minimum reached the customer as
  /// UnknownFailure — «جرّب تاني» for something no retry can fix. Change a message in SQL
  /// and `result_test.dart` names the one that stopped matching.
  static const _orderRefusals = {
    'merchant not accepting orders': OrderRefusal.shopClosed,
    'meal not accepting reservations': OrderRefusal.mealClosed,
    'sold out': OrderRefusal.soldOut,
    'that dish is not available right now': OrderRefusal.dishUnavailable,
    'below the shop minimum': OrderRefusal.belowMinimum,
    'too many different items in one order': OrderRefusal.tooManyItems,
    'the note is too long': OrderRefusal.noteTooLong,
    'an empty basket is not an order': OrderRefusal.emptyBasket,
    'merchant does not deliver to this zone': OrderRefusal.zoneNotServed,
  };

  static Failure from(Object error, [StackTrace? stackTrace]) {
    if (error is Failure) return error;

    if (_offlineTypes.contains(error.runtimeType.toString())) {
      return const OfflineFailure();
    }

    if (error is PostgrestException) {
      // The reasons the order function raises by name: each one is a sentence a person
      // is shown, so they are classified rather than collapsed.
      switch (error.code) {
        case '42501':
          // `place_order` refuses a blocked customer with the same code it uses for a
          // signed-out one, and the checkout said «لازم تسجّل دخول» to somebody signed in.
          if (error.message == 'this account cannot place orders') {
            return const AccountBlockedFailure();
          }
          return const PermissionFailure();
        case '23514':
        // `invalid_parameter_value`: the functions that check their own arguments —
        // «a shop needs a zone», «all three documents are required» — raise it. It fell
        // through to UnknownFailure while the fakes answered the same refusals with
        // ValidationFailure, so the screens were tested against a sentence production
        // never showed.
        case '22023':
          return const ValidationFailure();
        case 'P0002':
          return const NotFoundFailure();
        case '23505':
          if (error.message.contains('staff_applications_one_open') ||
              (error.details?.toString().contains('staff_applications_one_open') ?? false)) {
            return const AlreadyAppliedFailure();
          }
          return const ConflictFailure();
        case '23503':
          // A foreign key said no: deleting a merchant that has taken orders is the
          // case in point. Not a permission problem and not a race — history exists,
          // and history wins.
          return const ConflictFailure();
      }
      final message = error.message;
      if (message.startsWith('coupon:')) {
        // The order function names every coupon refusal as `coupon: <reason>`; the
        // reason is what the checkout screen speaks.
        final name = message.substring('coupon:'.length).trim();
        return CouponFailure(
          CouponRejection.values.firstWhere(
            (r) => r.name == name,
            orElse: () => CouponRejection.notFound,
          ),
        );
      }
      final refusal = _orderRefusals[message];
      if (refusal != null) return OrderRefusedFailure(refusal);
      if (message == 'an order is still on its way') return const OrderInFlightFailure();
    }

    return UnknownFailure(error, stackTrace);
  }
}

/// No usable connection. The one failure worth retrying automatically.
final class OfflineFailure extends Failure {
  const OfflineFailure();
}

/// The security rules said no. Never retry — surface it and stop.
final class PermissionFailure extends Failure {
  const PermissionFailure();
}

/// The server rejected a value before applying the requested write.
final class ValidationFailure extends Failure {
  const ValidationFailure();
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure();
}

/// Someone else changed the world first: the last portion of a meal was reserved, the
/// merchant closed, the order was already accepted.
final class ConflictFailure extends Failure {
  const ConflictFailure();
}

/// Why the order function would not take an order, one value per sentence the
/// checkout says about it.
enum OrderRefusal {
  shopClosed,
  mealClosed,
  soldOut,
  dishUnavailable,
  belowMinimum,
  tooManyItems,
  noteTooLong,
  emptyBasket,
  zoneNotServed,
}

/// The server looked at the basket and said no, and said which no.
///
/// A [ConflictFailure] underneath — the world the basket was built in has moved: the
/// shop shut, the dish was switched off, the minimum changed — so a screen that only
/// asks the broad question still gets the right broad answer, and one that asks the
/// narrow one can tell the customer what to change.
final class OrderRefusedFailure extends ConflictFailure {
  const OrderRefusedFailure(this.reason);

  final OrderRefusal reason;
}

/// The account cannot be deleted yet: an order of theirs is still on its way, and
/// scrubbing it would take the street and the phone off an order a courier is carrying.
/// A [ConflictFailure] underneath; the sentence it earns is "finish it first", which no
/// retry can replace.
final class OrderInFlightFailure extends ConflictFailure {
  const OrderInFlightFailure();
}

/// The account has been blocked from ordering. A [PermissionFailure] underneath, but
/// never to be spoken as "sign in": the person is signed in, and asking them to do it
/// again sends them round a loop with no way out but a phone call.
final class AccountBlockedFailure extends PermissionFailure {
  const AccountBlockedFailure();
}

/// The e-mail already belongs to an account. Its own type rather than a conflict,
/// because the sentence it earns — "this one is taken" — asks for a different fix than
/// "something collided": retype the address, not retry the action.
final class EmailTakenFailure extends Failure {
  const EmailTakenFailure();
}

/// The phone number already belongs to an account. Its own type for the same reason as
/// [EmailTakenFailure] — "هذا الرقم مسجل بالفعل" asks for signing in, not retyping.
final class PhoneTakenFailure extends Failure {
  const PhoneTakenFailure();
}

/// The phone number already has an open application. Its own type because the sentence
/// it earns — "there is already an application with this number" — tells the applicant
/// to wait for the call, not to try again or sign in.
final class AlreadyAppliedFailure extends Failure {
  const AlreadyAppliedFailure();
}

/// What was chosen is not an image this build can read — a video, a PDF, a file that
/// arrived broken. Its own type because nothing was ever sent: it is the one failure in
/// the upload path the person can fix themselves, by picking something else.
final class NotAnImageFailure extends Failure {
  const NotAnImageFailure();
}

final class RateLimitedFailure extends Failure {
  const RateLimitedFailure();
}

/// The coupon said no, and said why. Each reason is its own sentence on the checkout
/// screen rather than one shrug for all of them - "expired" and "minimum not met" ask
/// for two completely different responses from the customer.
final class CouponFailure extends Failure {
  const CouponFailure(this.reason);

  final CouponRejection reason;
}

/// Something we have not seen. Keeps [cause] so the crash report has the real error
/// rather than our summary of it.
final class UnknownFailure extends Failure {
  const UnknownFailure(this.cause, [this.stackTrace]);

  final Object cause;
  final StackTrace? stackTrace;
}

/// A value, or the reason there isn't one.
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;
  const factory Result.err(Failure failure) = Err<T>;

  /// Runs [action] and classifies anything it throws.
  ///
  /// This is the only place a repository catches, which is what keeps `try`/`catch` out
  /// of the widget layer entirely.
  static Future<Result<T>> guard<T>(Future<T> Function() action) async {
    try {
      return Result.ok(await action());
    } catch (error, stackTrace) {
      return Result.err(Failure.from(error, stackTrace));
    }
  }

  /// Runs a write that must return at least one affected row.
  ///
  /// PostgREST makes a row hidden by policy indistinguishable from one that disappeared:
  /// both writes complete with an empty representation. [NotFoundFailure] preserves that
  /// uncertainty; calling it a permission failure would claim more than the server said.
  static Future<Result<T>> guardWrite<T, Row>(
    Future<List<Row>> Function() action,
    T Function(Row row) onChanged,
  ) {
    return guard(() async {
      final rows = await action();
      if (rows.isEmpty) throw const NotFoundFailure();
      return onChanged(rows.first);
    });
  }

  bool get isOk => this is Ok<T>;

  T? get valueOrNull => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>() => null,
      };

  Failure? get failureOrNull => switch (this) {
        Ok<T>() => null,
        Err<T>(:final failure) => failure,
      };

  /// The value, or the failure thrown.
  ///
  /// For the boundary where a Result meets something that speaks in exceptions — a
  /// Riverpod provider, whose AsyncValue carries the error to the screen. Nothing inside
  /// a repository uses this.
  T get valueOrThrow => switch (this) {
        Ok<T>(:final value) => value,
        Err<T>(:final failure) => throw failure,
      };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Ok<T>(:final value) => Result.ok(transform(value)),
        Err<T>(:final failure) => Result.err(failure),
      };
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;
}
