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
  ///
  /// Returns the secret the server minted for this registration. It is proof of ownership
  /// that does not expire with the session, and it is the only thing [revoke] accepts.
  Future<Result<String?>> register(String token);

  /// Takes [token] off the account only if the caller still owns it.
  ///
  /// Called on sign-out, and it matters: a shared till that keeps the last merchant's
  /// token goes on ringing for a shop the person holding it no longer works for.
  Future<Result<void>> forget(String token);

  /// Takes [token] off whatever account holds it, with no session at all.
  ///
  /// The one deletion that cannot fail for lack of authentication, which is the failure
  /// [forget] has by construction: it needs a JWT, and the moment this exists for is the
  /// moment the JWT has gone. Returns whether a row was actually removed — false means
  /// "not mine", and a caller told false must not report a clean sign-out.
  Future<Result<bool>> revoke(String token, String secret);
}

class SupabasePushTokenRepository implements PushTokenRepository {
  SupabasePushTokenRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<String?>> register(String token) {
    return Result.guard(() async {
      if (_db.auth.currentUser == null) throw const PermissionFailure();

      // Null from a server too old to mint one. The caller keeps working without a
      // revocation path rather than treating the registration as failed.
      final secret = await _db.rpc('register_device_token', params: {'p_token': token});
      return secret is String ? secret : null;
    });
  }

  @override
  Future<Result<bool>> revoke(String token, String secret) {
    return Result.guard(() async {
      // Deliberately no session check. This is the call for when there is no session.
      final removed = await _db.rpc(
        'revoke_device_token',
        params: {'p_token': token, 'p_secret': secret},
      );
      return removed == true;
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

  /// The secret each registration minted, keyed by token. Rotated on every registration,
  /// the way the server rotates it, so a fake cannot prove an invariant the database
  /// does not hold.
  final Map<String, String> _secrets = {};

  int _minted = 0;

  @override
  Future<Result<String?>> register(String token) async {
    if (failure != null) return Result.err(failure!);
    _deviceOwners[token] = accountId;
    final secret = 'secret-${++_minted}';
    _secrets[token] = secret;
    return Result.ok(secret);
  }

  @override
  Future<Result<void>> forget(String token) async {
    if (failure != null) return Result.err(failure!);
    if (_deviceOwners[token] == accountId) {
      _deviceOwners.remove(token);
      _secrets.remove(token);
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<bool>> revoke(String token, String secret) async {
    // No `failure` check and no account check, on purpose: this is the call that works
    // when nothing else does, and a fake that made it fail alongside the rest would hide
    // the very case it exists for.
    if (_secrets[token] != secret) return const Result.ok(false);
    _deviceOwners.remove(token);
    _secrets.remove(token);
    return const Result.ok(true);
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

  /// The revocation secret the server minted for each token it accepted.
  ///
  /// Kept because a deletion that needs a session is a deletion that cannot happen after
  /// sign-out — which is the one moment it is needed. With the secret, the same removal
  /// works with no session at all.
  final Map<String, String> _secrets = {};

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
      // Null from a server too old to mint one; the token is still registered and the
      // session-bound deletion still works, so this degrades rather than fails.
      if (result.valueOrNull case final secret?) _secrets[fresh] = secret;

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
    var removed = (await _repository.forget(token)).failureOrNull == null;

    // The fallback that cannot fail for lack of a session, which is exactly how the
    // session-bound call fails once GoTrue has signed out. Without it a deletion that
    // misses its window stays in [_serverTokens] waiting for an auth emission that never
    // comes on a phone somebody signed out of and put down — and the old account goes on
    // being woken on it.
    if (!removed) {
      if (_secrets[token] case final secret?) {
        removed = (await _repository.revoke(token, secret)).valueOrNull ?? false;
      }
    }

    if (!removed) return;
    _serverTokens.remove(token);
    _secrets.remove(token);
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
