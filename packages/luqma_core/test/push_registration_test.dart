import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Keeping the device token in step with who is signed in.
///
/// The obvious place to register a token is at launch, next to the rest of the start-up.
/// It does not work, and it fails silently: `users.fcm_tokens` is written by the signed-in
/// account under RLS, and at launch nobody is signed in yet. A merchant installs the app,
/// opens it, *then* signs in — by which time registration has already run and been
/// refused.
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

      expect(tokens.tokens, isEmpty,
          reason: 'there is no account for the token to belong to');
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

    expect(tokens.tokens, ['tok-2'],
        reason: 'the stale one is dropped, not left beside the new one');
  });

  // A token arriving for nobody is a token filed against nobody. `users.fcm_tokens` is
  // written by the signed-in account under RLS, so the write would be refused anyway —
  // silently, which is how it would go unnoticed.
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
}
