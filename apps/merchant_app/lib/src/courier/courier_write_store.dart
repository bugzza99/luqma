import 'dart:convert';

import 'package:luqma_core/luqma_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The courier queue's store, backed by shared_preferences.
///
/// A JSON list under one key — the queue is a handful of writes at most, and it is the
/// one thing that must survive an app being killed between a tap in the street and a
/// connection coming back.
class SharedPreferencesCourierWriteStore implements CourierWriteStore {
  static const _key = 'courier_write_queue';

  @override
  Future<List<PendingCourierWrite>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        PendingCourierWrite.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  @override
  Future<void> save(List<PendingCourierWrite> pending) async {
    final prefs = await SharedPreferences.getInstance();
    if (pending.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(
      _key,
      jsonEncode([for (final write in pending) write.toJson()]),
    );
  }
}
