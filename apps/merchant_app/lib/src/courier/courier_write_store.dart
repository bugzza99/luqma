import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The courier queue's store.
///
/// A JSON list under one key — the queue is a handful of writes at most, and it is the
/// one thing that must survive an app being killed between a tap in the street and a
/// connection coming back.
///
/// **`SharedPreferencesAsync`, not the legacy `SharedPreferences`.** The legacy API keeps
/// an in-memory cache and writes through to the platform store afterwards, so its
/// documentation says plainly that a completed `setString` is not yet a write to disk and
/// that it must not be used for critical data. That is the whole of what this class
/// stores: a courier's tap on "delivered", which is cash already in their pocket against
/// an order the system still believes is out. The async API talks to the platform store
/// on every call and the future it returns is the platform's answer.
///
/// A database would be more durable still, and it is not worth it here: at most a few
/// small records, written one at a time, read once at launch. What was worth fixing is
/// the API that was documented as unsuitable for exactly this.
class SharedPreferencesCourierWriteStore implements CourierWriteStore {
  SharedPreferencesCourierWriteStore({SharedPreferencesAsync? prefs})
      : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;

  static const _key = 'courier_write_queue';

  @override
  Future<List<PendingCourierWrite>> load() async {
    final raw = await _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];

    // A value that cannot be read is an empty queue, not an exception.
    //
    // `load()` is awaited at the top of every `_submit`, so a throw here would not lose
    // the stored writes — it would stop the courier making any new one, for good, with
    // no way to clear it from the street. Losing what is already corrupt is bad; losing
    // that *and* everything the courier does for the rest of the shift is worse.
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          PendingCourierWrite.fromJson(Map<String, dynamic>.from(item as Map)),
      ];
    } on Object catch (error) {
      debugPrint('courier queue unreadable, starting empty: $error');
      return const [];
    }
  }

  @override
  Future<void> save(List<PendingCourierWrite> pending) async {
    if (pending.isEmpty) {
      await _prefs.remove(_key);
      return;
    }
    await _prefs.setString(
      _key,
      jsonEncode([for (final write in pending) write.toJson()]),
    );
  }
}
