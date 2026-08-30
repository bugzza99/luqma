import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
import '../models/merchant.dart';
import '../result.dart';

/// Reading and writing merchants.
///
/// An interface rather than direct backend calls, for one reason that shapes the whole
/// project: it lets the screens above be built and tested without a database, an
/// emulator or a network. Tests that need a running backend get written once and then
/// stop getting written.
abstract interface class MerchantRepository {
  /// Merchants a customer may see: approved, in this city. Live — the list updates
  /// itself when the admin approves or suspends someone.
  Stream<List<Merchant>> watchMerchants({required String cityId});

  Future<Result<Merchant>> getMerchant(String id);

  /// Pauses order intake until [until], or clears the pause when null.
  Future<Result<void>> setPausedUntil(String id, DateTime? until);

  /// Every merchant in the city, whatever their status.
  ///
  /// For AdminApp only. The ones waiting for approval are the reason that screen exists,
  /// and hiding suspended ones would remove the only place they could be reinstated.
  /// Sorted so anything needing a decision is at the top.
  Stream<List<Merchant>> watchAllMerchants({required String cityId});

  /// Creates or replaces. An empty id means create.
  Future<Result<Merchant>> saveMerchant(Merchant merchant);

  Future<Result<void>> setStatus(String id, MerchantStatus status);

  /// Removes a merchant that has never traded.
  ///
  /// The database owns the rule — `orders.merchant_id` is `on delete restrict`, so a
  /// merchant with orders is refused by the foreign key and this returns a conflict.
  /// A merchant added by mistake, before its first order, still deletes cleanly. The
  /// screen offers delete only while the count is zero; the constraint is what makes
  /// that promise keepable rather than remembered.
  Future<Result<void>> deleteMerchant(String id);

  /// How many orders a merchant has taken. The real query, never a denormalized count
  /// that could drift — the screen uses it to offer delete only to a merchant with none.
  Future<Result<int>> orderCount(String merchantId);
}

/// Pending first, then approved, then suspended.
int _byAttentionThenName(Merchant a, Merchant b) {
  const order = {
    MerchantStatus.pending: 0,
    MerchantStatus.approved: 1,
    MerchantStatus.suspended: 2,
  };
  final byStatus = order[a.status]!.compareTo(order[b.status]!);
  return byStatus != 0 ? byStatus : a.name.compareTo(b.name);
}

class SupabaseMerchantRepository implements MerchantRepository {
  SupabaseMerchantRepository(this._db);

  final SupabaseClient _db;

  /// Categories and served zones hang off their own tables, so they ride along on reads
  /// as embedded rows rather than being queried per screen.
  ///
  /// The two pictures ride along the same way, as *aliased* embeds. Two foreign keys
  /// point at the same table, so PostgREST needs the column named on each —
  /// `logo:logo_media_id(…)` — or it cannot tell which relationship is meant and refuses
  /// the query outright.
  ///
  /// `status` comes with the URL because the address alone is not permission to show it:
  /// a picture waiting for the moderation queue has a perfectly good URL, and the whole
  /// point of the queue is that it stays unseen until an admin says otherwise.
  static const _readColumns =
      '*, menu_categories(*), merchant_served_zones(zone_id), '
      'logo:logo_media_id(url, status), cover:cover_media_id(url, status)';

  /// An empty id means "none" everywhere else in this codebase, and an empty string is
  /// not a uuid — the column would refuse it before any policy had spoken.
  static String? _uuidOrNull(String? id) =>
      (id == null || id.isEmpty) ? null : id;

  /// The columns a save carries.
  ///
  /// Written out rather than derived from the model's JSON, because three kinds of field
  /// must never reach this statement:
  ///
  /// - **The server's money**: `wallet_balance`, `commission_owed`. A form built from a
  ///   stale load would quietly zero a wallet the server has been moving all day. In
  ///   Firestore the merged set had the same hazard; here it is answered instead of
  ///   survived.
  /// - **The customers' verdict**: `rating_avg`, `rating_count`. Same argument, less money.
  /// - **Fields with a life of their own**: served zones and menu categories live in
  ///   their own tables and move through their own paths, so a merchant edit neither
  ///   reads nor rewrites them.
  Map<String, dynamic> _row(Merchant m) => {
        'city_id': m.cityId,
        'type': m.type.name,
        'name': m.name,
        'zone_id': m.zoneId,
        'phone': m.phone,
        'status': m.status.name,
        // jsonb whose inner keys the app itself wrote, already camelCase.
        'opening_hours': [for (final w in m.openingHours) w.toJson()],
        // UTC, spelled: Dart writes local times without a zone suffix, and timestamptz
        // would read that as its own zone — the pause would come back an instant other
        // than the one the merchant set.
        'paused_until': m.pausedUntil?.toUtc().toIso8601String(),
        'logo_media_id': _uuidOrNull(m.logoMediaId),
        'cover_media_id': _uuidOrNull(m.coverMediaId),
        'delivers_self': m.deliversSelf,
        'owner_uid': _uuidOrNull(m.ownerUid),
        'plan_id': m.planId,
        'revenue_model': m.revenueModel.name,
        'revenue_value': m.revenueValue,
        'delivery_fee_override': m.deliveryFeeOverride,
        'min_order': m.minOrder,
        // Omitted until 2026-08-29, and the customer read the consequence: every
        // merchant card in the city says "٣٠ دقيقة تقريباً" because the column keeps its
        // default and nothing has ever been able to write another number to it. The
        // column is in the merchant's own writable list — see the guard in
        // `20260827010000_images_and_cuisines.sql` — so this was a gap, not a boundary.
        'prep_minutes': m.prepMinutes,
      };

  /// The address of an embedded picture, but only once somebody has approved it.
  ///
  /// Null for all three of "never uploaded", "still in the queue" and "refused" — a
  /// customer cannot act on the difference, and every one of them means the card draws
  /// the tinted mark from the shop's name instead.
  static String? _approvedUrl(Object? embedded) {
    final media = embedded as Map<String, dynamic>?;
    if (media == null || media['status'] != 'approved') return null;
    return media['url'] as String?;
  }

  Merchant _toMerchant(Map<String, dynamic> row) {
    final base = ColumnNames.toModel(row)
      ..remove('menu_categories')
      ..remove('merchant_served_zones')
      ..remove('logo')
      ..remove('cover');
    // Local, like Firestore's Timestamp.toDate() handed back: screens compare this
    // against clockProvider's local now, and Dart's DateTime equality insists on the
    // same zone, not merely the same moment.
    if (base['pausedUntil'] is String) {
      base['pausedUntil'] = DateTime.parse(base['pausedUntil'] as String).toLocal();
    }
    return Merchant.fromJson({
      ...base,
      'menuCategories': [
        for (final raw in (row['menu_categories'] as List? ?? const []))
          ColumnNames.toModel(Map<String, dynamic>.from(raw as Map)),
      ],
      'servedZones': [
        for (final raw in (row['merchant_served_zones'] as List? ?? const []))
          (raw as Map)['zone_id'],
      ],
      'logoUrl': _approvedUrl(row['logo']),
      'coverUrl': _approvedUrl(row['cover']),
    });
  }

  @override
  Stream<List<Merchant>> watchMerchants({required String cityId}) {
    return watchRows(
      db: _db,
      table: 'merchants',
      map: _toMerchant,
      // The embedded pictures, or the watched list carries no photograph at all.
      columns: _readColumns,
      filters: [
        RowFilter('city_id', cityId),
        RowFilter('status', MerchantStatus.approved.name),
      ],
      orderBy: 'created_at',
    );
  }

  @override
  Future<Result<Merchant>> getMerchant(String id) {
    return Result.guard(() async {
      final row = await _db
          .from('merchants')
          .select(_readColumns)
          .eq('id', id)
          .maybeSingle();
      if (row == null) throw const NotFoundFailure();
      return _toMerchant(row);
    });
  }

  @override
  Future<Result<void>> setPausedUntil(String id, DateTime? until) {
    return Result.guard(
      () => _db.from('merchants').update({
        'paused_until': until?.toUtc().toIso8601String(),
      }).eq('id', id),
    );
  }

  @override
  Stream<List<Merchant>> watchAllMerchants({required String cityId}) {
    return watchRows(
      db: _db,
      table: 'merchants',
      map: _toMerchant,
      // The embedded pictures, or the watched list carries no photograph at all.
      columns: _readColumns,
      filters: [RowFilter('city_id', cityId)],
      orderBy: 'created_at',
      // Sorted in Dart: the attention order is a policy about people, not an index.
    ).map((merchants) => merchants..sort(_byAttentionThenName));
  }

  @override
  Future<Result<Merchant>> saveMerchant(Merchant merchant) {
    return Result.guard(() async {
      final saved = merchant.id.isEmpty
          ? await _db
              .from('merchants')
              .insert(_row(merchant))
              .select(_readColumns)
              .single()
          : await _db
              .from('merchants')
              .update(_row(merchant))
              .eq('id', merchant.id)
              .select(_readColumns)
              .single();
      return _toMerchant(saved);
    });
  }

  @override
  Future<Result<void>> setStatus(String id, MerchantStatus status) {
    return Result.guard(
      () => _db.from('merchants').update({
        'status': status.name,
      }).eq('id', id),
    );
  }

  @override
  Future<Result<void>> deleteMerchant(String id) {
    return Result.guard(
      () => _db.from('merchants').delete().eq('id', id),
    );
  }

  @override
  Future<Result<int>> orderCount(String merchantId) {
    return Result.guard(() async {
      final rows = await _db
          .from('orders')
          .select('id')
          .eq('merchant_id', merchantId);
      return rows.length;
    });
  }
}

/// An in-memory merchant repository for tests and for building screens before the
/// backend exists.
///
/// It re-applies the same visibility rules as the Firestore query rather than returning
/// whatever it was given: a fake that is more permissive than production hides exactly
/// the bugs it was meant to catch.
class FakeMerchantRepository implements MerchantRepository {
  FakeMerchantRepository({
    List<Merchant> seed = const [],
    Map<String, int> orderCounts = const {},
    this.failure,
    this.saveFailure,
  })  : _merchants = {for (final m in seed) m.id: m},
        _orderCounts = Map.of(orderCounts);

  final Map<String, Merchant> _merchants;

  /// Everything held right now. A widget test runs on a fake clock and cannot await one
  /// of the streams below, so a screen that *writes* a merchant is checked through this.
  List<Merchant> get all => List.unmodifiable(_merchants.values);

  /// Orders already taken, per merchant id — the thing the real delete is refused by.
  final Map<String, int> _orderCounts;

  /// When set, every call fails with this — so the offline and permission paths can be
  /// exercised without unplugging anything.
  final Failure? failure;

  /// Fails only the *writes*. A screen that loads fine and then cannot save is a
  /// different situation from one that never loaded, and it is the one where an
  /// ignored `Result` shows the person something that did not happen.
  final Failure? saveFailure;

  @override
  Stream<List<Merchant>> watchMerchants({required String cityId}) {
    if (failure != null) return Stream.error(failure!);
    return Stream.value(
      _merchants.values
          .where((m) => m.cityId == cityId && m.status == MerchantStatus.approved)
          .toList(),
    );
  }

  @override
  Future<Result<Merchant>> getMerchant(String id) async {
    if (failure != null) return Result.err(failure!);
    final merchant = _merchants[id];
    if (merchant == null) return const Result.err(NotFoundFailure());
    return Result.ok(merchant);
  }

  @override
  Future<Result<void>> setPausedUntil(String id, DateTime? until) async {
    if (failure != null) return Result.err(failure!);
    final merchant = _merchants[id];
    if (merchant == null) return const Result.err(NotFoundFailure());
    _merchants[id] = merchant.copyWith(pausedUntil: until);
    return const Result.ok(null);
  }

  @override
  Stream<List<Merchant>> watchAllMerchants({required String cityId}) {
    if (failure != null) return Stream.error(failure!);
    return Stream.value(
      _merchants.values.where((m) => m.cityId == cityId).toList()
        ..sort(_byAttentionThenName),
    );
  }

  @override
  Future<Result<Merchant>> saveMerchant(Merchant merchant) async {
    if (failure != null) return Result.err(failure!);
    if (saveFailure != null) return Result.err(saveFailure!);
    final saved = merchant.id.isEmpty
        ? merchant.copyWith(id: 'merchant-${_merchants.length + 1}')
        : merchant;
    _merchants[saved.id] = saved;
    return Result.ok(saved);
  }

  @override
  Future<Result<void>> setStatus(String id, MerchantStatus status) async {
    if (failure != null) return Result.err(failure!);
    final merchant = _merchants[id];
    if (merchant == null) return const Result.err(NotFoundFailure());
    _merchants[id] = merchant.copyWith(status: status);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> deleteMerchant(String id) async {
    if (failure != null) return Result.err(failure!);
    if (!_merchants.containsKey(id)) return const Result.err(NotFoundFailure());
    if ((_orderCounts[id] ?? 0) > 0) {
      return const Result.err(ConflictFailure());
    }
    _merchants.remove(id);
    return const Result.ok(null);
  }

  @override
  Future<Result<int>> orderCount(String merchantId) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(_orderCounts[merchantId] ?? 0);
  }
}
