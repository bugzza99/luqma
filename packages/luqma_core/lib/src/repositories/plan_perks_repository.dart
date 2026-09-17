import 'package:supabase_flutter/supabase_flutter.dart';

import '../result.dart';

/// What a shop's active plan shows customers: a place at the top, a «موثّق» badge.
///
/// Read from the server rather than worked out on the phone from the plan and its expiry:
/// customers cannot read plans' prices or terms, and should not.
class MerchantPerk {
  const MerchantPerk({required this.merchantId, this.boost = false, this.verified = false});

  final String merchantId;
  final bool boost;
  final bool verified;
}

/// This month's free placements for one shop, and what its plan gives.
class PlanAllowance {
  const PlanAllowance({
    this.planActive = false,
    this.bannersIncluded = 0,
    this.bannersUsed = 0,
    this.pushesIncluded = 0,
    this.pushesUsed = 0,
    this.boost = false,
    this.verified = false,
  });

  final bool planActive;
  final int bannersIncluded;
  final int bannersUsed;
  final int pushesIncluded;
  final int pushesUsed;
  final bool boost;
  final bool verified;

  int get bannersLeft => (bannersIncluded - bannersUsed).clamp(0, bannersIncluded);
  int get pushesLeft => (pushesIncluded - pushesUsed).clamp(0, pushesIncluded);

  factory PlanAllowance.fromRow(Map<String, dynamic> row) => PlanAllowance(
        planActive: row['plan_active'] as bool? ?? false,
        bannersIncluded: (row['banners_included'] as num?)?.toInt() ?? 0,
        bannersUsed: (row['banners_used'] as num?)?.toInt() ?? 0,
        pushesIncluded: (row['pushes_included'] as num?)?.toInt() ?? 0,
        pushesUsed: (row['pushes_used'] as num?)?.toInt() ?? 0,
        boost: row['boost'] as bool? ?? false,
        verified: row['verified'] as bool? ?? false,
      );
}

abstract interface class PlanPerksRepository {
  /// Every shop whose active plan lifts it or badges it.
  Future<Result<List<MerchantPerk>>> perks();

  /// One shop's allowance this month. The owner of that shop, or an admin.
  Future<Result<PlanAllowance>> allowance(String merchantId);
}

class SupabasePlanPerksRepository implements PlanPerksRepository {
  SupabasePlanPerksRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<List<MerchantPerk>>> perks() {
    return Result.guard(() async {
      final rows = await _db.rpc('merchant_perks') as List? ?? const [];
      return [
        for (final raw in rows)
          if (raw is Map)
            MerchantPerk(
              merchantId: raw['merchant_id'] as String,
              boost: raw['boost'] as bool? ?? false,
              verified: raw['verified'] as bool? ?? false,
            ),
      ];
    });
  }

  @override
  Future<Result<PlanAllowance>> allowance(String merchantId) {
    return Result.guard(() async {
      final rows = await _db.rpc('plan_allowance', params: {'p_merchant_id': merchantId});
      final list = rows is List ? rows : [rows];
      if (list.isEmpty || list.first is! Map) return const PlanAllowance();
      return PlanAllowance.fromRow(Map<String, dynamic>.from(list.first as Map));
    });
  }
}

class FakePlanPerksRepository implements PlanPerksRepository {
  FakePlanPerksRepository({
    this.perkList = const [],
    this.allowances = const {},
    this.failure,
  });

  final List<MerchantPerk> perkList;
  final Map<String, PlanAllowance> allowances;
  final Failure? failure;

  @override
  Future<Result<List<MerchantPerk>>> perks() async =>
      failure != null ? Result.err(failure!) : Result.ok(perkList);

  @override
  Future<Result<PlanAllowance>> allowance(String merchantId) async => failure != null
      ? Result.err(failure!)
      : Result.ok(allowances[merchantId] ?? const PlanAllowance());
}
