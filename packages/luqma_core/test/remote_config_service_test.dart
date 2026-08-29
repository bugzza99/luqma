import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The path from AdminApp to a phone in Edku.
///
/// Everything the owner controls without shipping an update arrives through here, which
/// makes this the one component that must never take the app down with it. A fetch that
/// fails, times out, or returns nonsense has to leave the app running on values it can
/// work with — the phone is in someone's hand mid-order when it happens.
void main() {
  group('loading', () {
    test('starts on the compiled-in defaults before any fetch', () {
      final service = RemoteConfigService(FakeConfigFetcher({}));
      expect(service.current, LuqmaConfig.defaults);
    });

    test('a successful fetch replaces them', () async {
      final service = RemoteConfigService(
        FakeConfigFetcher({'accept_timeout_minutes': 8, 'otp_enabled': true}),
      );

      await service.refresh();

      expect(service.current.acceptTimeoutMinutes, 8);
      expect(service.current.otpEnabled, isTrue);
    });

    test('refresh reports whether it actually reached the server', () async {
      final good = RemoteConfigService(FakeConfigFetcher({}));
      final bad = RemoteConfigService(FakeConfigFetcher.failing());

      expect(await good.refresh(), isTrue);
      expect(await bad.refresh(), isFalse);
    });
  });

  group('when the fetch fails', () {
    test('it does not throw at the caller', () async {
      final service = RemoteConfigService(FakeConfigFetcher.failing());
      await expectLater(service.refresh(), completes);
    });

    test('the defaults are still there on a first-run failure', () async {
      final service = RemoteConfigService(FakeConfigFetcher.failing());
      await service.refresh();
      expect(service.current, LuqmaConfig.defaults);
    });

    // The case that matters most: the app was configured, then the network dropped. It
    // must keep the configuration it already had rather than silently reverting to
    // whatever shipped in the binary months ago.
    test('a later failure keeps the last good values', () async {
      final fetcher = FakeConfigFetcher({'accept_timeout_minutes': 8});
      final service = RemoteConfigService(fetcher);
      await service.refresh();

      fetcher.startFailing();
      await service.refresh();

      expect(service.current.acceptTimeoutMinutes, 8);
    });
  });

  group('what arrives is still validated', () {
    test('a value out of range is refused even though the fetch succeeded', () async {
      final service = RemoteConfigService(
        FakeConfigFetcher({'accept_timeout_minutes': 0}),
      );

      await service.refresh();

      expect(
        service.current.acceptTimeoutMinutes,
        LuqmaConfig.defaults.acceptTimeoutMinutes,
      );
    });
  });

  group('the provider', () {
    test('exposes whatever the service last loaded', () async {
      final service = RemoteConfigService(
        FakeConfigFetcher({'marketing_push_per_week': 1}),
      );
      await service.refresh();

      final container = ProviderContainer(
        overrides: [remoteConfigServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      expect(container.read(appConfigProvider).marketingPushPerWeek, 1);
    });

    test('a refresh reaches anything watching the config', () async {
      final fetcher = FakeConfigFetcher({});
      final service = RemoteConfigService(fetcher);
      final container = ProviderContainer(
        overrides: [remoteConfigServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      expect(container.read(appConfigProvider).otpEnabled, isFalse);

      fetcher.values['otp_enabled'] = true;
      await container.read(appConfigProvider.notifier).refresh();

      expect(container.read(appConfigProvider).otpEnabled, isTrue);
    });
  });
}
