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
      final row =
          await _db.from('users').select('fcm_tokens').eq('id', uid).single();
      final tokens = (row['fcm_tokens'] as List?)?.cast<String>() ?? const [];
      if (tokens.contains(token)) return;

      await _db
          .from('users')
          .update({'fcm_tokens': [...tokens, token]}).eq('id', uid);
    });
  }

  @override
  Future<Result<void>> forget(String token) {
    return Result.guard(() async {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return;

      final row =
          await _db.from('users').select('fcm_tokens').eq('id', uid).single();
      final tokens = (row['fcm_tokens'] as List?)?.cast<String>() ?? const [];

      await _db.from('users').update({
        'fcm_tokens': tokens.where((t) => t != token).toList(),
      }).eq('id', uid);
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
}) {
  String? registered;

  return identities.listen((identity) async {
    try {
      if (identity == null) {
        final was = registered;
        registered = null;
        if (was != null) await repository.forget(was);
        return;
      }

      final fresh = await token();
      if (fresh == null) return;

      registered = fresh;
      await repository.register(fresh);
    } catch (_) {
      // Deliberately swallowed. This runs on every sign-in, and the worst outcome it may
      // cause is a merchant who is not woken — never one who cannot sign in.
    }
  });
}
