import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The point of putting an interface between the app and Firestore was that the layers
/// above could be built and tested without a backend. These tests are that claim, checked:
/// nothing below touches Firebase, a network, or an emulator.
void main() {
  Merchant merchant(String id, {MerchantStatus status = MerchantStatus.approved}) =>
      Merchant(
        id: id,
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: id,
        zoneId: 'z1',
        phone: '01000000000',
        status: status,
      );

  ProviderContainer containerWith(MerchantRepository repository) {
    final container = ProviderContainer(
      overrides: [merchantRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('merchants', () {
    test('the list comes from whatever repository is installed', () async {
      final container = containerWith(
        FakeMerchantRepository(seed: [merchant('a'), merchant('b')]),
      );

      // Hold a subscription the way a widget on screen does: a stream provider with no
      // listener is disposed before it can emit, which is not a state the app is ever in.
      addTearDown(container.listen(merchantsProvider('edku'), (_, _) {}).close);

      final merchants = await container.read(merchantsProvider('edku').future);

      expect(merchants.map((m) => m.id), ['a', 'b']);
    });

    test('a repository failure surfaces as an error, not as an empty list', () async {
      final container = containerWith(
        FakeMerchantRepository(failure: const OfflineFailure()),
      );
      addTearDown(container.listen(merchantsProvider('edku'), (_, _) {}).close);
      await Future<void>.delayed(Duration.zero);

      // Asserted on the AsyncValue rather than the future, because the AsyncValue is what
      // a screen actually renders from.
      final state = container.read(merchantsProvider('edku'));

      // An empty list would be read by the interface as "there are no restaurants in
      // Edku", which is a very different thing to tell someone than "you are offline".
      expect(state.hasError, isTrue);
      expect(state.error, isA<OfflineFailure>());
      expect(state.value, isNull);
    });

    test('two watchers of the same city share one subscription', () async {
      final container = containerWith(FakeMerchantRepository(seed: [merchant('a')]));

      final first = container.read(merchantsProvider('edku'));
      final second = container.read(merchantsProvider('edku'));

      expect(identical(first, second), isTrue);
    });

    test('a different city is a different subscription', () {
      final container = containerWith(FakeMerchantRepository());

      expect(
        identical(
          container.read(merchantsProvider('edku')),
          container.read(merchantsProvider('rosetta')),
        ),
        isFalse,
      );
    });
  });

  // The config provider's own behaviour is covered in remote_config_service_test.dart,
  // which owns the whole path from a fetch to a value the app trusts. Repeating it here
  // would mean two places to update when the contract changes.

  group('the city being served', () {
    test('defaults to Edku', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(currentCityProvider), 'edku');
    });

    // Every query is scoped by city already, so opening a second one is a value change
    // rather than a migration.
    test('can be pointed at another city', () {
      final container = ProviderContainer(
        overrides: [currentCityProvider.overrideWithValue('rosetta')],
      );
      addTearDown(container.dispose);

      expect(container.read(currentCityProvider), 'rosetta');
    });
  });
}
