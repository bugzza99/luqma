import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../result.dart';

/// Whoever is holding the phone.
@immutable
class LuqmaIdentity {
  const LuqmaIdentity({
    required this.uid,
    this.name,
    this.email,
    this.phone,
    this.photoUrl,
    this.claims = const {},
  });

  final String uid;
  final String? name;
  final String? email;
  final String? phone;
  final String? photoUrl;

  /// The custom claims on the ID token.
  ///
  /// Empty for a customer, and the whole of what a staff account is allowed to be —
  /// see [StaffIdentity]. Carried here rather than fetched where it is needed, so
  /// there is one place the session comes from and one place tests replace.
  final Map<String, Object?> claims;
}

/// Three states, not two.
///
/// [unknown] is separate on purpose: while the session is still resolving, treating
/// somebody as signed out throws a sign-in prompt at a person who is already signed in,
/// on every cold start.
enum AuthState { unknown, signedOut, signedIn }

/// Signing in and out.
///
/// An interface because the real one needs Google's SDK, a configured OAuth client and a
/// device — none of which a test has. Every screen above this talks to the interface, so
/// the whole account flow is exercised without any of that.
abstract interface class AuthService {
  AuthState get state;
  LuqmaIdentity? get identity;

  /// Emits the identity as it stands the moment somebody subscribes, then every change
  /// after that.
  ///
  /// The replay is the point: a screen opened after sign-in has to be able to find out
  /// who it is looking at. A plain broadcast buffers nothing, so such a screen would
  /// render as signed out until the next change — which, for somebody who stays signed
  /// in, is never.
  Stream<LuqmaIdentity?> get changes;

  /// Waits for the session to resolve one way or the other.
  Future<void> restore();

  /// Signs in, or returns `Ok(null)` when the person simply backed out.
  ///
  /// Backing out is not a failure: showing a red banner because somebody dismissed a
  /// sheet is the app apologising for their decision.
  Future<Result<LuqmaIdentity?>> signInWithGoogle();

  /// Signs in a staff account. Merchants and couriers get an email and a password from
  /// the owner; there is no self-service sign-up for either.
  Future<Result<LuqmaIdentity>> signInWithPassword({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

/// The real one. The session comes from GoTrue, and every policy in the database reads
/// the same token this service hands out.
class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client, {required this.googleIdToken}) : _auth = _client.auth {
    // Auth state changes, not just sign-in and sign-out: a claim granted while the app
    // is open arrives when the token refreshes, and a merchant whose account was set up
    // a minute ago should get in then rather than at the next cold start.
    _subscription = _client.auth.onAuthStateChange.listen((event) async {
      final user = event.session?.user;
      _identity = user == null ? null : _toIdentity(user);
      _state = user == null ? AuthState.signedOut : AuthState.signedIn;
      _controller.add(_identity);
      if (!_resolved.isCompleted) _resolved.complete();
    });
  }

  /// Obtains a Google id token, or null when the person backed out.
  ///
  /// Injected rather than called directly so that swapping Google for anything else —
  /// or adding a second provider — is a change here and nowhere above.
  final Future<String?> Function() googleIdToken;

  final GoTrueClient _auth;

  final SupabaseClient _client;
  final _controller = StreamController<LuqmaIdentity?>.broadcast();
  final _resolved = Completer<void>();
  // Typed loosely: GoTrue's own `AuthState` shares a name with ours below, and the
  // subscription never needs to spell it.
  late final StreamSubscription<dynamic> _subscription;

  AuthState _state = AuthState.unknown;
  LuqmaIdentity? _identity;

  @override
  AuthState get state => _state;

  @override
  LuqmaIdentity? get identity => _identity;

  @override
  Stream<LuqmaIdentity?> get changes => _replaying();

  /// Hands the current identity to each new subscriber before forwarding the rest.
  ///
  /// The subscription to the underlying controller is attached inside the same
  /// synchronous callback that emits the replay, so nothing can slip through the gap.
  Stream<LuqmaIdentity?> _replaying() => Stream.multi((listener) {
        listener.add(_identity);
        final sub = _controller.stream.listen(
          listener.add,
          onError: listener.addError,
          onDone: listener.close,
        );
        listener.onCancel = sub.cancel;
      });

  @override
  Future<void> restore() => _resolved.future;

  @override
  Future<Result<LuqmaIdentity?>> signInWithGoogle() async {
    return Result.guard(() async {
      final idToken = await googleIdToken();
      if (idToken == null) return null;

      await _auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken);
      return _toIdentity(_client.auth.currentUser!);
    });
  }

  @override
  Future<Result<LuqmaIdentity>> signInWithPassword({
    required String email,
    required String password,
  }) {
    return Result.guard(() async {
      final result = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return _toIdentity(result.user!);
    });
  }

  @override
  Future<void> signOut() => _auth.signOut();

  void dispose() {
    _subscription.cancel();
    _controller.close();
  }

  /// Who is signed in, and what the server says they may be.
  ///
  /// The claims come off the **access token**, never off `user.appMetadata`. The
  /// access-token hook copies the staff record into the token at sign-in and does not
  /// touch the user row, whose `raw_app_meta_data` stays `{provider: email}` for ever.
  /// Reading the row therefore hands every gate in the product an ordinary customer —
  /// which locked the owner out of AdminApp with "this account has no permission", and
  /// every merchant out of their own shop.
  ///
  /// It is also the right place on principle: a claim is only worth anything because a
  /// server signed it, and the token is the signed thing.
  LuqmaIdentity _toIdentity(User user) => LuqmaIdentity(
        uid: user.id,
        name: user.userMetadata?['name'] as String?,
        email: user.email,
        phone: user.phone,
        photoUrl: user.userMetadata?['avatar_url'] as String?,
        claims: _claimsOnToken(),
      );

  /// `app_metadata` as the current access token states it.
  ///
  /// Empty when there is no session, and empty rather than throwing on a token this
  /// build cannot read — an unreadable token is somebody with no claims, never a crash
  /// on the launch path.
  Map<String, Object?> _claimsOnToken() {
    final token = _auth.currentSession?.accessToken;
    if (token == null) return const {};

    try {
      final payload = token.split('.')[1];
      final decoded = utf8.decode(base64Url.decode(base64Url.normalize(payload)));
      final claims = jsonDecode(decoded) as Map<String, dynamic>;
      return (claims['app_metadata'] as Map<String, dynamic>?) ?? const {};
    } catch (_) {
      return const {};
    }
  }
}

/// An in-memory session, for tests and for running the app with no backend at all.
class FakeAuthService implements AuthService {
  FakeAuthService({
    LuqmaIdentity? restoring,
    this.cancels = false,
    this.failure,
    // ignore: prefer_initializing_formals
  }) : _restoring = restoring;

  final LuqmaIdentity? _restoring;

  /// Makes sign-in behave as though the person dismissed the Google sheet.
  final bool cancels;

  /// Makes sign-in fail with this.
  final Failure? failure;

  final _controller = StreamController<LuqmaIdentity?>.broadcast();

  AuthState _state = AuthState.unknown;
  LuqmaIdentity? _identity;

  @override
  AuthState get state => _state;

  @override
  LuqmaIdentity? get identity => _identity;

  @override
  Stream<LuqmaIdentity?> get changes => _replaying();

  /// Hands the current identity to each new subscriber before forwarding the rest.
  ///
  /// The subscription to the underlying controller is attached inside the same
  /// synchronous callback that emits the replay, so nothing can slip through the gap.
  Stream<LuqmaIdentity?> _replaying() => Stream.multi((listener) {
        listener.add(_identity);
        final sub = _controller.stream.listen(
          listener.add,
          onError: listener.addError,
          onDone: listener.close,
        );
        listener.onCancel = sub.cancel;
      });

  @override
  Future<void> restore() async {
    _identity = _restoring;
    _state = _restoring == null ? AuthState.signedOut : AuthState.signedIn;
    _controller.add(_identity);
  }

  @override
  Future<Result<LuqmaIdentity?>> signInWithGoogle() async {
    if (failure != null) {
      _state = AuthState.signedOut;
      return Result.err(failure!);
    }
    if (cancels) {
      _state = AuthState.signedOut;
      return const Result.ok(null);
    }

    _identity = const LuqmaIdentity(
      uid: 'fake-uid',
      name: 'عميل تجريبي',
      email: 'test@example.com',
    );
    _state = AuthState.signedIn;
    _controller.add(_identity);
    return Result.ok(_identity);
  }

  @override
  Future<Result<LuqmaIdentity>> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (failure != null) {
      _state = AuthState.signedOut;
      return Result.err(failure!);
    }

    _identity = _restoring ??
        LuqmaIdentity(uid: 'fake-uid', email: email, name: 'حساب تجريبي');
    _state = AuthState.signedIn;
    _controller.add(_identity);
    return Result.ok(_identity!);
  }

  @override
  Future<void> signOut() async {
    _identity = null;
    _state = AuthState.signedOut;
    _controller.add(null);
  }

  void dispose() => _controller.close();
}
