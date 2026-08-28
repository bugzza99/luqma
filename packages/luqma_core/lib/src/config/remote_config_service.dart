import 'package:supabase_flutter/supabase_flutter.dart';
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

/// Reads the `config` table over PostgREST. Deliberately thin — everything worth testing
/// lives in [RemoteConfigService] and [LuqmaConfig].
class SupabaseConfigFetcher implements ConfigFetcher {
  SupabaseConfigFetcher(this._db);

  final SupabaseClient _db;

  @override
  Future<ConfigSource> fetch() async {
    // Values live as jsonb scalars, so they arrive already typed - a boolean comes back
    // a bool, an integer an int, and validation upstream stays type-aware.
    final rows = await _db.from('config').select('key, value');
    return MapConfigSource({
      for (final row in rows)
        if (row['value'] != null) row['key'] as String: row['value'] as Object,
    });
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
