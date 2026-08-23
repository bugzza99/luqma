import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Who is signed in, and the addresses that belong to them.
///
/// The two are one seam: an address list that outlives a sign-out would show one person
/// another person's home, which is the worst thing this app could get wrong.
void main() {
  ProviderContainer containerWith(AuthService auth, {AddressRepository? addresses}) {
    final container = ProviderContainer(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        if (addresses != null)
          addressRepositoryProvider.overrideWithValue(addresses),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('the identity', () {
    test('must be installed — the app cannot guess where a session comes from', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // The message has to name the fix: this one only ever fires at start-up, in
      // front of whoever forgot the override.
      expect(
        () => container.read(authServiceProvider),
        throwsA(
          predicate<Object>(
            (e) => e.toString().contains('Override authServiceProvider'),
          ),
        ),
      );
    });

    test('a restored session arrives without anybody signing in', () async {
      final container = containerWith(
        FakeAuthService(restoring: const LuqmaIdentity(uid: 'u1', name: 'أحمد')),
      );
      addTearDown(container.listen(currentIdentityProvider, (_, _) {}).close);

      final identity = await container.read(currentIdentityProvider.future);

      expect(identity?.uid, 'u1');
    });

    test('no session resolves to nobody rather than staying pending', () async {
      final container = containerWith(FakeAuthService());
      addTearDown(container.listen(currentIdentityProvider, (_, _) {}).close);

      expect(await container.read(currentIdentityProvider.future), isNull);
    });

    test('signing in reaches the provider', () async {
      final auth = FakeAuthService();
      final container = containerWith(auth);
      addTearDown(container.listen(currentIdentityProvider, (_, _) {}).close);
      await container.read(currentIdentityProvider.future);

      await auth.signInWithGoogle();
      await Future<void>.delayed(Duration.zero);

      expect(container.read(currentIdentityProvider).value?.uid, 'fake-uid');
    });
  });

  group('my addresses', () {
    const home = Address(id: 'a1', zoneId: 'z1', label: 'البيت');

    test('are empty while nobody is signed in', () async {
      final container = containerWith(
        FakeAuthService(),
        addresses: FakeAddressRepository(seed: const {'u1': [home]}),
      );
      addTearDown(container.listen(currentIdentityProvider, (_, _) {}).close);

      // Not an error and not a prompt: a signed-out customer browsing has no addresses,
      // which is a normal state, not a fault.
      expect(await container.read(myAddressesProvider.future), isEmpty);
    });

    test('come back for whoever is signed in', () async {
      final container = containerWith(
        FakeAuthService(restoring: const LuqmaIdentity(uid: 'u1')),
        addresses: FakeAddressRepository(seed: const {'u1': [home]}),
      );
      addTearDown(container.listen(currentIdentityProvider, (_, _) {}).close);

      final addresses = await container.read(myAddressesProvider.future);

      expect(addresses.single.label, 'البيت');
    });

    // The failure this whole seam exists to prevent.
    test('do not follow the previous person after a sign-out', () async {
      final auth = FakeAuthService(restoring: const LuqmaIdentity(uid: 'u1'));
      final container = containerWith(
        auth,
        addresses: FakeAddressRepository(seed: const {'u1': [home]}),
      );
      addTearDown(container.listen(currentIdentityProvider, (_, _) {}).close);
      addTearDown(container.listen(myAddressesProvider, (_, _) {}).close);
      expect(await container.read(myAddressesProvider.future), hasLength(1));

      await auth.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(await container.read(myAddressesProvider.future), isEmpty);
    });

    test('the chosen one is the default until somebody picks another', () async {
      final container = containerWith(
        FakeAuthService(restoring: const LuqmaIdentity(uid: 'u1')),
        addresses: FakeAddressRepository(
          seed: const {
            'u1': [home, Address(id: 'a2', zoneId: 'z2', label: 'الشغل')],
          },
        ),
      );
      addTearDown(container.listen(currentIdentityProvider, (_, _) {}).close);
      // Held the way a screen holds it: an auto-dispose provider with nobody listening
      // is disposed mid-load, which is not a state the app is ever in.
      addTearDown(container.listen(chosenAddressProvider, (_, _) {}).close);

      expect((await container.read(chosenAddressProvider.future))?.id, 'a1');
    });

    test('choosing one moves it', () async {
      final container = containerWith(
        FakeAuthService(restoring: const LuqmaIdentity(uid: 'u1')),
        addresses: FakeAddressRepository(
          seed: const {
            'u1': [home, Address(id: 'a2', zoneId: 'z2', label: 'الشغل')],
          },
        ),
      );
      addTearDown(container.listen(currentIdentityProvider, (_, _) {}).close);
      addTearDown(container.listen(chosenAddressProvider, (_, _) {}).close);
      await container.read(chosenAddressProvider.future);

      await container.read(addressActionsProvider).choose('a2');

      expect((await container.read(chosenAddressProvider.future))?.id, 'a2');
    });

    test('saving a new one shows up in the list', () async {
      final container = containerWith(
        FakeAuthService(restoring: const LuqmaIdentity(uid: 'u1')),
        addresses: FakeAddressRepository(),
      );
      addTearDown(container.listen(currentIdentityProvider, (_, _) {}).close);
      addTearDown(container.listen(myAddressesProvider, (_, _) {}).close);
      await container.read(myAddressesProvider.future);

      await container.read(addressActionsProvider).save(
            const Address(id: '', zoneId: 'z1', label: 'البيت'),
          );

      expect(await container.read(myAddressesProvider.future), hasLength(1));
    });

    // Saving into nowhere would look like it worked and lose the address.
    test('saving while signed out fails rather than pretending', () async {
      final container = containerWith(
        FakeAuthService(),
        addresses: FakeAddressRepository(),
      );
      addTearDown(container.listen(currentIdentityProvider, (_, _) {}).close);
      await container.read(myAddressesProvider.future);

      final result = await container.read(addressActionsProvider).save(
            const Address(id: '', zoneId: 'z1'),
          );

      expect(result.failureOrNull, isA<PermissionFailure>());
    });
  });
}
