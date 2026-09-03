import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';

import '../result.dart';

/// The device tokens an account can be woken on.
///
/// Kept on `users.fcm_tokens` for every role, not on `staff`: `ensure_user_profile` gives
/// every account a `users` row whatever it signs in as, so one array keyed by uid covers
/// the merchant, the courier, the admin and the customer without a second place to look.
///
/// An array rather than a column because one person has more than one device — a
/// merchant's own phone and the till behind the counter — and waking only the last one to
/// sign in is waking the wrong one half the time.
abstract interface class PushTokenRepository {
  /// Adds [token] to whoever is signed in, if it is not already there.
  Future<Result<void>> register(String token);

  /// Takes [token] off the account.
  ///
  /// Called on sign-out, and it matters: a shared till that keeps the last merchant's
  /// token goes on ringing for a shop the person holding it no longer works for.
  Future<Result<void>> forget(String token);
}

class SupabasePushTokenRepository implements PushTokenRepository {
  SupabasePushTokenRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<void>> register(String token) {
    return Result.guard(() async {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) throw const PermissionFailure();

      // Read, merge, write. Not `array_append`: a phone that reinstalls gets the same
      // token back from FCM, and appending blindly would send the same alarm twice.
      final row = await _db
          .from('users')
          .select('fcm_tokens')
          .eq('id', uid)
          .single();
      final tokens = (row['fcm_tokens'] as List?)?.cast<String>() ?? const [];
      if (tokens.contains(token)) return;

      await _db
          .from('users')
          .update({
            'fcm_tokens': [...tokens, token],
          })
          .eq('id', uid);
    });
  }

  @override
  Future<Result<void>> forget(String token) {
    return Result.guard(() async {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;

      final row = await _db
          .from('users')
          .select('fcm_tokens')
          .eq('id', uid)
          .single();
      final tokens = (row['fcm_tokens'] as List?)?.cast<String>() ?? const [];

      await _db
          .from('users')
          .update({'fcm_tokens': tokens.where((t) => t != token).toList()})
          .eq('id', uid);
    });
  }
}

/// In-memory tokens, for tests and for running the app with no backend at all.
class FakePushTokenRepository implements PushTokenRepository {
  FakePushTokenRepository({this.failure});

  final Failure? failure;

  /// What this account is currently reachable on, for assertions.
  final List<String> tokens = [];

  @override
  Future<Result<void>> register(String token) async {
    if (failure != null) return Result.err(failure!);
    if (!tokens.contains(token)) tokens.add(token);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> forget(String token) async {
    if (failure != null) return Result.err(failure!);
    tokens.remove(token);
    return const Result.ok(null);
  }
}

/// Keeps [repository] in step with whoever is signed in.
///
/// Registering at launch does not work, and it fails silently: `users.fcm_tokens` is
/// written by the signed-in account under RLS, and at launch nobody is signed in yet. A
/// merchant installs the app, opens it, *then* signs in — by which time registration has
/// already run and been refused. Nothing about that is visible: the app looks fine, the
/// account has no token, and the phone never rings.
///
/// So the token follows the session rather than the start-up. [token] is asked for each
/// time somebody signs in, because Android reissues it after a reinstall or a restore.
///
/// Nothing here throws. A merchant who cannot be reached by notification can still cook;
/// a merchant whose app dies on sign-in cannot.
StreamSubscription<LuqmaIdentity?> keepPushTokenRegistered({
  required Stream<LuqmaIdentity?> identities,
  required PushTokenRepository repository,
  required Future<String?> Function() token,
  Stream<String>? refreshes,
}) {
  String? registered;
  var signedIn = false;

  Future<void> put(String fresh) async {
    if (fresh == registered) return;
    final was = registered;
    registered = fresh;
    await repository.register(fresh);
    // The old one is dropped only once the new one is on the account. The other order
    // leaves a phone with no token at all if the second call fails.
    if (was != null) await repository.forget(was);
  }

  // Android reissues a token after a reinstall, a restore, a clear-data, or on its own
  // after a long silence. Nothing listened for that, so a phone whose token changed while
  // the app was open went quiet with the stale one still on the account — and it fails
  // the way every push bug here fails: no error, no screen, just silence.
  final refreshed = refreshes?.listen(
    (fresh) async {
      if (!signedIn) return;
      try {
        await put(fresh);
      } catch (_) {
        // Same reasoning as below: never worth an exception on a working app.
      }
    },
    // A stream *error* is delivered here and nowhere else — the `try` above wraps the
    // data callback and cannot see it. Without this it reaches the zone, and Sentry's
    // `PlatformDispatcher.onError` reports an unhandled async error as fatal, so a bad
    // moment on the FCM refresh stream would close the app.
    onError: (Object _) {},
  );

  final subscription = identities.listen(
    (identity) async {
      try {
        if (identity == null) {
          signedIn = false;
          final was = registered;
          registered = null;
          if (was != null) await repository.forget(was);
          return;
        }

        signedIn = true;
        final fresh = await token();
        if (fresh == null) return;
        await put(fresh);
      } catch (_) {
        // Deliberately swallowed. This runs on every sign-in, and the worst outcome it may
        // cause is somebody who is not woken — never one who cannot sign in.
      }
    },
    // Theoretical today — `SupabaseAuthService`'s controller is never given an error —
    // and here for the same reason as above: a session stream that ever did emit one
    // must not be able to take the app down with it.
    onError: (Object _) {},
  );

  subscription.onDone(() => refreshed?.cancel());
  return subscription;
}
