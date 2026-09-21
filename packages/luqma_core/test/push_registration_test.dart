import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Keeping the device token in step with who is signed in.
///
/// The obvious place to register a token is at launch, next to the rest of the start-up.
/// It does not work, and it fails silently: the ownership RPC needs a signed-in account,
/// and at launch nobody is signed in yet. A merchant installs the app, opens it, *then*
/// signs in — by which time registration has already run and been refused.
///
/// Nothing about that is visible. The app looks fine, the account has no token, and the
/// phone never rings.
void main() {
  const merchant = LuqmaIdentity(uid: 'owner-1', name: 'صاحب المطعم');

  group('while nobody is signed in', () {
    test('nothing is registered', () async {
      final auth = FakeAuthService();
      final tokens = FakePushTokenRepository();

      final sub = keepPushTokenRegistered(
        identities: auth.changes,
        repository: tokens,
        token: () async => 'tok-1',
      );
      addTearDown(sub.cancel);
      await auth.restore();
      await Future<void>.delayed(Duration.zero);

      expect(
        tokens.tokens,
        isEmpty,
        reason: 'there is no account for the token to belong to',
      );
    });
  });

  test('signing in registers the token', () async {
    final auth = FakeAuthService();
    final tokens = FakePushTokenRepository();

    final sub = keepPushTokenRegistered(
      identities: auth.changes,
      repository: tokens,
      token: () async => 'tok-1',
    );
    addTearDown(sub.cancel);

    await auth.signInWithPassword(email: 'a@b.c', password: 'x');
    await Future<void>.delayed(Duration.zero);

    expect(tokens.tokens, ['tok-1']);
  });

  // A session restored from a previous run arrives as the first thing on the stream, and
  // has to count exactly like a fresh sign-in — otherwise a merchant who never signs out
  // is a merchant whose token is registered once and never again.
  test('a restored session counts too', () async {
    final auth = FakeAuthService(restoring: merchant);
    final tokens = FakePushTokenRepository();

    final sub = keepPushTokenRegistered(
      identities: auth.changes,
      repository: tokens,
      token: () async => 'tok-1',
    );
    addTearDown(sub.cancel);

    await auth.restore();
    await Future<void>.delayed(Duration.zero);

    expect(tokens.tokens, ['tok-1']);
  });

  // A till behind a counter that keeps the last merchant's token goes on ringing for a
  // shop the person holding it no longer works for.
  test('signing out takes it off', () async {
    final auth = FakeAuthService();
    final tokens = FakePushTokenRepository();

    final sub = keepPushTokenRegistered(
      identities: auth.changes,
      repository: tokens,
      token: () async => 'tok-1',
    );
    addTearDown(sub.cancel);

    await auth.signInWithPassword(email: 'a@b.c', password: 'x');
    await Future<void>.delayed(Duration.zero);
    await auth.signOut();
    await Future<void>.delayed(Duration.zero);

    expect(tokens.tokens, isEmpty);
  });

  test('a device with no token asks for nothing', () async {
    final auth = FakeAuthService();
    final tokens = FakePushTokenRepository();

    final sub = keepPushTokenRegistered(
      identities: auth.changes,
      repository: tokens,
      // Firebase is not configured in this build, or the play services are missing.
      token: () async => null,
    );
    addTearDown(sub.cancel);

    await auth.signInWithPassword(email: 'a@b.c', password: 'x');
    await Future<void>.delayed(Duration.zero);

    expect(tokens.tokens, isEmpty);
  });

  // Registration must never take the app down with it. A merchant who cannot be reached
  // by notification can still cook; a merchant whose app crashes on sign-in cannot.
  test('a failing repository is survived', () async {
    final auth = FakeAuthService();
    final tokens = FakePushTokenRepository(failure: const OfflineFailure());

    final sub = keepPushTokenRegistered(
      identities: auth.changes,
      repository: tokens,
      token: () async => 'tok-1',
    );
    addTearDown(sub.cancel);

    await auth.signInWithPassword(email: 'a@b.c', password: 'x');
    await Future<void>.delayed(Duration.zero);

    expect(tokens.tokens, isEmpty);
  });

  test('a failed registration of the same token is retried', () async {
    final auth = FakeAuthService();
    final tokens = _FailsOncePushTokenRepository();

    final sub = keepPushTokenRegistered(
      identities: auth.changes,
      repository: tokens,
      token: () async => 'tok-1',
    );
    addTearDown(sub.cancel);

    await auth.signInWithPassword(email: 'a@b.c', password: 'x');
    await Future<void>.delayed(Duration.zero);
    expect(tokens.registered, isEmpty);

    // The session can re-emit without Firebase changing the token. That is the retry
    // opportunity a poisoned local `registered` value used to suppress.
    await auth.refreshSession();
    await Future<void>.delayed(Duration.zero);

    expect(tokens.attempts, 2);
    expect(tokens.registered, ['tok-1']);
  });

  // Android reissues a token after a reinstall, a restore, a clear-data, or on its own
  // after a long silence. Nothing listened for that, so a phone whose token changed while
  // the app was open went quiet with the stale one still on the account — and it fails
  // the way every push bug here fails: no error, no screen, just silence.
  test('a reissued token replaces the one on the account', () async {
    final auth = FakeAuthService();
    final tokens = FakePushTokenRepository();
    final refreshes = StreamController<String>.broadcast();
    addTearDown(refreshes.close);

    final sub = keepPushTokenRegistered(
      identities: auth.changes,
      repository: tokens,
      token: () async => 'tok-1',
      refreshes: refreshes.stream,
    );
    addTearDown(sub.cancel);

    await auth.signInWithPassword(email: 'a@b.c', password: 'x');
    await Future<void>.delayed(Duration.zero);
    expect(tokens.tokens, ['tok-1']);

    refreshes.add('tok-2');
    await Future<void>.delayed(Duration.zero);

    expect(
      tokens.tokens,
      ['tok-2'],
      reason: 'the stale one is dropped, not left beside the new one',
    );
  });

  test('sign-out forgets the last token the server accepted', () async {
    final auth = FakeAuthService();
    final tokens = _RejectsRefreshedTokenRepository();
    final refreshes = StreamController<String>.broadcast();
    addTearDown(refreshes.close);

    final registration = keepPushTokenRegistered(
      identities: auth.changes,
      repository: tokens,
      token: () async => 'tok-1',
      refreshes: refreshes.stream,
    );
    addTearDown(registration.cancel);

    await auth.signInWithPassword(email: 'a@b.c', password: 'x');
    await Future<void>.delayed(Duration.zero);
    refreshes.add('tok-2');
    await Future<void>.delayed(Duration.zero);

    expect(registration.registeredToken, 'tok-1');
    expect(tokens.registered, ['tok-1']);

    // Firebase now says tok-2, but its registration failed. Cleanup must remove tok-1,
    // the token the server can still use to wake this signed-out installation.
    await registration.forgetRegisteredToken();

    expect(registration.registeredToken, isNull);
    expect(tokens.registered, isEmpty);
  });

  test('refresh registrations finish in arrival order', () async {
    final auth = FakeAuthService();
    final tokens = _ControlledPushTokenRepository();
    final refreshes = StreamController<String>.broadcast();
    addTearDown(refreshes.close);

    final registration = keepPushTokenRegistered(
      identities: auth.changes,
      repository: tokens,
      token: () async => 'tok-1',
      refreshes: refreshes.stream,
    );
    addTearDown(registration.cancel);

    await auth.signInWithPassword(email: 'a@b.c', password: 'x');
    await tokens.started('tok-1');
    refreshes.add('tok-2');

    tokens.complete('tok-1');
    await tokens.started('tok-2');
    tokens.complete('tok-2');
    await Future<void>.delayed(Duration.zero);

    expect(registration.registeredToken, 'tok-2');
    expect(tokens.registered, {'tok-2'});
  });

  test('sign-out waits for and removes an in-flight registration', () async {
    final auth = FakeAuthService();
    final tokens = _ControlledPushTokenRepository();
    final registration = keepPushTokenRegistered(
      identities: auth.changes,
      repository: tokens,
      token: () async => 'tok-1',
    );
    addTearDown(registration.cancel);

    await auth.signInWithPassword(email: 'a@b.c', password: 'x');
    await tokens.started('tok-1');

    final cleanup = registration.forgetRegisteredToken();
    tokens.complete('tok-1');
    await cleanup;

    expect(registration.registeredToken, isNull);
    expect(tokens.registered, isEmpty);
  });

  test('a failed old-token deletion is retried at sign-out', () async {
    final auth = FakeAuthService();
    final tokens = _FailsFirstForgetPushTokenRepository();
    final refreshes = StreamController<String>.broadcast();
    addTearDown(refreshes.close);
    final registration = keepPushTokenRegistered(
      identities: auth.changes,
      repository: tokens,
      token: () async => 'tok-1',
      refreshes: refreshes.stream,
    );
    addTearDown(registration.cancel);

    await auth.signInWithPassword(email: 'a@b.c', password: 'x');
    await Future<void>.delayed(Duration.zero);
    refreshes.add('tok-2');
    await Future<void>.delayed(Duration.zero);

    expect(tokens.registered, {'tok-1', 'tok-2'});
    expect(registration.registeredToken, 'tok-2');

    await registration.forgetRegisteredToken();

    expect(tokens.registered, isEmpty);
    expect(tokens.forgetAttempts['tok-1'], 2);
  });

  // A token arriving for nobody is a token filed against nobody. The RPC takes its uid
  // from the session, so there is deliberately no account parameter to fall back to.
  test('a refresh before anybody signs in registers nothing', () async {
    final auth = FakeAuthService();
    final tokens = FakePushTokenRepository();
    final refreshes = StreamController<String>.broadcast();
    addTearDown(refreshes.close);

    final sub = keepPushTokenRegistered(
      identities: auth.changes,
      repository: tokens,
      token: () async => 'tok-1',
      refreshes: refreshes.stream,
    );
    addTearDown(sub.cancel);

    refreshes.add('tok-2');
    await Future<void>.delayed(Duration.zero);

    expect(tokens.tokens, isEmpty);
  });

  test(
    'the same device token is registered again for a different account',
    () async {
      final identities = StreamController<LuqmaIdentity>.broadcast();
      final tokens = _CountingPushTokenRepository();
      addTearDown(identities.close);
      final registration = keepPushTokenRegistered(
        identities: identities.stream,
        repository: tokens,
        token: () async => 'shared-phone',
      );
      addTearDown(registration.cancel);

      identities.add(const LuqmaIdentity(uid: 'account-1'));
      await Future<void>.delayed(Duration.zero);
      identities.add(const LuqmaIdentity(uid: 'account-2'));
      await Future<void>.delayed(Duration.zero);

      expect(tokens.registrations, ['shared-phone', 'shared-phone']);
      expect(registration.registeredToken, 'shared-phone');
    },
  );

  test(
    'registering a shared installation transfers it to the current account',
    () async {
      final deviceOwners = <String, String>{};
      final owner = FakePushTokenRepository(
        accountId: 'owner',
        deviceOwners: deviceOwners,
      );
      final courier = FakePushTokenRepository(
        accountId: 'courier',
        deviceOwners: deviceOwners,
      );

      await owner.register('shared-phone');
      await courier.register('shared-phone');

      expect(owner.tokens, isEmpty);
      expect(courier.tokens, ['shared-phone']);
    },
  );

  test(
    'one fake account cannot forget another account\'s installation',
    () async {
      final deviceOwners = <String, String>{};
      final owner = FakePushTokenRepository(
        accountId: 'owner',
        deviceOwners: deviceOwners,
      );
      final courier = FakePushTokenRepository(
        accountId: 'courier',
        deviceOwners: deviceOwners,
      );

      await courier.register('shared-phone');
      await owner.forget('shared-phone');

      expect(owner.tokens, isEmpty);
      expect(courier.tokens, ['shared-phone']);
    },
  );

  // A stream *error* is not delivered to the data callback, so the `try/catch` around the
  // body of that callback does not cover it. With no `onError` it goes to the zone — and
  // Sentry's `PlatformDispatcher.onError` reports an unhandled async error as **fatal**,
  // so an FCM refresh stream having a bad moment would close the app.
  //
  // The same shape as the launch crash: push work assumed safe, thrown where nothing was
  // catching. `_replaying` in `auth_service.dart` already passes `onError`; this was the
  // listen that did not.
  test('an error on the refresh stream never reaches the zone', () async {
    final auth = FakeAuthService();
    final tokens = FakePushTokenRepository();
    final refreshes = StreamController<String>.broadcast();
    addTearDown(refreshes.close);

    final escaped = <Object>[];
    await runZonedGuarded(() async {
      final sub = keepPushTokenRegistered(
        identities: auth.changes,
        repository: tokens,
        token: () async => 'tok-1',
        refreshes: refreshes.stream,
      );
      addTearDown(sub.cancel);

      await auth.signInWithPassword(email: 'a@b.c', password: 'x');
      await Future<void>.delayed(Duration.zero);

      refreshes.addError(StateError('FCM had a bad moment'));
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => escaped.add(error));

    expect(escaped, isEmpty);
    // And the token already on the account is left alone: an error is not news that the
    // device's token changed.
    expect(tokens.tokens, ['tok-1']);
  });
}

class _FailsOncePushTokenRepository implements PushTokenRepository {
  var attempts = 0;
  final registered = <String>[];

  @override
  Future<Result<void>> register(String token) async {
    attempts++;
    if (attempts == 1) return const Result.err(OfflineFailure());
    registered.add(token);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> forget(String token) async {
    registered.remove(token);
    return const Result.ok(null);
  }
}

class _RejectsRefreshedTokenRepository implements PushTokenRepository {
  final registered = <String>[];

  @override
  Future<Result<void>> register(String token) async {
    if (token == 'tok-2') return const Result.err(OfflineFailure());
    registered.add(token);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> forget(String token) async {
    registered.remove(token);
    return const Result.ok(null);
  }
}

class _ControlledPushTokenRepository implements PushTokenRepository {
  final registered = <String>{};
  final _started = <String, Completer<void>>{};
  final _gates = <String, Completer<Result<void>>>{};

  Future<void> started(String token) =>
      (_started[token] ??= Completer<void>()).future;

  void complete(String token) => (_gates[token] ??= Completer<Result<void>>())
      .complete(const Result.ok(null));

  @override
  Future<Result<void>> register(String token) async {
    (_started[token] ??= Completer<void>()).complete();
    final result = await (_gates[token] ??= Completer<Result<void>>()).future;
    if (result.failureOrNull == null) registered.add(token);
    return result;
  }

  @override
  Future<Result<void>> forget(String token) async {
    registered.remove(token);
    return const Result.ok(null);
  }
}

class _FailsFirstForgetPushTokenRepository implements PushTokenRepository {
  final registered = <String>{};
  final forgetAttempts = <String, int>{};

  @override
  Future<Result<void>> register(String token) async {
    registered.add(token);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> forget(String token) async {
    final attempt = (forgetAttempts[token] ?? 0) + 1;
    forgetAttempts[token] = attempt;
    if (token == 'tok-1' && attempt == 1) {
      return const Result.err(OfflineFailure());
    }
    registered.remove(token);
    return const Result.ok(null);
  }
}

class _CountingPushTokenRepository implements PushTokenRepository {
  final registrations = <String>[];

  @override
  Future<Result<void>> register(String token) async {
    registrations.add(token);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> forget(String token) async => const Result.ok(null);
}
