import 'package:admin_app/src/auth/admin_access.dart';
import 'package:admin_app/src/auth/identity_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Turning a Firebase session into the one answer the router needs.
void main() {
  ProviderContainer containerFor(Stream<AdminIdentity?> identity) {
    final container = ProviderContainer(
      overrides: [adminIdentityProvider.overrideWith((ref) => identity)],
    );
    addTearDown(container.dispose);
    addTearDown(container.listen(adminAccessProvider, (_, _) {}).close);
    return container;
  }

  // The distinction the whole gate rests on: "we do not know yet" is not "signed out".
  test('an unresolved stream reads as unknown, not as signed out', () {
    final container = containerFor(const Stream<AdminIdentity?>.empty());
    expect(container.read(adminAccessProvider), AdminAccess.unknown);
  });

  test('no user reads as signed out', () async {
    final container = containerFor(Stream.value(null));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(adminAccessProvider), AdminAccess.signedOut);
  });

  test('a user with the claim reads as granted', () async {
    final container = containerFor(
      Stream.value(const AdminIdentity(uid: 'u1', isAdmin: true)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(adminAccessProvider), AdminAccess.granted);
  });

  test('a user without it reads as not authorised', () async {
    final container = containerFor(
      Stream.value(const AdminIdentity(uid: 'u1', isAdmin: false)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(adminAccessProvider), AdminAccess.notAuthorised);
  });

  // If the session cannot be read at all, the safe reading of "we could not tell" is
  // that nobody is signed in — never that somebody is.
  test('a failing stream reads as signed out rather than granted', () async {
    final container = containerFor(
      Stream<AdminIdentity?>.error(StateError('boom')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(adminAccessProvider), AdminAccess.signedOut);
  });
}
