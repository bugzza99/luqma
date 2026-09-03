import 'package:supabase_flutter/supabase_flutter.dart';

import '../result.dart';

/// The admin's write path to the control plane.
///
/// The rows are the same ones the customer fetches — the difference is the write.
/// [setValues] goes through `admin_set_config`, a SECURITY DEFINER function that checks
/// `is_admin()` and stamps an audit row, so a config change is recorded like every other
/// admin mutation rather than being a silent upsert anyone with a token could make.
abstract interface class ConfigRepository {
  /// Every config row, keyed by name, already typed from jsonb.
  Future<Result<Map<String, Object>>> readAll();

  /// Upserts the given keys and returns the full persisted config. Keys absent from
  /// [values] are left alone.
  Future<Result<Map<String, Object>>> setValues(Map<String, Object> values);
}

class SupabaseConfigRepository implements ConfigRepository {
  SupabaseConfigRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<Map<String, Object>>> readAll() {
    return Result.guard(() async {
      final rows = await _db.from('config').select('key, value');
      return {
        for (final row in rows)
          if (row['value'] != null)
            row['key'] as String: row['value'] as Object,
      };
    });
  }

  @override
  Future<Result<Map<String, Object>>> setValues(Map<String, Object> values) {
    return Result.guard(() async {
      final persisted = await _db.rpc(
        'admin_set_config',
        params: {'p_values': values},
      );
      if (persisted is! Map) {
        throw StateError('admin_set_config returned a non-object response');
      }
      return {
        for (final entry in persisted.entries)
          if (entry.value != null) entry.key.toString(): entry.value as Object,
      };
    });
  }
}

/// In-memory config, for tests and for building the screen above it.
class FakeConfigRepository implements ConfigRepository {
  FakeConfigRepository({
    Map<String, Object> seed = const {},
    this.failure,
    this.setFailure,
    this.returnedValues,
  }) : _values = Map.of(seed);

  final Map<String, Object> _values;
  final Failure? failure;
  final Failure? setFailure;

  /// Optional server-normalized response used by controller/widget tests.
  final Map<String, Object>? returnedValues;

  /// Every [setValues] call, so a test can assert exactly what the screen wrote.
  final List<Map<String, Object>> setCalls = [];

  @override
  Future<Result<Map<String, Object>>> readAll() async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(Map.of(_values));
  }

  @override
  Future<Result<Map<String, Object>>> setValues(
    Map<String, Object> values,
  ) async {
    final writeFailure = setFailure ?? failure;
    if (writeFailure != null) return Result.err(writeFailure);
    setCalls.add(Map.of(values));
    _values.addAll(values);
    if (returnedValues != null) {
      _values
        ..clear()
        ..addAll(returnedValues!);
    }
    return Result.ok(Map.of(_values));
  }
}
