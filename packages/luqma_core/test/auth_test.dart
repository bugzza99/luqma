import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Signing in.
///
/// The app is browsable signed out — the home screen, merchants, menus, the basket. The
/// account is asked for at the moment it is actually needed, which is checkout, so the
/// service has to say clearly which of three states somebody is in rather than folding
/// "we don't know yet" into "signed out".
void main() {
  group('the session', () {
    test('starts out unknown, not signed out', () async {
      final auth = FakeAuthService();

      // Treating an unresolved session as signed out throws a sign-in prompt at somebody
      // who is already signed in, on every cold start.
      expect(auth.state, AuthState.unknown);
    });

    test('resolves to signed out when nobody is signed in', () async {
      final auth = FakeAuthService();

      await auth.restore();

      expect(auth.state, AuthState.signedOut);
      expect(auth.identity, isNull);
    });

    test('resolves to signed in when a session was left behind', () async {
      final auth = FakeAuthService(
        restoring: const LuqmaIdentity(uid: 'u1', name: 'أحمد'),
      );

      await auth.restore();

      expect(auth.state, AuthState.signedIn);
      expect(auth.identity?.uid, 'u1');
    });
  });

  group('signing up', () {
    test('produces an identity carrying the phone', () async {
      final auth = FakeAuthService();

      final result = await auth.signUpWithPhone(
        phone: '01012345678',
        password: 'a-real-password',
        name: 'أحمد',
      );

      expect(result.valueOrNull?.uid, isNotEmpty);
      expect(result.valueOrNull?.phone, '01012345678');
      expect(auth.state, AuthState.signedIn);
    });

    // The phone is the identity. A second account on the same number is somebody
    // signing up for an account that already has their history — sign in, not sign up.
    test('the same phone twice is refused, not duplicated', () async {
      final auth = FakeAuthService();
      await auth.signUpWithPhone(
        phone: '01012345678',
        password: 'a-real-password',
        name: 'أحمد',
      );

      final result = await auth.signUpWithPhone(
        phone: '01012345678',
        password: 'a-different-password',
        name: 'شخص تاني',
      );

      expect(result.failureOrNull, isA<PhoneTakenFailure>());
    });

    test('a failed sign-up reports the failure and signs nobody in', () async {
      final auth = FakeAuthService(failure: const OfflineFailure());

      final result = await auth.signUpWithPhone(
        phone: '01012345678',
        password: 'a-real-password',
        name: 'أحمد',
      );

      expect(result.failureOrNull, isA<OfflineFailure>());
      expect(auth.state, AuthState.signedOut);
    });
  });

  group('signing in', () {
    test('produces an identity', () async {
      final auth = FakeAuthService();

      final result =
          await auth.signInWithPhone(phone: '01012345678', password: 'x');

      expect(result.valueOrNull?.uid, isNotEmpty);
      expect(auth.state, AuthState.signedIn);
    });

    test('the identity reaches everyone watching', () async {
      final auth = FakeAuthService();
      final seen = <LuqmaIdentity?>[];
      final sub = auth.changes.listen(seen.add);

      await auth.signInWithPhone(phone: '01012345678', password: 'x');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(seen.last?.uid, isNotEmpty);
    });

    // A screen that opens after somebody signed in has to be able to find out who they
    // are. Without this, the account tab would render as signed out until the next
    // change — which, for somebody who stays signed in, is never.
    test('a listener attaching afterwards still learns who it is', () async {
      final auth = FakeAuthService();
      await auth.signInWithPhone(phone: '01012345678', password: 'x');

      final first = await auth.changes.first.timeout(const Duration(seconds: 1));

      expect(first?.uid, 'fake-uid');
    });

    test('a failed sign-in reports the failure and signs nobody in', () async {
      final auth = FakeAuthService(failure: const OfflineFailure());

      final result =
          await auth.signInWithPhone(phone: '01012345678', password: 'x');

      expect(result.failureOrNull, isA<OfflineFailure>());
      expect(auth.state, AuthState.signedOut);
    });
  });

  group('signing out', () {
    test('clears the identity and tells everyone watching', () async {
      final auth = FakeAuthService();
      await auth.signInWithPhone(phone: '01012345678', password: 'x');

      final seen = <LuqmaIdentity?>[];
      final sub = auth.changes.listen(seen.add);
      await auth.signOut();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(auth.state, AuthState.signedOut);
      expect(auth.identity, isNull);
      expect(seen.last, isNull);
    });
  });
}
