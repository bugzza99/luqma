import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// How many marketing pushes have gone out since [since]. The cap is enforced against
  /// this, and it counts what was *sent* rather than what was approved.
  Future<Result<int>> pushesSentSince({
    required String cityId,
    required DateTime since,
  });
}

class FirestorePromotionRepository implements PromotionRepository {
  FirestorePromotionRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _promotions =>
      _firestore.collection('promotions');

  @override
  Future<Result<Promotion>> request(Promotion promotion) {
    return Result.guard(() async {
      final doc = _promotions.doc();
      final asked = promotion.copyWith(
        id: doc.id,
        status: PromotionStatus.requested,
        approvedBy: null,
        rejectionReason: null,
      );

      await doc.set(asked.toJson()..remove('id'));
      return asked;
    });
  }

  @override
  Stream<List<Promotion>> watchQueue(String cityId) {
    return _promotions
        .where('cityId', isEqualTo: cityId)
        .where('status', isEqualTo: PromotionStatus.requested.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_toPromotion).toList()
          ..sort((a, b) => a.startAt.compareTo(b.startAt)));
  }

  @override
  Stream<List<Promotion>> watchLive({
    required String cityId,
    required DateTime now,
  }) {
    return _promotions
        .where('cityId', isEqualTo: cityId)
        .where('status', whereIn: [
          PromotionStatus.approved.name,
          PromotionStatus.active.name,
        ])
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(_toPromotion)
            // Filtered here rather than in the query: a date range plus an `in` on
            // status plus a city needs a composite index for a handful of documents.
            .where((p) => p.isLiveAt(now))
            .toList()
          // Whoever paid more for the slot gets it. Without an order a contested slot
          // shows whichever document Firestore happened to return first.
          ..sort((a, b) => b.priority.compareTo(a.priority)));
  }

  @override
  Stream<List<Promotion>> watchForMerchant(String merchantId) {
    return _promotions
        .where('merchantId', isEqualTo: merchantId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_toPromotion).toList()
          ..sort((a, b) => b.startAt.compareTo(a.startAt)));
  }

  @override
  Future<Result<void>> approve(String promotionId, {required String approvedBy}) {
    return Result.guard(
      () => _promotions.doc(promotionId).update({
        // Approved, not active. `startAt` decides when it runs — a campaign signed off
        // today for next week must not appear the moment somebody approved it.
        'status': PromotionStatus.approved.name,
        'approvedBy': approvedBy,
        'rejectionReason': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
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

      await _promotions.doc(promotionId).update({
        'status': PromotionStatus.rejected.name,
        'rejectionReason': trimmed,
        'approvedBy': by,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<Result<int>> pushesSentSince({
    required String cityId,
    required DateTime since,
  }) {
    return Result.guard(() async {
      final snapshot = await _promotions
          .where('cityId', isEqualTo: cityId)
          .where('channel', isEqualTo: PromotionChannel.push.name)
          .get();

      // Counted from what was *sent*, not what was approved. An approved campaign that
      // never went out has not spent anybody's attention.
      return snapshot.docs
          .map(_toPromotion)
          .where((p) =>
              p.status == PromotionStatus.ended && !p.startAt.isBefore(since))
          .length;
    });
  }

  Promotion _toPromotion(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Promotion.fromJson({...doc.data()!, 'id': doc.id});
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
  Future<Result<int>> pushesSentSince({
    required String cityId,
    required DateTime since,
  }) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(
      _promotions.values
          .where((p) =>
              p.cityId == cityId &&
              p.channel == PromotionChannel.push &&
              p.status == PromotionStatus.ended &&
              !p.startAt.isBefore(since))
          .length,
    );
  }
}
