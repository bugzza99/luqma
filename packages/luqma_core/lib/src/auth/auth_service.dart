import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
  });

  final String uid;
  final String? name;
  final String? email;
  final String? phone;
  final String? photoUrl;
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

  Future<void> signOut();
}

/// The real one. Google's token goes to Firebase Auth, which issues the session the rest
/// of the app — and every security rule — actually trusts.
class FirebaseAuthService implements AuthService {
  FirebaseAuthService(this._auth, {required this.googleCredential}) {
    _subscription = _auth.authStateChanges().listen((user) {
      _identity = user == null ? null : _toIdentity(user);
      _state = user == null ? AuthState.signedOut : AuthState.signedIn;
      _controller.add(_identity);
      if (!_resolved.isCompleted) _resolved.complete();
    });
  }

  /// Obtains a Google credential, or null when the person backed out.
  ///
  /// Injected rather than called directly so that swapping Google for anything else —
  /// or adding a second provider — is a change here and nowhere above.
  final Future<AuthCredential?> Function() googleCredential;

  final FirebaseAuth _auth;
  final _controller = StreamController<LuqmaIdentity?>.broadcast();
  final _resolved = Completer<void>();
  late final StreamSubscription<User?> _subscription;

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
      final credential = await googleCredential();
      if (credential == null) return null;

      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      return user == null ? null : _toIdentity(user);
    });
  }

  @override
  Future<void> signOut() => _auth.signOut();

  void dispose() {
    _subscription.cancel();
    _controller.close();
  }

  static LuqmaIdentity _toIdentity(User user) => LuqmaIdentity(
        uid: user.uid,
        name: user.displayName,
        email: user.email,
        phone: user.phoneNumber,
        photoUrl: user.photoURL,
      );
}

/// An in-memory session, for tests and for running the app with no Firebase project.
class FakeAuthService implements AuthService {
  FakeAuthService({
    LuqmaIdentity? restoring,
    this.cancels = false,
    this.failure,
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
  Future<void> signOut() async {
    _identity = null;
    _state = AuthState.signedOut;
    _controller.add(null);
  }

  void dispose() => _controller.close();
}
