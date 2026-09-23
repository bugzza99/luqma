import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../result.dart';
import '../util/phone.dart';

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

  /// Creates a brand-new customer account: the phone number is the identity, chosen and
  /// held by whoever types it, and the password is theirs from the first keystroke —
  /// there is no confirmation step to wait on.
  ///
  /// [phone] is Egyptian local format (`01…`); validate it with [Phone.isValidEgyptianMobile]
  /// before calling this.
  Future<Result<LuqmaIdentity>> signUpWithPhone({
    required String phone,
    required String password,
    required String name,
  });

  /// Signs an existing customer back in by phone and password.
  Future<Result<LuqmaIdentity>> signInWithPhone({
    required String phone,
    required String password,
  });

  /// Signs in a staff account. Merchants and couriers get an email and a password from
  /// the owner; there is no self-service sign-up for either.
  Future<Result<LuqmaIdentity>> signInWithPassword({
    required String email,
    required String password,
  });

  /// Asks GoTrue for a new access token, and with it a fresh set of claims.
  ///
  /// A claim is only on the token because the access-token hook stamped it at sign-in, so
  /// somebody whose `staff` row was written a minute ago is still carrying a token that
  /// says they are nobody — for up to an hour, until the token refreshes on its own. That
  /// is precisely the minute an approved partner opens the app, having just been told it
  /// worked, and reads that they have no access. This is the button that answers them.
  Future<Result<void>> refreshSession();

  Future<void> signOut();
}

/// The real one. The session comes from GoTrue, and every policy in the database reads
/// the same token this service hands out.
class SupabaseAuthService implements AuthService {
  /// [resolveWithin] bounds the wait in [restore]. See [_giveUp].
  SupabaseAuthService(
    this._client, {
    Duration resolveWithin = const Duration(seconds: 8),
    this.beforeSignOutTimeout = const Duration(seconds: 5),
    this._beforeSignOut,
  }) : _auth = _client.auth {
    // Auth state changes, not just sign-in and sign-out: a claim granted while the app
    // is open arrives when the token refreshes, and a merchant whose account was set up
    // a minute ago should get in then rather than at the next cold start.
    _subscription = _client.auth.onAuthStateChange.listen(
      (event) async {
        final user = event.session?.user;
        _identity = user == null ? null : _toIdentity(user);
        _state = user == null ? AuthState.signedOut : AuthState.signedIn;
        _controller.add(_identity);
        if (!_resolved.isCompleted) _resolved.complete();
      },
      // A `listen` with no `onError` sends a stream error to the zone, and these builds
      // install Sentry's `PlatformDispatcher.onError`, which reports an unhandled async
      // error as **fatal**. So a transient failure on GoTrue's own stream — the kind a
      // weak connection produces — would arrive as a crash report for a process that
      // never crashed. Same lesson as `unawaited(LuqmaPush.start())`, from the other end.
      //
      // It resolves to signed out rather than staying unknown, for the reason the timer
      // below gives: the wait is over and nobody arrived. And it deliberately does *not*
      // put the error on `_controller` — every gate reads that stream, and signing an
      // admin out of a screen they are working on because one refresh failed is a worse
      // answer than letting the next event correct it.
      onError: (Object error, StackTrace stackTrace) {
        // Somebody already signed in **stays** signed in. A failed token refresh puts a
        // retryable error on this stream, and clearing the identity for it throws whoever
        // is holding the phone back to the sign-in screen for a moment of bad signal —
        // which is what the «حدّث الحساب» button on the partner app would otherwise do to
        // an approved merchant standing in their kitchen. The session on the device is
        // still there; what failed was asking about it.
        if (_identity != null) {
          debugPrint('auth stream error, keeping the session we have: $error');
          if (!_resolved.isCompleted) _resolved.complete();
          return;
        }
        debugPrint('auth stream error, treating the session as absent: $error');
        _identity = null;
        _state = AuthState.signedOut;
        _controller.add(null);
        if (!_resolved.isCompleted) _resolved.complete();
      },
    );

    // A floor under a failure, not a race the real event has to win.
    //
    // `restore()` hands out `_resolved.future`, and until this timer existed the only
    // thing that completed it was GoTrue's first `onAuthStateChange`. Three launch paths
    // wait on it — the customer's splash, the merchant's gate, and
    // `currentIdentityProvider` — so an event that never arrives is not a degraded
    // feature: it is a burgundy splash for ever, with no exception, nothing in Sentry,
    // and "التطبيق مش بيفتح" as the only report anybody can make.
    //
    // Eight seconds because the real event lands well inside one on any phone this ships
    // to, so this can only fire when something is genuinely wrong. Giving up resolves to
    // *signed out* rather than staying unknown — the customer app is browsable signed
    // out, so somebody lands on the home screen instead of a wall, and a session that
    // does arrive later still signs them in through the listener above.
    _giveUp = Timer(resolveWithin, () {
      if (_resolved.isCompleted) return;
      _state = AuthState.signedOut;
      // Emitted as well as recorded. `_identity` is already null, so this changes no
      // value — but `state` and `changes` are two ways of asking the same question, and
      // a transition that moves one without the other is how they come to disagree.
      _controller.add(_identity);
      _resolved.complete();
    });
  }

  final GoTrueClient _auth;

  final SupabaseClient _client;
  final Future<void> Function()? _beforeSignOut;

  /// Maximum time optional device cleanup may delay an explicit sign-out.
  final Duration beforeSignOutTimeout;
  final _controller = StreamController<LuqmaIdentity?>.broadcast();
  final _resolved = Completer<void>();
  // Typed loosely: GoTrue's own `AuthState` shares a name with ours below, and the
  // subscription never needs to spell it.
  late final StreamSubscription<dynamic> _subscription;
  late final Timer _giveUp;

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
  Future<Result<LuqmaIdentity>> signUpWithPhone({
    required String phone,
    required String password,
    required String name,
  }) {
    return Result.guard(() async {
      try {
        final result = await _auth.signUp(
          email: Phone.toAccountEmail(phone),
          password: password,
          // The real number, kept beside the account so the courier has something to
          // call and the admin has something to search. The address is only a key.
          data: {'name': name, 'phone': Phone.normalize(phone)},
        );
        return _toIdentity(result.user!);
      } on AuthException catch (e) {
        // GoTrue names this a few different ways depending on version and path; none of
        // them are worth telling apart from the sentence the person reads.
        if (e.message.toLowerCase().contains('already') ||
            e.code == 'email_exists' ||
            e.code == 'user_already_exists') {
          throw const PhoneTakenFailure();
        }
        rethrow;
      }
    });
  }

  @override
  Future<Result<LuqmaIdentity>> signInWithPhone({
    required String phone,
    required String password,
  }) {
    return Result.guard(() async {
      final result = await _auth.signInWithPassword(
        email: Phone.toAccountEmail(phone),
        password: password,
      );
      return _toIdentity(result.user!);
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
  Future<Result<void>> refreshSession() {
    return Result.guard(() async {
      // The listener above is what publishes the new identity: a refreshed token arrives
      // as an ordinary auth state change, claims and all.
      await _auth.refreshSession();
    });
  }

  @override
  Future<void> signOut() async {
    // Device-token ownership has to be removed while the access token still exists.
    // Once GoTrue signs out, RLS quite correctly refuses the cleanup RPC. Cleanup is
    // best effort: notification hygiene must never trap somebody in their account.
    try {
      await _beforeSignOut?.call().timeout(beforeSignOutTimeout);
    } catch (error) {
      debugPrint('pre-sign-out cleanup failed: $error');
    }
    await _auth.signOut();
  }

  void dispose() {
    _giveUp.cancel();
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
  LuqmaIdentity _toIdentity(User user) {
    // A customer's address is synthetic — `01…@phone.luqma.app`, derived from the number
    // they typed — so it is never surfaced as an email. Their real number rides in the
    // metadata instead. Staff sign in with a genuine address and carry no phone here.
    final synthetic = user.email?.endsWith('@${Phone.accountDomain}') ?? false;

    return LuqmaIdentity(
      uid: user.id,
      name: user.userMetadata?['name'] as String?,
      email: synthetic ? null : user.email,
      phone: user.userMetadata?['phone'] as String? ?? user.phone,
      photoUrl: user.userMetadata?['avatar_url'] as String?,
      claims: _claimsOnToken(),
    );
  }

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
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(payload)),
      );
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
    this.failure,
    // ignore: prefer_initializing_formals
  }) : _restoring = restoring;

  final LuqmaIdentity? _restoring;

  /// Makes sign-in or sign-up fail with this.
  final Failure? failure;

  final _controller = StreamController<LuqmaIdentity?>.broadcast();

  /// Phone numbers this fake has already handed an account, and the password each one
  /// was given — so a second sign-up is refused and a wrong password is refused, the way
  /// production refuses both.
  ///
  /// Keyed on [Phone.normalize], because that is what the real service folds into the
  /// account address: `٠١٠…` and `010…` are one account there and must be one here.
  final Map<String, String> _accounts = {};

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
  Future<Result<LuqmaIdentity>> signUpWithPhone({
    required String phone,
    required String password,
    required String name,
  }) async {
    if (failure != null) {
      _state = AuthState.signedOut;
      return Result.err(failure!);
    }
    final key = Phone.normalize(phone);
    if (_accounts.containsKey(key)) {
      return const Result.err(PhoneTakenFailure());
    }

    _accounts[key] = password;
    // A uid per account, not one shared string: a test that cannot tell two accounts apart
    // cannot prove an application was filed against the right one.
    _identity = LuqmaIdentity(uid: _uidFor(key), name: name, phone: key);
    _state = AuthState.signedIn;
    _controller.add(_identity);
    return Result.ok(_identity!);
  }

  @override
  Future<Result<LuqmaIdentity>> signInWithPhone({
    required String phone,
    required String password,
  }) async {
    if (failure != null) {
      _state = AuthState.signedOut;
      return Result.err(failure!);
    }

    // A password this fake handed out is the only one it accepts back. Without this the
    // fake signs anybody into any number, which is the one thing the screens above it
    // rely on being impossible — see "the fakes are not the system".
    final key = Phone.normalize(phone);
    final known = _accounts[key];
    if (known != null && known != password) {
      return Result.err(UnknownFailure(Exception('wrong password')));
    }

    _identity =
        _restoring ??
        LuqmaIdentity(uid: _uidFor(key), name: 'عميل تجريبي', phone: key);
    _state = AuthState.signedIn;
    _controller.add(_identity);
    return Result.ok(_identity!);
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

    _identity =
        _restoring ??
        LuqmaIdentity(uid: 'fake-uid', email: email, name: 'حساب تجريبي');
    _state = AuthState.signedIn;
    _controller.add(_identity);
    return Result.ok(_identity!);
  }

  @override
  Future<Result<void>> refreshSession() async {
    if (failure != null) return Result.err(failure!);
    // Nothing to refresh, and it has to say so truthfully: a fake that invented new claims
    // would let a screen pass a test the server would fail.
    //
    // But a *new object* carrying the same values, because that is what the real one
    // emits: every GoTrue event builds a fresh `LuqmaIdentity`. Re-emitting the same
    // instance let Riverpod see nothing change, which is how a courier's write queue could
    // be torn down and rebuilt on every hourly token refresh with no test noticing.
    final current = _identity;
    _identity = current == null
        ? null
        : LuqmaIdentity(
            uid: current.uid,
            name: current.name,
            email: current.email,
            phone: current.phone,
            photoUrl: current.photoUrl,
            claims: Map.of(current.claims),
          );
    _controller.add(_identity);
    return const Result.ok(null);
  }

  @override
  Future<void> signOut() async {
    _identity = null;
    _state = AuthState.signedOut;
    _controller.add(null);
  }

  /// One uid per number, stable across calls, so a test can say which account it means.
  String _uidFor(String phone) => 'fake-uid-$phone';

  void dispose() => _controller.close();
}
