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
/// The envelope holds the writes still waiting and the ones the server refused on
/// replay, because the courier is owed news of both and an app kill must not erase
/// either.
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

  /// 2 carries the refused writes beside the pending ones. Version 1 held pending only,
  /// and a phone upgrading from it still has its queued cash writes there — see
  /// [_fromVersion1].
  static const _schemaVersion = 2;

  static String _key(String accountId, int version) =>
      '$_keyStem.$accountId.v$version';

  static String _accountKeyPrefix(String accountId) =>
      '$_keyStem.$accountId.v';

  @override
  Future<StoredCourierWrites> load({required String accountId}) async {
    // A value that cannot be read is an empty queue, not an exception.
    //
    // `load()` is awaited at the top of every `_submit`, so a throw here would not lose
    // the stored writes — it would stop the courier making any new one, for good, with
    // no way to clear it from the street. Losing what is already corrupt is bad; losing
    // that *and* everything the courier does for the rest of the shift is worse.
    try {
      final raw = await _prefs.getString(_key(accountId, _schemaVersion));
      if (raw != null && raw.isNotEmpty) {
        // A move from version 1 killed between its write and its removal leaves the old
        // key behind. Harmless while this key exists; the day the queue empties and this
        // key goes, it would bring back writes that were settled long ago.
        await _prefs.remove(_key(accountId, 1));
        return _decodeEnvelope(raw);
      }

      final previous = await _fromVersion1(accountId);
      if (previous != null) return previous;

      final legacy = await _prefs.getString(_legacyKey);
      if (legacy != null && legacy.isNotEmpty) {
        final writes = _decodeWrites(jsonDecode(legacy));
        final owner = await _prefs.getString(_legacyOwnerKey);
        if (owner != null && owner != accountId) return StoredCourierWrites.empty;

        // The claim lands before the copy, so an interrupted migration can be retried
        // only by the courier who was signed in when this build first saw the old key.
        // Without it, a kill between copying and removing could hand the same cash writes
        // to whoever signs in next.
        if (owner == null) await _prefs.setString(_legacyOwnerKey, accountId);
        final migrated = StoredCourierWrites(pending: writes);
        await _write(accountId, migrated);
        await _prefs.remove(_legacyKey);
        return migrated;
      }

      final newerVersion = await _newerVersionFor(accountId);
      if (newerVersion != null) {
        debugPrint(
          'courier queue schema $newerVersion is newer than $_schemaVersion; '
          'preserving it and starting a separate queue',
        );
      }
      return StoredCourierWrites.empty;
    } on Object catch (error) {
      debugPrint('courier queue unreadable, starting empty: $error');
      return StoredCourierWrites.empty;
    }
  }

  /// This account's queue as the previous build left it, moved to the current key.
  ///
  /// Written first and removed second, so a kill between the two leaves the current key
  /// in place — which [load] reads before it ever looks here — rather than no queue at
  /// all. Version 1 never kept refused writes, so there are none to bring.
  Future<StoredCourierWrites?> _fromVersion1(String accountId) async {
    final key = _key(accountId, 1);
    final raw = await _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['version'] != 1) return null;
    final migrated = StoredCourierWrites(pending: _decodeWrites(decoded['writes']));
    await _write(accountId, migrated);
    await _prefs.remove(key);
    return migrated;
  }

  @override
  Future<void> save({
    required String accountId,
    required List<PendingCourierWrite> pending,
    required List<PendingCourierWrite> rejected,
  }) async {
    if (pending.isEmpty && rejected.isEmpty) {
      await _prefs.remove(_key(accountId, _schemaVersion));
      return;
    }
    await _write(
      accountId,
      StoredCourierWrites(pending: pending, rejected: rejected),
    );
  }

  Future<void> _write(String accountId, StoredCourierWrites stored) =>
      _prefs.setString(
        _key(accountId, _schemaVersion),
        jsonEncode({
          'version': _schemaVersion,
          'writes': [for (final write in stored.pending) write.toJson()],
          'rejected': [for (final write in stored.rejected) write.toJson()],
        }),
      );

  StoredCourierWrites _decodeEnvelope(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return StoredCourierWrites.empty;
    final envelope = Map<String, dynamic>.from(decoded);
    if (envelope['version'] != _schemaVersion) return StoredCourierWrites.empty;
    return StoredCourierWrites(
      pending: _decodeWrites(envelope['writes']),
      rejected: _decodeWrites(envelope['rejected']),
    );
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
