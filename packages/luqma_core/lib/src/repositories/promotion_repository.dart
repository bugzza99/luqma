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

  /// The admin puts up a placement themselves, already approved.
  ///
  /// The other half of `request`, and the one that was missing: AdminApp could approve
  /// and reject what merchants asked for and could not put up a banner of its own, so
  /// the owner had no way to announce anything — free delivery today, a new kitchen —
  /// without signing into a merchant account to ask themselves for it first.
  ///
  /// Approved on arrival because the admin *is* the approval. Whether it is on screen is
  /// still `startAt`/`endAt`'s question, not this one — a banner made today for next week
  /// must not appear the moment it is saved.
  Future<Result<Promotion>> createApproved(
    Promotion promotion, {
    required String approvedBy,
  });

  /// A merchant corrects a placement they asked for, before it starts.
  ///
  /// Lands back as `requested` whatever the document claims — an edit is a fresh ask, so
  /// a merchant cannot approve their own words by changing something already signed off.
  /// The policy refuses anything else, and refuses the edit entirely once the banner has
  /// started: a live campaign taken dark to fix a typo is a worse answer than the typo.
  Future<Result<Promotion>> editRequest(Promotion promotion);

  /// Moves when a placement appears and disappears. The admin's, and only theirs.
  Future<Result<void>> reschedule(
    String promotionId, {
    required DateTime startAt,
    required DateTime endAt,
  });

  /// What is waiting for a decision. Live.
  Stream<List<Promotion>> watchQueue(String cityId);

  /// Every placement in the city, whatever became of it. Live.
  ///
  /// The queue is what needs a decision; this is what exists. An approved banner left
  /// the admin's screen the moment it was approved, so nobody could see a scheduled one
  /// or move its dates.
  Stream<List<Promotion>> watchAll(String cityId);

  /// What should be on screen right now, best placement first. Live.
  Stream<List<Promotion>> watchLive({required String cityId, required DateTime now});

  /// Everything one merchant asked for, whatever became of it. Live.
  Stream<List<Promotion>> watchForMerchant(String merchantId);

  /// Signs a request off.
  ///
  /// [startAt] and [endAt] move the window when given. The merchant's form asks for a
  /// week from now, and the admin is the one who knows when the slot is actually free —
  /// the original code said "the admin moves it when they approve" and gave them no way
  /// to, so a banner requested for a future date could only ever be approved into that
  /// future date and the owner watched nothing happen.
  Future<Result<void>> approve(
    String promotionId, {
    required String approvedBy,
    DateTime? startAt,
    DateTime? endAt,
  });

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

  /// The server computes this because the client cannot read the recipient rows, and
  /// should not: an audit needs totals, not a list of customers who received an offer.
  Future<Result<PromotionPushReport>> pushReport(String promotionId);
}

class SupabasePromotionRepository implements PromotionRepository {
  SupabasePromotionRepository(this._db);

  final SupabaseClient _db;

  /// An empty id means "none" everywhere else in this codebase, and an empty string is
  /// not a uuid — the column would refuse it before any policy had spoken.
  static String? _uuidOrNull(String? id) =>
      (id == null || id.isEmpty) ? null : id;

  /// Everything on the row, plus the picture the banner is supposed to draw.
  ///
  /// The embed is the whole reason the column can be rendered: `media_id` is a uuid and
  /// a uuid draws nothing. Without this the ad slot fell back to its gradient for every
  /// banner in the city, which looks like a design choice rather than a missing picture.
  static const _columns = '*, media(url, status)';

  Promotion _toPromotion(Map<String, dynamic> row) {
    final media = row['media'] as Map<String, dynamic>?;
    final row2 = Map<String, dynamic>.from(row)..remove('media');
    // Unapproved is the same as absent. `read_media` already hides another merchant's
    // pending row, but an admin reading this list can see their own — and the moderation
    // queue is worth nothing if the picture is on screen before it is reviewed.
    if (media != null && media['status'] == 'approved') {
      row2['image_url'] = media['url'];
    }
    final model = ColumnNames.toModel(row2)
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
        'background_color': asked.backgroundColor,
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
  Future<Result<Promotion>> createApproved(
    Promotion promotion, {
    required String approvedBy,
  }) {
    return Result.guard(() async {
      // Approved on arrival: the admin writing it *is* the approval, and a queue entry
      // waiting for the person who just made it is a step that means nothing. The
      // `admin_promotions` policy is what allows the status — `merchant_requests_promotion`
      // permits `requested` and nothing else, so this write is refused outright for
      // anybody who is not an admin.
      final ready = promotion.copyWith(
        status: PromotionStatus.approved,
        approvedBy: approvedBy,
        rejectionReason: null,
      );
      final saved = await _db.from('promotions').insert({
        'city_id': ready.cityId,
        'merchant_id': ready.merchantId,
        'channel': ready.channel.name,
        'render_mode': ready.renderMode.name,
        'background_color': ready.backgroundColor,
        'title': ready.title,
        'body': ready.body,
        'media_id': _uuidOrNull(ready.mediaId),
        'section_key': ready.sectionKey,
        'category_id': _uuidOrNull(ready.categoryId),
        'zone_ids': ready.zoneIds,
        'start_at': ready.startAt.toUtc().toIso8601String(),
        'end_at': ready.endAt.toUtc().toIso8601String(),
        'priority': ready.priority,
        'price': ready.price,
        'requested_by': ready.requestedBy,
        'status': ready.status.name,
        'approved_by': approvedBy,
      }).select().single();
      return _toPromotion(saved);
    });
  }

  @override
  Future<Result<Promotion>> editRequest(Promotion promotion) {
    return Result.guard(() async {
      // Forced back to `requested`, exactly as `request` forces it on the way in. The
      // policy refuses any other status from a merchant, so writing what it will refuse
      // would only turn a clear rule into an error somebody has to read.
      final asked = promotion.copyWith(
        status: PromotionStatus.requested,
        approvedBy: null,
        rejectionReason: null,
      );
      final saved = await _db
          .from('promotions')
          .update({
            'channel': asked.channel.name,
            'render_mode': asked.renderMode.name,
            'background_color': asked.backgroundColor,
            'title': asked.title,
            'body': asked.body,
            'media_id': _uuidOrNull(asked.mediaId),
            'status': asked.status.name,
            'approved_by': null,
            'rejection_reason': null,
          })
          .eq('id', asked.id)
          .select()
          .single();
      return _toPromotion(saved);
    });
  }

  @override
  Future<Result<void>> reschedule(
    String promotionId, {
    required DateTime startAt,
    required DateTime endAt,
  }) {
    return Result.guard(
      () => _db.from('promotions').update({
        'start_at': startAt.toUtc().toIso8601String(),
        'end_at': endAt.toUtc().toIso8601String(),
      }).eq('id', promotionId),
    );
  }

  @override
  Stream<List<Promotion>> watchQueue(String cityId) {
    return watchRows(
      db: _db,
      table: 'promotions',
      columns: _columns,
      map: _toPromotion,
      filters: [
        RowFilter('city_id', cityId),
        RowFilter('status', PromotionStatus.requested.name),
      ],
      orderBy: 'start_at',
    );
  }

  @override
  Stream<List<Promotion>> watchAll(String cityId) {
    return watchRows(
      db: _db,
      table: 'promotions',
      columns: _columns,
      map: _toPromotion,
      filters: [RowFilter('city_id', cityId)],
    ).map((promotions) => promotions
      // Soonest first: what is running now, then what is about to, then what is done.
      ..sort((a, b) => b.startAt.compareTo(a.startAt)));
  }

  @override
  Stream<List<Promotion>> watchLive({
    required String cityId,
    required DateTime now,
  }) {
    return watchRows(
      db: _db,
      table: 'promotions',
      columns: _columns,
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
      columns: _columns,
      map: _toPromotion,
      filters: [RowFilter('merchant_id', merchantId)],
    ).map((promotions) => promotions..sort((a, b) => b.startAt.compareTo(a.startAt)));
  }

  @override
  Future<Result<void>> approve(
    String promotionId, {
    required String approvedBy,
    DateTime? startAt,
    DateTime? endAt,
  }) {
    return Result.guard(
      () => _db.from('promotions').update({
        // Approved, not active. `startAt` decides when it runs — a campaign signed off
        // today for next week must not appear the moment somebody approved it. What is
        // new is that the admin can *set* that date rather than only inherit it.
        'status': PromotionStatus.approved.name,
        'approved_by': _uuidOrNull(approvedBy),
        'rejection_reason': null,
        if (startAt != null) 'start_at': startAt.toUtc().toIso8601String(),
        if (endAt != null) 'end_at': endAt.toUtc().toIso8601String(),
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

  @override
  Future<Result<PromotionPushReport>> pushReport(String promotionId) {
    return Result.guard(() async {
      final row = await _db.rpc('promotion_push_report', params: {
        'p_promotion_id': promotionId,
      });
      return PromotionPushReport.fromJson(
        Map<String, dynamic>.from(row as Map),
      );
    });
  }
}

/// In-memory promotions, for tests and for the screens above them.
class FakePromotionRepository implements PromotionRepository {
  FakePromotionRepository({
    List<Promotion> seed = const [],
    Map<String, PromotionPushReport> pushReports = const {},
    this.failure,
    this.isAdmin = true,
    DateTime Function()? clock,
  })  : _promotions = {for (final p in seed) p.id: p},
        _pushReports = Map.unmodifiable(pushReports),
        _clock = clock ?? DateTime.now;

  final Map<String, Promotion> _promotions;
  final Map<String, PromotionPushReport> _pushReports;
  final Failure? failure;
  final bool isAdmin;

  /// The hour [pushSlotAvailable] answers against.
  ///
  /// Injectable because the push cap is a question about a seven-day window, and a fake
  /// reading the wall clock makes every test of it depend on the day it is run. That is
  /// not theoretical: the merchant's cap test pinned its own `now` to a fixed date and
  /// seeded a campaign two days before it, and passed for five days — until the real
  /// clock moved past the window and the same fixture started reading as "nothing sent
  /// this week". The test failed for a reason that had nothing to do with the code.
  final DateTime Function() _clock;

  final _changed = StreamController<void>.broadcast();

  /// Fails the *next* write only, then clears itself.
  ///
  /// Separate from [failure], which fails everything including the reads a screen needs
  /// to draw at all: a form whose list never loaded cannot be filled in, so a refusal on
  /// submit can only be tested by letting the screen load first.
  Failure? failNext;

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
  Future<Result<Promotion>> createApproved(
    Promotion promotion, {
    required String approvedBy,
  }) async {
    if (failure != null) return Result.err(failure!);
    if (failNext != null) {
      final refusal = failNext!;
      failNext = null;
      return Result.err(refusal);
    }

    final ready = promotion.copyWith(
      id: 'promo-${_promotions.length + 1}',
      status: PromotionStatus.approved,
      approvedBy: approvedBy,
      rejectionReason: null,
    );
    _promotions[ready.id] = ready;
    _notify();
    return Result.ok(ready);
  }

  @override
  Future<Result<Promotion>> editRequest(Promotion promotion) async {
    if (failure != null) return Result.err(failure!);
    if (failNext != null) {
      final refusal = failNext!;
      failNext = null;
      return Result.err(refusal);
    }

    final existing = _promotions[promotion.id];
    if (existing == null) return const Result.err(NotFoundFailure());

    // The same two rules the policy enforces, so a screen cannot pass against the fake
    // and be refused by the database: only before it starts, and always back to the
    // queue.
    if (!existing.startAt.isAfter(_clock())) {
      return const Result.err(PermissionFailure());
    }

    final asked = promotion.copyWith(
      status: PromotionStatus.requested,
      approvedBy: null,
      rejectionReason: null,
    );
    _promotions[asked.id] = asked;
    _notify();
    return Result.ok(asked);
  }

  @override
  Future<Result<void>> reschedule(
    String promotionId, {
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    if (failure != null) return Result.err(failure!);

    final existing = _promotions[promotionId];
    if (existing == null) return const Result.err(NotFoundFailure());

    _promotions[promotionId] = existing.copyWith(startAt: startAt, endAt: endAt);
    _notify();
    return const Result.ok(null);
  }

  @override
  Stream<List<Promotion>> watchAll(String cityId) {
    if (failure != null) return Stream.error(failure!);
    return _live(
      () => _promotions.values.where((p) => p.cityId == cityId).toList()
        ..sort((a, b) => b.startAt.compareTo(a.startAt)),
    );
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
  Future<Result<void>> approve(
    String promotionId, {
    required String approvedBy,
    DateTime? startAt,
    DateTime? endAt,
  }) async {
    if (failure != null) return Result.err(failure!);

    final promotion = _promotions[promotionId];
    if (promotion == null) return const Result.err(NotFoundFailure());

    _promotions[promotionId] = promotion.copyWith(
      status: PromotionStatus.approved,
      approvedBy: approvedBy,
      rejectionReason: null,
      startAt: startAt ?? promotion.startAt,
      endAt: endAt ?? promotion.endAt,
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
    final now = _clock();
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

  @override
  Future<Result<PromotionPushReport>> pushReport(String promotionId) async {
    if (failure != null) return Result.err(failure!);
    // The real RPC is granted to the signed-in role and then asks `is_admin()` itself.
    // Mirroring the second gate matters: otherwise a non-admin screen can pass every
    // test against this fake and meet a 42501 only after it ships.
    if (!isAdmin) return const Result.err(PermissionFailure());
    return Result.ok(_pushReports[promotionId] ?? const PromotionPushReport());
  }
}
