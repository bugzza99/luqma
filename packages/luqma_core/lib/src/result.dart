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
  static Failure from(Object error, [StackTrace? stackTrace]) {
    if (error is Failure) return error;

    if (error is PostgrestException) {
      // The reasons the order function raises by name: each one is a sentence a person
      // is shown, so they are classified rather than collapsed.
      switch (error.code) {
        case '42501':
          return const PermissionFailure();
        case 'P0002':
          return const NotFoundFailure();
        case '23505':
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
      if (message == 'sold out' ||
          message.contains('not accepting orders') ||
          message.contains('not accepting reservations') ||
          message.contains('does not deliver')) {
        return const ConflictFailure();
      }
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

final class NotFoundFailure extends Failure {
  const NotFoundFailure();
}

/// Someone else changed the world first: the last portion of a meal was reserved, the
/// merchant closed, the order was already accepted.
final class ConflictFailure extends Failure {
  const ConflictFailure();
}

/// The e-mail already belongs to an account. Its own type rather than a conflict,
/// because the sentence it earns — "this one is taken" — asks for a different fix than
/// "something collided": retype the address, not retry the action.
final class EmailTakenFailure extends Failure {
  const EmailTakenFailure();
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
