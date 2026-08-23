import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import 'luqma_config.dart';

/// Where the owner's settings come from. An interface so the service's failure handling
/// can be tested without Firebase — which matters, because the failure handling is the
/// whole reason this class exists.
abstract interface class ConfigFetcher {
  Future<ConfigSource> fetch();
}

/// The single path from AdminApp to a phone in Edku.
///
/// Everything the owner changes without shipping an update arrives through here, which
/// makes it the one component that must never take the app down with it. A fetch that
/// fails, times out or returns nonsense leaves the app running on the last values it
/// knew were good — the phone is in someone's hand mid-order when that happens.
///
/// Widgets never read Remote Config directly. They read the config off the provider, so
/// there is exactly one place where a raw value becomes a value the app trusts.
class RemoteConfigService {
  RemoteConfigService(this._fetcher);

  final ConfigFetcher _fetcher;

  /// Compiled into the binary, so a cold start with no network still renders a correct
  /// app rather than an unconfigured one.
  LuqmaConfig _current = LuqmaConfig.defaults;

  LuqmaConfig get current => _current;

  /// Fetches and applies. Returns whether the server was actually reached.
  ///
  /// Never throws. A caller that has to wrap this in a try/catch would end up choosing,
  /// at every call site, what to do when the settings are unavailable — and the right
  /// answer is always the same: carry on with what you have.
  Future<bool> refresh() async {
    try {
      final source = await _fetcher.fetch();
      // Validated on the way in, so a value that arrived intact but is unusable falls
      // back per key rather than poisoning the whole config.
      _current = LuqmaConfig.from(source);
      return true;
    } catch (error, stackTrace) {
      debugPrint('remote config refresh failed: $error\n$stackTrace');
      return false;
    }
  }
}

/// Reads Firebase Remote Config. Deliberately thin — everything worth testing lives in
/// [RemoteConfigService] and [LuqmaConfig].
class FirebaseConfigFetcher implements ConfigFetcher {
  FirebaseConfigFetcher(this._remoteConfig);

  final FirebaseRemoteConfig _remoteConfig;

  /// How stale a cached value may be before a fetch goes to the network.
  ///
  /// Fifteen minutes rather than hours: this is how quickly a mistake made in AdminApp
  /// can be undone on phones already in the field.
  static const staleAfter = Duration(minutes: 15);

  @override
  Future<ConfigSource> fetch() async {
    await _remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: staleAfter,
      ),
    );
    await _remoteConfig.fetchAndActivate();

    return MapConfigSource({
      for (final entry in _remoteConfig.getAll().entries)
        entry.key: _typed(entry.value),
    });
  }

  /// Remote Config hands back every value as a string with accessors on the side. The
  /// app's validation is type-aware, so the string is turned back into what it plainly
  /// is before it gets there.
  static Object _typed(RemoteConfigValue value) {
    final raw = value.asString();
    if (raw == 'true' || raw == 'false') return raw == 'true';
    final asInt = int.tryParse(raw);
    if (asInt != null) return asInt;
    return raw;
  }
}

/// An in-memory fetcher for tests and for running against no backend at all.
class FakeConfigFetcher implements ConfigFetcher {
  FakeConfigFetcher(this.values);

  FakeConfigFetcher.failing() : values = {}, _failing = true;

  final Map<String, Object> values;
  bool _failing = false;

  void startFailing() => _failing = true;

  @override
  Future<ConfigSource> fetch() async {
    if (_failing) throw StateError('no network');
    return MapConfigSource(Map.of(values));
  }
}
