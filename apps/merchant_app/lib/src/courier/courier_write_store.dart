import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The courier queue's store.
///
/// One versioned JSON envelope per account — the queue is a handful of writes at most,
/// and it is the one thing that must survive an app being killed between a tap in the
/// street and a connection coming back. The account is in the key because a shared shop
/// handset changing couriers must change queues before anything can be replayed.
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

  static const _legacyKey = 'courier_write_queue';
  static const _legacyOwnerKey = 'courier_write_queue.legacy_owner';
  static const _keyStem = 'courier_write_queue.account';
  static const _schemaVersion = 1;

  static String _key(String accountId, int version) =>
      '$_keyStem.$accountId.v$version';

  static String _accountKeyPrefix(String accountId) =>
      '$_keyStem.$accountId.v';

  @override
  Future<List<PendingCourierWrite>> load({required String accountId}) async {
    // A value that cannot be read is an empty queue, not an exception.
    //
    // `load()` is awaited at the top of every `_submit`, so a throw here would not lose
    // the stored writes — it would stop the courier making any new one, for good, with
    // no way to clear it from the street. Losing what is already corrupt is bad; losing
    // that *and* everything the courier does for the rest of the shift is worse.
    try {
      final raw = await _prefs.getString(_key(accountId, _schemaVersion));
      if (raw != null && raw.isNotEmpty) return _decodeEnvelope(raw);

      final legacy = await _prefs.getString(_legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        final writes = _decodeWrites(jsonDecode(legacy));
        final owner = await _prefs.getString(_legacyOwnerKey);
        if (owner != null && owner != accountId) return const [];

        // The claim lands before the copy, so an interrupted migration can be retried
        // only by the courier who was signed in when this build first saw the old key.
        // Without it, a kill between copying and removing could hand the same cash writes
        // to whoever signs in next.
        if (owner == null) await _prefs.setString(_legacyOwnerKey, accountId);
        await _write(accountId, writes);
        await _prefs.remove(_legacyKey);
        return writes;
      }

      final newerVersion = await _newerVersionFor(accountId);
      if (newerVersion != null) {
        debugPrint(
          'courier queue schema $newerVersion is newer than $_schemaVersion; '
          'preserving it and starting a separate queue',
        );
      }
      return const [];
    } on Object catch (error) {
      debugPrint('courier queue unreadable, starting empty: $error');
      return const [];
    }
  }

  @override
  Future<void> save({
    required String accountId,
    required List<PendingCourierWrite> pending,
  }) async {
    if (pending.isEmpty) {
      await _prefs.remove(_key(accountId, _schemaVersion));
      return;
    }
    await _write(accountId, pending);
  }

  Future<void> _write(
    String accountId,
    List<PendingCourierWrite> pending,
  ) =>
      _prefs.setString(
        _key(accountId, _schemaVersion),
        jsonEncode({
          'version': _schemaVersion,
          'writes': [for (final write in pending) write.toJson()],
        }),
      );

  List<PendingCourierWrite> _decodeEnvelope(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const [];
    final envelope = Map<String, dynamic>.from(decoded);
    if (envelope['version'] != _schemaVersion) return const [];
    return _decodeWrites(envelope['writes']);
  }

  List<PendingCourierWrite> _decodeWrites(Object? decoded) {
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        PendingCourierWrite.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  Future<int?> _newerVersionFor(String accountId) async {
    final prefix = _accountKeyPrefix(accountId);
    int? newest;
    for (final key in await _prefs.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      final version = int.tryParse(key.substring(prefix.length));
      if (version != null && version > _schemaVersion) {
        newest = newest == null || version > newest ? version : newest;
      }
    }
    return newest;
  }
}
