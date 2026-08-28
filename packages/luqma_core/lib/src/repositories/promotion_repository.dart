import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
import '../models/promotion.dart';
import '../result.dart';

/// Paid placements: asking for one, approving it, and finding what is live.
///
/// A merchant may ask; only an admin may approve. That single asymmetry is the whole
/// design — letting a merchant publish their own push is the fastest way to make
/// customers disable notifications, and the operational channel goes with it.
abstract interface class PromotionRepository {
  /// A merchant asks for a placement. Always lands as `requested`, whatever the
  /// document claims — the rules refuse anything else, and this is what stops the app
  /// offering a write that is about to be rejected.
  Future<Result<Promotion>> request(Promotion promotion);

  /// What is waiting for a decision. Live.
  Stream<List<Promotion>> watchQueue(String cityId);

  /// What should be on screen right now, best placement first. Live.
  Stream<List<Promotion>> watchLive({required String cityId, required DateTime now});

  /// Everything one merchant asked for, whatever became of it. Live.
  Stream<List<Promotion>> watchForMerchant(String merchantId);

  Future<Result<void>> approve(String promotionId, {required String approvedBy});

  /// Refuses it. The reason is required: without one the merchant has nothing to fix
  /// and will ask again with the same thing.
  Future<Result<void>> reject(
    String promotionId, {
    required String reason,
    required String by,
  });

  /// Whether the city still has a marketing push left this week.
  ///
  /// Asked of the server, not counted here: a merchant's RLS sees only their own rows,
  /// so a client-side count would understate every merchant but the caller and the cap
  /// would never bite. The cap is on the city — what is being rationed is a customer's
  /// patience — and it counts what was *sent*, not what was approved.
  Future<Result<bool>> pushSlotAvailable({
    required String cityId,
    required int limit,
  });
}

class SupabasePromotionRepository implements PromotionRepository {
  SupabasePromotionRepository(this._db);

  final SupabaseClient _db;

  /// An empty id means "none" everywhere else in this codebase, and an empty string is
  /// not a uuid — the column would refuse it before any policy had spoken.
  static String? _uuidOrNull(String? id) =>
      (id == null || id.isEmpty) ? null : id;

  Promotion _toPromotion(Map<String, dynamic> row) {
    final model = ColumnNames.toModel(row)
      ..update('zoneIds', (zones) => [for (final z in zones as List) z],
          ifAbsent: () => <String>[]);
    // Local, like Firestore's Timestamp.toDate() handed back: `isLiveAt` compares
    // against the device's clock.
    for (final key in ['startAt', 'endAt']) {
      if (model[key] is String) {
        model[key] = DateTime.parse(model[key] as String).toLocal();
      }
    }
    return Promotion.fromJson(model);
  }

  @override
  Future<Result<Promotion>> request(Promotion promotion) {
    return Result.guard(() async {
      // A merchant may ask; only an admin may approve. The status is forced here and
      // the policy refuses anything else — this is what stops the app offering a write
      // that is about to be rejected.
      final asked = promotion.copyWith(
        status: PromotionStatus.requested,
        approvedBy: null,
        rejectionReason: null,
      );
      final saved = await _db.from('promotions').insert({
        'city_id': asked.cityId,
        'merchant_id': asked.merchantId,
        'channel': asked.channel.name,
        'render_mode': asked.renderMode.name,
        'title': asked.title,
        'body': asked.body,
        'media_id': _uuidOrNull(asked.mediaId),
        'section_key': asked.sectionKey,
        'category_id': _uuidOrNull(asked.categoryId),
        'zone_ids': asked.zoneIds,
        'start_at': asked.startAt.toUtc().toIso8601String(),
        'end_at': asked.endAt.toUtc().toIso8601String(),
        'priority': asked.priority,
        'price': asked.price,
        'requested_by': asked.requestedBy,
        'status': asked.status.name,
      }).select().single();
      return _toPromotion(saved);
    });
  }

  @override
  Stream<List<Promotion>> watchQueue(String cityId) {
    return watchRows(
      db: _db,
      table: 'promotions',
      map: _toPromotion,
      filters: [
        RowFilter('city_id', cityId),
        RowFilter('status', PromotionStatus.requested.name),
      ],
      orderBy: 'start_at',
    );
  }

  @override
  Stream<List<Promotion>> watchLive({
    required String cityId,
    required DateTime now,
  }) {
    return watchRows(
      db: _db,
      table: 'promotions',
      map: _toPromotion,
      filters: [RowFilter('city_id', cityId)],
      // Live-ness is a date range plus a status pair — filtered here rather than in the
      // query, because a handful of documents does not buy an OR clause its complexity.
    ).map((promotions) => promotions
        .where((p) => p.isLiveAt(now))
        .toList()
      // Whoever paid more for the slot gets it. Without an order a contested slot
      // shows whichever row happened to come back first.
      ..sort((a, b) => b.priority.compareTo(a.priority)));
  }

  @override
  Stream<List<Promotion>> watchForMerchant(String merchantId) {
    return watchRows(
      db: _db,
      table: 'promotions',
      map: _toPromotion,
      filters: [RowFilter('merchant_id', merchantId)],
    ).map((promotions) => promotions..sort((a, b) => b.startAt.compareTo(a.startAt)));
  }

  @override
  Future<Result<void>> approve(String promotionId, {required String approvedBy}) {
    return Result.guard(
      () => _db.from('promotions').update({
        // Approved, not active. `startAt` decides when it runs — a campaign signed off
        // today for next week must not appear the moment somebody approved it.
        'status': PromotionStatus.approved.name,
        'approved_by': _uuidOrNull(approvedBy),
        'rejection_reason': null,
      }).eq('id', promotionId),
    );
  }

  @override
  Future<Result<void>> reject(
    String promotionId, {
    required String reason,
    required String by,
  }) {
    return Result.guard(() async {
      final trimmed = reason.trim();
      if (trimmed.isEmpty) throw const ConflictFailure();

      await _db.from('promotions').update({
        'status': PromotionStatus.rejected.name,
        'rejection_reason': trimmed,
        'approved_by': _uuidOrNull(by),
      }).eq('id', promotionId);
    });
  }

  @override
  Future<Result<bool>> pushSlotAvailable({
    required String cityId,
    required int limit,
  }) {
    return Result.guard(() async {
      // The server counts the whole city, which is the one thing a merchant-scoped
      // client cannot do for itself — its RLS sees only its own rows.
      return await _db.rpc('push_slot_available', params: {
        'p_city_id': cityId,
        'p_limit': limit,
      }) as bool;
    });
  }
}

/// In-memory promotions, for tests and for the screens above them.
class FakePromotionRepository implements PromotionRepository {
  FakePromotionRepository({List<Promotion> seed = const [], this.failure})
      : _promotions = {for (final p in seed) p.id: p};

  final Map<String, Promotion> _promotions;
  final Failure? failure;

  final _changed = StreamController<void>.broadcast();

  /// Everything held right now. A widget test runs on a fake clock and cannot await one
  /// of the streams below.
  List<Promotion> get all => List.unmodifiable(_promotions.values);

  Promotion? operator [](String id) => _promotions[id];

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
  Future<Result<Promotion>> request(Promotion promotion) async {
    if (failure != null) return Result.err(failure!);

    final asked = promotion.copyWith(
      id: 'promo-${_promotions.length + 1}',
      status: PromotionStatus.requested,
      approvedBy: null,
      rejectionReason: null,
    );
    _promotions[asked.id] = asked;
    _notify();
    return Result.ok(asked);
  }

  @override
  Stream<List<Promotion>> watchQueue(String cityId) {
    if (failure != null) return Stream.error(failure!);
    return _live(
      () => _promotions.values
          .where((p) =>
              p.cityId == cityId && p.status == PromotionStatus.requested)
          .toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt)),
    );
  }

  @override
  Stream<List<Promotion>> watchLive({
    required String cityId,
    required DateTime now,
  }) {
    if (failure != null) return Stream.error(failure!);
    return _live(
      () => _promotions.values
          .where((p) => p.cityId == cityId && p.isLiveAt(now))
          .toList()
        ..sort((a, b) => b.priority.compareTo(a.priority)),
    );
  }

  @override
  Stream<List<Promotion>> watchForMerchant(String merchantId) {
    if (failure != null) return Stream.error(failure!);
    return _live(
      () => _promotions.values.where((p) => p.merchantId == merchantId).toList()
        ..sort((a, b) => b.startAt.compareTo(a.startAt)),
    );
  }

  @override
  Future<Result<void>> approve(String promotionId, {required String approvedBy}) async {
    if (failure != null) return Result.err(failure!);

    final promotion = _promotions[promotionId];
    if (promotion == null) return const Result.err(NotFoundFailure());

    _promotions[promotionId] = promotion.copyWith(
      status: PromotionStatus.approved,
      approvedBy: approvedBy,
      rejectionReason: null,
    );
    _notify();
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> reject(
    String promotionId, {
    required String reason,
    required String by,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (reason.trim().isEmpty) return const Result.err(ConflictFailure());

    final promotion = _promotions[promotionId];
    if (promotion == null) return const Result.err(NotFoundFailure());

    _promotions[promotionId] = promotion.copyWith(
      status: PromotionStatus.rejected,
      rejectionReason: reason.trim(),
      approvedBy: by,
    );
    _notify();
    return const Result.ok(null);
  }

  @override
  Future<Result<bool>> pushSlotAvailable({
    required String cityId,
    required int limit,
  }) async {
    if (failure != null) return Result.err(failure!);
    // Mirrors the server: sent means ended, or approved and already started, within the
    // last seven days. An approved campaign that has not begun has not spent attention.
    final now = DateTime.now();
    final since = now.subtract(const Duration(days: 7));
    final sent = _promotions.values
        .where((p) =>
            p.cityId == cityId &&
            p.channel == PromotionChannel.push &&
            !p.startAt.isBefore(since) &&
            (p.status == PromotionStatus.ended ||
                (p.status == PromotionStatus.approved &&
                    !p.startAt.isAfter(now))))
        .length;
    return Result.ok(sent < limit);
  }
}
