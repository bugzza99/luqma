import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../models/settlement.dart';
import '../result.dart';

/// A merchant's statement: what the platform took, order by order.
///
/// Read-only, and there is no write method here on purpose. Nothing in the product may
/// write this table from a client — the policy grants `select` and nothing else, and the
/// only thing that inserts a row is the settlement trigger running as its definer. A
/// repository with a `save` would be an interface promising something the database
/// refuses, which is how a screen comes to show a button that cannot work.
abstract interface class SettlementRepository {
  /// The merchant's settlements, newest first.
  ///
  /// [limit] because a statement screen shows a page, not a year. The policy already
  /// restricts this to the merchant's own rows (or an admin's view of anybody's), so the
  /// merchant id here narrows a query rather than granting anything.
  Future<Result<List<OrderSettlement>>> forMerchant(
    String merchantId, {
    int limit,
  });
}

class SupabaseSettlementRepository implements SettlementRepository {
  SupabaseSettlementRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<List<OrderSettlement>>> forMerchant(
    String merchantId, {
    int limit = 100,
  }) {
    return Result.guard(() async {
      final rows = await _db
          .from('order_settlements')
          .select()
          .eq('merchant_id', merchantId)
          // Newest first, spelled out. `order()` in this SDK defaults to descending,
          // which happens to be what this wants — and the flag is passed anyway, because
          // a reader should not have to know that to see the intent, and the one query in
          // this package that leaned on the default was wrong for a month.
          .order('settled_at', ascending: false)
          .limit(limit);

      return [
        for (final row in rows)
          OrderSettlement.fromJson(ColumnNames.toModel(row)),
      ];
    });
  }
}

/// Holds settlements in memory, for the screens and their tests.
class FakeSettlementRepository implements SettlementRepository {
  FakeSettlementRepository({List<OrderSettlement> seed = const [], this.failure})
      : _settlements = List.of(seed);

  final List<OrderSettlement> _settlements;

  /// When set, every call fails with this.
  final Failure? failure;

  @override
  Future<Result<List<OrderSettlement>>> forMerchant(
    String merchantId, {
    int limit = 100,
  }) async {
    if (failure != null) return Result.err(failure!);

    // The same filter and the same order as the real query, because a fake that returns
    // a differently-sorted list lets a screen pass a test and show yesterday's charge at
    // the top in the street.
    final mine = _settlements.where((s) => s.merchantId == merchantId).toList()
      ..sort((a, b) => (b.settledAt ?? DateTime(0))
          .compareTo(a.settledAt ?? DateTime(0)));
    return Result.ok(mine.take(limit).toList());
  }
}
