import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  // E12. Three ways the path from AdminApp could still leave a phone wrong.
  group('a fetch that hangs', () {
    test('is given up on, and the values standing stay', () async {
      final service = RemoteConfigService(
        _ControlledFetcher(),
        timeout: const Duration(milliseconds: 20),
      );

      expect(await service.refresh(), isFalse);
      expect(service.current, LuqmaConfig.defaults);
    });
  });

  group('two refreshes at once', () {
    test('the older answer arriving last does not undo the newer one', () async {
      final fetcher = _ControlledFetcher();
      final service = RemoteConfigService(fetcher);

      final older = service.refresh();
      final newer = service.refresh();
      fetcher.answer(1, {'accept_timeout_minutes': 9});
      await newer;
      fetcher.answer(0, {'accept_timeout_minutes': 3});
      await older;

      expect(service.current.acceptTimeoutMinutes, 9);
    });
  });

  group('a cold start with no network', () {
    // The case the force-update wall depends on: an owner raised the minimum version,
    // and a phone that has seen that once must not forget it the next time it opens in
    // a street with no signal.
    test('runs on the last values it fetched, not on the binary', () async {
      final store = MemoryConfigStore();
      final first = RemoteConfigService(
        FakeConfigFetcher({'min_supported_version': '0.9.5', 'accept_timeout_minutes': 8}),
        store: store,
      );
      await first.refresh();

      final second = RemoteConfigService(FakeConfigFetcher.failing(), store: store);
      await second.restore();
      await second.refresh();

      expect(second.current.minSupportedVersion, '0.9.5');
      expect(second.current.acceptTimeoutMinutes, 8);
    });

    test('a fetch that already landed is not replaced by what was stored', () async {
      final store = MemoryConfigStore()..saved = {'accept_timeout_minutes': 3};
      final service = RemoteConfigService(
        FakeConfigFetcher({'accept_timeout_minutes': 9}),
        store: store,
      );

      await service.refresh();
      await service.restore();

      expect(service.current.acceptTimeoutMinutes, 9);
    });

    test('a stored value is judged by the same rules as a fetched one', () async {
      final store = MemoryConfigStore()..saved = {'accept_timeout_minutes': 999};
      final service = RemoteConfigService(FakeConfigFetcher.failing(), store: store);

      await service.restore();

      expect(service.current.acceptTimeoutMinutes,
          LuqmaConfig.defaults.acceptTimeoutMinutes);
    });

    test('the phone store gives back what it was given', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesConfigStore();

      await store.save({'otp_enabled': true, 'accept_timeout_minutes': 8, 'x': 'y'});

      expect(await store.load(),
          {'otp_enabled': true, 'accept_timeout_minutes': 8, 'x': 'y'});
    });

    test('a damaged record on the phone is nothing, not a crash', () async {
      SharedPreferences.setMockInitialValues({SharedPreferencesConfigStore.key: '{nope'});

      expect(await SharedPreferencesConfigStore().load(), isNull);
    });
  });
}

/// Answers each fetch when told to, by the order it was asked in.
class _ControlledFetcher implements ConfigFetcher {
  final _pending = <Completer<Map<String, Object>>>[];

  @override
  Future<Map<String, Object>> fetch() {
    final c = Completer<Map<String, Object>>();
    _pending.add(c);
    return c.future;
  }

  void answer(int index, Map<String, Object> values) => _pending[index].complete(values);
}
