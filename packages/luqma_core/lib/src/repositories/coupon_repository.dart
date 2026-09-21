import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/live_query.dart';
import '../models/coupon.dart';
import '../result.dart';

/// Coupons management for merchant owners (their own shop) and platform admins.
abstract interface class CouponRepository {
  /// Watches coupons for a specific merchant.
  Stream<List<Coupon>> watchForMerchant(String merchantId);

  /// Lists all coupons on the platform (admin; newest first).
  Future<Result<List<Coupon>>> listAll();

  /// Creates a new coupon. Code is stored normalized via [Coupon.normalizeCode].
  /// id, usedCount and createdByUid are assigned by the server.
  Future<Result<Coupon>> create(Coupon draft);

  /// Updates editable fields on an existing coupon: code, type, value,
  /// maxDiscount, minOrder, firstOrderOnly, perUserLimit, totalLimit,
  /// validFrom, validUntil, isActive (and for admin, fundedBy).
  Future<Result<void>> update(Coupon coupon);

  /// Toggles active status of a coupon.
  Future<Result<void>> setActive(String id, bool active);
}

class SupabaseCouponRepository implements CouponRepository {
  SupabaseCouponRepository(this._db);

  final SupabaseClient _db;

  @override
  Stream<List<Coupon>> watchForMerchant(String merchantId) {
    return watchRows(
      db: _db,
      table: 'coupons',
      map: _fromRow,
      filters: [RowFilter('merchant_id', merchantId)],
      orderBy: 'created_at',
      ascending: false,
    );
  }

  @override
  Future<Result<List<Coupon>>> listAll() {
    return Result.guard(() async {
      final rows = await _db
          .from('coupons')
          .select()
          .order('created_at', ascending: false);
      return rows.map(_fromRow).toList();
    });
  }

  @override
  Future<Result<Coupon>> create(Coupon draft) {
    if (draft.type == CouponType.percentage && draft.maxDiscount == null) {
      return Future.value(const Result.err(ValidationFailure()));
    }

    return Result.guard(() async {
      final row = await _db.rpc(
        'create_coupon',
        params: {
          'p_code': Coupon.normalizeCode(draft.code),
          'p_city_id': draft.cityId,
          'p_type': draft.type.name,
          'p_value': draft.value,
          'p_max_discount': draft.maxDiscount,
          'p_min_order': draft.minOrder,
          'p_merchant_id': draft.merchantId,
          'p_first_order_only': draft.firstOrderOnly,
          'p_per_user_limit': draft.perUserLimit,
          'p_total_limit': draft.totalLimit,
          'p_is_active': draft.isActive,
          'p_funded_by': draft.fundedBy.name,
          'p_valid_from': draft.validFrom?.toUtc().toIso8601String(),
          'p_valid_until': draft.validUntil?.toUtc().toIso8601String(),
        },
      );
      return _fromRow(Map<String, dynamic>.from(row as Map));
    });
  }

  @override
  Future<Result<void>> update(Coupon coupon) {
    if (coupon.type == CouponType.percentage && coupon.maxDiscount == null) {
      return Future.value(const Result.err(ValidationFailure()));
    }

    return Result.guard(() async {
      await _db.rpc(
        'update_coupon',
        params: {
          'p_id': coupon.id,
          'p_code': Coupon.normalizeCode(coupon.code),
          'p_type': coupon.type.name,
          'p_value': coupon.value,
          'p_max_discount': coupon.maxDiscount,
          'p_min_order': coupon.minOrder,
          'p_first_order_only': coupon.firstOrderOnly,
          'p_per_user_limit': coupon.perUserLimit,
          'p_total_limit': coupon.totalLimit,
          'p_is_active': coupon.isActive,
          'p_funded_by': coupon.fundedBy.name,
          'p_valid_from': coupon.validFrom?.toUtc().toIso8601String(),
          'p_valid_until': coupon.validUntil?.toUtc().toIso8601String(),
        },
      );
    });
  }

  @override
  Future<Result<void>> setActive(String id, bool active) {
    return Result.guard(() async {
      await _db.rpc(
        'set_coupon_active',
        params: {'p_id': id, 'p_active': active},
      );
    });
  }

  static Coupon _fromRow(Map<String, dynamic> row) {
    return Coupon(
      id: row['id'] as String,
      code: row['code'] as String,
      cityId: row['city_id'] as String,
      type: switch (row['type']) {
        'fixedAmount' => CouponType.fixedAmount,
        'freeDelivery' => CouponType.freeDelivery,
        _ => CouponType.percentage,
      },
      value: (row['value'] as num).toInt(),
      maxDiscount: (row['max_discount'] as num?)?.toInt(),
      minOrder: (row['min_order'] as num?)?.toInt() ?? 0,
      merchantId: row['merchant_id'] as String?,
      firstOrderOnly: row['first_order_only'] as bool? ?? false,
      perUserLimit: (row['per_user_limit'] as num?)?.toInt() ?? 0,
      totalLimit: (row['total_limit'] as num?)?.toInt() ?? 0,
      usedCount: (row['used_count'] as num?)?.toInt() ?? 0,
      isActive: row['is_active'] as bool? ?? true,
      validFrom: row['valid_from'] != null
          ? DateTime.parse(row['valid_from'] as String).toLocal()
          : null,
      validUntil: row['valid_until'] != null
          ? DateTime.parse(row['valid_until'] as String).toLocal()
          : null,
      fundedBy: row['funded_by'] == 'platform'
          ? CouponFunder.platform
          : CouponFunder.merchant,
      createdByUid: row['created_by'] as String?,
    );
  }
}

/// In-memory coupons, for tests and building screens above it.
class FakeCouponRepository implements CouponRepository {
  FakeCouponRepository({
    List<Coupon> seed = const [],
    this.failure,
    this.isAdmin = true,
    this.merchantId,
    this.actingUid = 'fake-admin-uid',
    this.merchantCities = const {},
  }) : _coupons = {for (final c in seed) c.id: c};

  /// merchant id -> city id, so a shop's coupon in another city is refused as the trigger
  /// refuses it. A merchant missing here is not checked.
  final Map<String, String> merchantCities;

  final Map<String, Coupon> _coupons;
  final Failure? failure;
  final bool isAdmin;
  final String? merchantId;
  final String actingUid;

  final _changed = StreamController<void>.broadcast();

  Stream<T> _live<T>(T Function() read) => Stream.multi((listener) {
    listener.add(read());
    final sub = _changed.stream.listen((_) => listener.add(read()));
    listener.onCancel = sub.cancel;
  });

  void _notify() {
    if (!_changed.isClosed) _changed.add(null);
  }

  void dispose() => _changed.close();

  @override
  Stream<List<Coupon>> watchForMerchant(String targetMerchantId) {
    if (failure != null) return Stream.error(failure!);
    return _live(() {
      // If merchant-scoped caller asks for another merchant, RLS returns empty list
      if (!isAdmin && merchantId != null && targetMerchantId != merchantId) {
        return const [];
      }
      return _newestFirst(
        _coupons.values.where(
          (c) => c.merchantId == targetMerchantId && _visible(c),
        ),
      );
    });
  }

  /// What the caller's policies let them see: an admin everything, an owner their own
  /// shop's merchant-funded coupons, anybody else nothing.
  bool _visible(Coupon c) =>
      isAdmin ||
      (merchantId != null &&
          c.merchantId == merchantId &&
          c.fundedBy == CouponFunder.merchant);

  /// The table's check constraints.
  static bool _valid(Coupon c) =>
      c.value >= 0 &&
      (c.maxDiscount == null || c.maxDiscount! >= 0) &&
      c.minOrder >= 0 &&
      c.perUserLimit >= 0 &&
      c.totalLimit >= 0 &&
      (c.type != CouponType.percentage || c.maxDiscount != null) &&
      (c.validFrom == null ||
          c.validUntil == null ||
          c.validUntil!.isAfter(c.validFrom!));

  /// Newest first, the way production orders by `created_at`: insertion order reversed.
  List<Coupon> _newestFirst(Iterable<Coupon> coupons) {
    final order = _coupons.keys.toList();
    return coupons.toList()
      ..sort((a, b) => order.indexOf(b.id).compareTo(order.indexOf(a.id)));
  }

  @override
  Future<Result<List<Coupon>>> listAll() async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(_newestFirst(_coupons.values.where(_visible)));
  }

  @override
  Future<Result<Coupon>> create(Coupon draft) async {
    if (failure != null) return Result.err(failure!);

    if (!_valid(draft)) return const Result.err(ValidationFailure());

    // Merchant scope restrictions
    if (!isAdmin) {
      if (merchantId == null || draft.merchantId != merchantId) {
        return const Result.err(PermissionFailure());
      }
      if (draft.fundedBy != CouponFunder.merchant) {
        return const Result.err(PermissionFailure());
      }
      final city = merchantCities[merchantId];
      if (city != null && draft.cityId != city) {
        return const Result.err(ValidationFailure());
      }
    }

    final normCode = Coupon.normalizeCode(draft.code);

    // Unique code per city
    final hasDuplicate = _coupons.values.any(
      (c) =>
          c.cityId == draft.cityId && Coupon.normalizeCode(c.code) == normCode,
    );
    if (hasDuplicate) {
      return const Result.err(ConflictFailure());
    }

    final id = 'fake-coupon-${_coupons.length + 1}';
    final coupon = draft.copyWith(
      id: id,
      code: normCode,
      usedCount: 0,
      // The guard trigger stamps the creator for an owner and leaves an admin's write alone,
      // where the column defaults to null.
      createdByUid: isAdmin ? null : actingUid,
    );
    _coupons[id] = coupon;
    _notify();
    return Result.ok(coupon);
  }

  @override
  Future<Result<void>> update(Coupon coupon) async {
    if (failure != null) return Result.err(failure!);

    final existing = _coupons[coupon.id];
    // A row the policy hides updates nothing, and `guardWrite` reads that as not found.
    if (existing == null || !_visible(existing)) {
      return const Result.err(NotFoundFailure());
    }

    if (!_valid(coupon)) return const Result.err(ValidationFailure());

    if (!isAdmin &&
        (coupon.merchantId != merchantId ||
            coupon.fundedBy != CouponFunder.merchant)) {
      return const Result.err(PermissionFailure());
    }

    final normCode = Coupon.normalizeCode(coupon.code);

    // Unique code per city (excluding self)
    final hasDuplicate = _coupons.values.any(
      (c) =>
          c.id != coupon.id &&
          c.cityId == existing.cityId &&
          Coupon.normalizeCode(c.code) == normCode,
    );
    if (hasDuplicate) {
      return const Result.err(ConflictFailure());
    }

    // Update editable fields only
    final updated = existing.copyWith(
      code: normCode,
      type: coupon.type,
      value: coupon.value,
      maxDiscount: coupon.maxDiscount,
      minOrder: coupon.minOrder,
      firstOrderOnly: coupon.firstOrderOnly,
      perUserLimit: coupon.perUserLimit,
      totalLimit: coupon.totalLimit,
      validFrom: coupon.validFrom,
      validUntil: coupon.validUntil,
      isActive: coupon.isActive,
      fundedBy: isAdmin ? coupon.fundedBy : existing.fundedBy,
    );
    _coupons[coupon.id] = updated;
    _notify();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setActive(String id, bool active) async {
    if (failure != null) return Result.err(failure!);

    final existing = _coupons[id];
    if (existing == null || !_visible(existing)) {
      return const Result.err(NotFoundFailure());
    }

    _coupons[id] = existing.copyWith(isActive: active);
    _notify();
    return const Result.ok(null);
  }
}
