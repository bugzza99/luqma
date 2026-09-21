import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_service.dart';

import '../result.dart';

/// The app installations an account can currently be woken on.
///
/// A token has one owner because it names an installation, while one account can still
/// own several tokens for a phone in the kitchen and a till behind the counter.
abstract interface class PushTokenRepository {
  /// Claims [token] for whoever is signed in, transferring it from any previous account.
  Future<Result<void>> register(String token);

  /// Takes [token] off the account only if the caller still owns it.
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
      if (_db.auth.currentUser == null) throw const PermissionFailure();

      await _db.rpc('register_device_token', params: {'p_token': token});
    });
  }

  @override
  Future<Result<void>> forget(String token) {
    return Result.guard(() async {
      // A signed-out no-op must not be reported as a successful deletion: the manager
      // would then discard its retry state while the server can still wake the old
      // account on this installation.
      if (_db.auth.currentUser == null) throw const PermissionFailure();

      await _db.rpc('forget_device_token', params: {'p_token': token});
    });
  }
}

/// In-memory tokens, for tests and for running the app with no backend at all.
class FakePushTokenRepository implements PushTokenRepository {
  /// [deviceOwners] is shared by account-scoped fakes because two accounts must contend
  /// for one installation exactly as they do against the table's token key.
  FakePushTokenRepository({
    this.failure,
    this.accountId = 'fake-account',
    Map<String, String>? deviceOwners,
  }) : _deviceOwners = deviceOwners ?? {};

  final Failure? failure;
  final String accountId;
  final Map<String, String> _deviceOwners;

  /// What this account is currently reachable on, for assertions.
  List<String> get tokens => [
    for (final entry in _deviceOwners.entries)
      if (entry.value == accountId) entry.key,
  ];

  @override
  Future<Result<void>> register(String token) async {
    if (failure != null) return Result.err(failure!);
    _deviceOwners[token] = accountId;
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> forget(String token) async {
    if (failure != null) return Result.err(failure!);
    if (_deviceOwners[token] == accountId) _deviceOwners.remove(token);
    return const Result.ok(null);
  }
}

/// Keeps [repository] in step with whoever is signed in.
///
/// Registering at launch does not work, and it fails silently: the registration RPC needs
/// a signed-in account, and at launch nobody is signed in yet. A merchant installs the
/// app, opens it, *then* signs in — by which time registration has already run and been
/// refused. Nothing about that is visible: the app looks fine, the account has no token,
/// and the phone never rings.
///
/// So the token follows the session rather than the start-up. [token] is asked for each
/// time somebody signs in, because Android reissues it after a reinstall or a restore.
///
/// Nothing here throws. A merchant who cannot be reached by notification can still cook;
/// a merchant whose app dies on sign-in cannot.
PushTokenRegistration keepPushTokenRegistered({
  required Stream<LuqmaIdentity?> identities,
  required PushTokenRepository repository,
  required Future<String?> Function() token,
  Stream<String>? refreshes,
}) {
  return PushTokenRegistration._(
    repository,
    identities: identities,
    token: token,
    refreshes: refreshes,
  );
}

/// The live link between one signed-in session and its last successful push token.
///
/// Sign-out must remove the token that the server actually accepted, which can differ
/// from Firebase's current token when a refresh registration failed. Keeping that value
/// here also gives the auth service a cleanup operation it can await before its session
/// disappears.
class PushTokenRegistration {
  PushTokenRegistration._(
    this._repository, {
    required Stream<LuqmaIdentity?> identities,
    required Future<String?> Function() token,
    Stream<String>? refreshes,
  }) {
    _refreshed = refreshes?.listen((fresh) async {
      if (!_signedIn) return;
      final generation = _generation;
      try {
        await _put(fresh, generation);
      } catch (_) {
        // Push availability must never make the app unavailable.
      }
    }, onError: (Object _) {});

    _identities = identities.listen((identity) async {
      try {
        if (identity == null) {
          await forgetRegisteredToken();
          return;
        }

        if (_identityUid != identity.uid) {
          _identityUid = identity.uid;
          // A token string names the installation, not the account. Even when Firebase
          // returns the same string, a new account must run register again so the server
          // transfers ownership to that account.
          _registered = null;
          _generation++;
        }
        _signedIn = true;
        final generation = _generation;
        final fresh = await token();
        if (fresh == null) return;
        await _put(fresh, generation);
      } catch (_) {
        // Same reasoning as above: token work must not block authentication.
      }
    }, onError: (Object _) {});

    _identities.onDone(() => _refreshed?.cancel());
  }

  final PushTokenRepository _repository;
  late final StreamSubscription<LuqmaIdentity?> _identities;
  StreamSubscription<String>? _refreshed;
  String? _registered;
  String? _identityUid;
  bool _signedIn = false;
  int _generation = 0;
  Future<void> _serial = Future<void>.value();

  /// Every token the server accepted but has not confirmed forgetting yet. Usually this
  /// is one value; keeping the failed deletions means a temporary outage cannot strand a
  /// signed-out installation on an old account forever.
  final Set<String> _serverTokens = {};

  /// The token whose registration most recently succeeded.
  String? get registeredToken => _registered;

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _serial.then((_) => operation());
    // A failed push operation must not poison every operation queued after it. The
    // caller still receives [next] and can handle the error; only the queue tail heals.
    _serial = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _put(String fresh, int generation) {
    return _enqueue(() async {
      if (!_signedIn || generation != _generation) return;
      if (fresh == _registered) return;

      final result = await _repository.register(fresh);
      // Do not remember a token the server refused. A transient failure should be
      // retryable on the next auth emission or token refresh.
      if (result.failureOrNull != null) return;
      _serverTokens.add(fresh);

      // Sign-out can begin while the network request above is in flight. Remove the
      // just-registered token in that case instead of attaching it to a dead session.
      if (!_signedIn || generation != _generation) {
        await _forget(fresh);
        return;
      }

      _registered = fresh;
      // Registration and replacement are serialized, so two refresh events cannot
      // finish out of order and leave the older token as the remembered one.
      for (final stale in _serverTokens.toList()) {
        if (stale != fresh) await _forget(stale);
      }
    });
  }

  Future<void> _forget(String token) async {
    final result = await _repository.forget(token);
    if (result.failureOrNull != null) return;
    _serverTokens.remove(token);
    if (_registered == token) _registered = null;
  }

  /// Removes the server-accepted token while authentication still exists.
  Future<void> forgetRegisteredToken() {
    // This part is intentionally synchronous: it invalidates an in-flight registration
    // before the auth service starts waiting for the queued cleanup.
    _signedIn = false;
    _identityUid = null;
    _generation++;
    // This value belongs to the session that is ending. Failed deletions stay in
    // [_serverTokens] for retry, but must not suppress registration if another account
    // signs in on the same installation.
    _registered = null;
    return _enqueue(() async {
      for (final token in _serverTokens.toList()) {
        await _forget(token);
      }
    });
  }

  Future<void> cancel() async {
    _signedIn = false;
    _identityUid = null;
    _generation++;
    await _identities.cancel();
    await _refreshed?.cancel();
    await _serial;
  }
}
