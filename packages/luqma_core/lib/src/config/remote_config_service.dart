import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'luqma_config.dart';

/// Where the owner's settings come from. An interface so the service's failure handling
/// can be tested without Firebase — which matters, because the failure handling is the
/// whole reason this class exists.
///
/// It answers with the raw values rather than a [ConfigSource], because the last good
/// answer is kept on the phone and has to be written somewhere as it arrived.
abstract interface class ConfigFetcher {
  Future<Map<String, Object>> fetch();
}

/// Where the last good answer is kept between launches (E12).
///
/// Without it every cold start began on the values compiled into the binary, so a phone
/// opened in a street with no signal forgot what the owner had set — including a raised
/// minimum version, the one setting whose whole point is that it cannot be walked past.
/// What is kept is the raw answer, not a [LuqmaConfig]: it goes back through
/// [LuqmaConfig.from] on the way out, judged by the rules of the build reading it.
abstract interface class ConfigStore {
  /// The values last saved, or null when there are none or they cannot be read.
  Future<Map<String, Object>?> load();

  Future<void> save(Map<String, Object> values);
}

/// A [ConfigStore] in memory, for tests.
class MemoryConfigStore implements ConfigStore {
  Map<String, Object>? saved;

  @override
  Future<Map<String, Object>?> load() async => saved == null ? null : Map.of(saved!);

  @override
  Future<void> save(Map<String, Object> values) async => saved = Map.of(values);
}

/// The [ConfigStore] on a phone: one JSON string in shared preferences.
class SharedPreferencesConfigStore implements ConfigStore {
  static const key = 'luqma.config.last_good';

  @override
  Future<Map<String, Object>?> load() async {
    try {
      final text = (await SharedPreferences.getInstance()).getString(key);
      if (text == null) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return {
        for (final e in decoded.entries)
          if (e.key is String && e.value != null) e.key as String: e.value as Object,
      };
    } catch (_) {
      // A damaged record is the same as none: the binary's defaults, then the network.
      return null;
    }
  }

  @override
  Future<void> save(Map<String, Object> values) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, jsonEncode(values));
    } catch (_) {
      // Not saving costs the next offline cold start its values, nothing more.
    }
  }
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
  RemoteConfigService(
    this._fetcher, {
    this.store,
    this.timeout = const Duration(seconds: 10),
  });

  final ConfigFetcher _fetcher;

  /// Where the last good answer is kept between launches; none in tests and AdminApp.
  final ConfigStore? store;

  /// How long a fetch may take before it is treated as failed. Without one a request
  /// stalled on a weak connection never finished, and a caller awaiting it — the admin's
  /// settings screen, the force-update gate on resume — waited with it (E12).
  final Duration timeout;

  // Refreshes can overlap — the one `main` fires and the one the force-update gate fires
  // a moment later — and the network answers them in any order. Each is numbered as it
  // starts, and an answer older than one already applied is dropped.
  var _started = 0;
  var _applied = 0;

  /// Compiled into the binary, so a cold start with no network still renders a correct
  /// app rather than an unconfigured one.
  LuqmaConfig _current = LuqmaConfig.defaults;

  LuqmaConfig get current => _current;

  /// Loads the last good values kept on the phone, unless a fetch has already landed —
  /// the network's answer is newer than anything stored. Never throws.
  Future<void> restore() async {
    final saved = await store?.load();
    if (saved == null || _applied > 0) return;
    _current = LuqmaConfig.from(MapConfigSource(saved));
  }

  /// Fetches and applies. Returns whether the server was actually reached.
  ///
  /// Never throws. A caller that has to wrap this in a try/catch would end up choosing,
  /// at every call site, what to do when the settings are unavailable — and the right
  /// answer is always the same: carry on with what you have.
  Future<bool> refresh() async {
    final ticket = ++_started;
    try {
      final values = await _fetcher.fetch().timeout(timeout);
      // Reached the server either way; a newer answer simply got here first.
      if (ticket < _applied) return true;
      _applied = ticket;
      // Validated on the way in, so a value that arrived intact but is unusable falls
      // back per key rather than poisoning the whole config.
      _current = LuqmaConfig.from(MapConfigSource(values));
      unawaited(store?.save(values));
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
  Future<Map<String, Object>> fetch() async {
    // Values live as jsonb scalars, so they arrive already typed - a boolean comes back
    // a bool, an integer an int, and validation upstream stays type-aware.
    final rows = await _db.from('config').select('key, value');
    return {
      for (final row in rows)
        if (row['value'] != null) row['key'] as String: row['value'] as Object,
    };
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
  Future<Map<String, Object>> fetch() async {
    if (_failing) throw StateError('no network');
    return Map.of(values);
  }
}
