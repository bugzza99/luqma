import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/merchant_sales.dart';
import '../models/order.dart';
import '../result.dart';

/// What a shop sold, counted once and in one place.
///
/// Backed by `public.merchant_sales(p_merchant_id uuid, p_days integer)`:
/// read-only, security invoker over the merchant's orders, and returning
/// delivered food sales, average order value, cancellations, daily bars,
/// and top dishes.
abstract interface class MerchantSalesRepository {
  /// Fetches sales figures for [merchantId] over [days] (default 7, clamped 1..90).
  Future<Result<MerchantSales>> getSales(String merchantId, {int days = 7});
}

class SupabaseMerchantSalesRepository implements MerchantSalesRepository {
  SupabaseMerchantSalesRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<MerchantSales>> getSales(String merchantId, {int days = 7}) {
    return Result.guard(() async {
      final data = await _db.rpc(
        'merchant_sales',
        params: {
          'p_merchant_id': merchantId,
          'p_days': days,
        },
      );
      if (data == null) return MerchantSales.empty;
      return MerchantSales.fromJson(Map<String, dynamic>.from(data as Map));
    });
  }
}

/// In-memory sales figures computed from seeded orders for tests.
///
/// Re-applies the exact same rules as the Postgres function `merchant_sales`:
/// delivered only, food only, cancellations split by who cancelled, with every
/// day represented in the window.
class FakeMerchantSalesRepository implements MerchantSalesRepository {
  FakeMerchantSalesRepository({
    List<Order> seed = const [],
    this.failure,
    DateTime Function()? now,
  })  : _orders = List.of(seed),
        _now = now ?? DateTime.now;

  final List<Order> _orders;
  final Failure? failure;
  final DateTime Function() _now;

  @override
  Future<Result<MerchantSales>> getSales(String merchantId, {int days = 7}) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(MerchantSales.of(
      _orders,
      merchantId: merchantId,
      days: days,
      now: _now,
    ));
  }
}
