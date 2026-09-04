import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
import '../models/daily_meal.dart';
import '../result.dart';

/// Today's home-cooked meals.
///
/// One rule shapes this whole interface: `remainingQty` belongs to the server. A kitchen
/// that could write it could sell the same portion twice, and two people tapping the last
/// one at the same moment is precisely what this collection exists to get right. So every
/// method here either creates a meal, edits everything *except* the count, or reads.
abstract interface class DailyMealRepository {
  /// What a customer sees: published, for this day, in this city. Live.
  ///
  /// Sold-out meals are included. A section that quietly drops a meal at eight o'clock
  /// makes the whole thing look like it was never there — and "خلص" is information: it
  /// is what teaches somebody to order earlier tomorrow.
  Stream<List<DailyMeal>> watchToday({required String cityId, required String day});

  /// What one kitchen sees of its own: drafts included. Live.
  Stream<List<DailyMeal>> watchForMerchant(String merchantId);

  /// Creates or edits. An empty [DailyMeal.id] means create.
  ///
  /// On an edit the quantities are left alone, whatever is passed. Deciding how much to
  /// cook happens once, when the meal is created; after that the count is a running
  /// total of what has been reserved.
  Future<Result<DailyMeal>> saveMeal(DailyMeal meal);

  /// Takes a meal down early, or puts it back. Never touches the count.
  Future<Result<void>> setStatus(String mealId, DailyMealStatus status);
}

class SupabaseDailyMealRepository implements DailyMealRepository {
  SupabaseDailyMealRepository(this._db);

  final SupabaseClient _db;

  /// An empty id means "none" everywhere else in this codebase, and an empty string is
  /// not a uuid — the column would refuse it before any policy had spoken.
  static String? _uuidOrNull(String? id) =>
      (id == null || id.isEmpty) ? null : id;

  @override
  Stream<List<DailyMeal>> watchToday({
    required String cityId,
    required String day,
  }) {
    return watchRows(
      db: _db,
      table: 'daily_meals',
      map: _toMeal,
      columns: _columns,
      filters: [
        RowFilter('city_id', cityId),
        RowFilter('date', day),
        RowFilter('status', DailyMealStatus.published.name),
      ],
      // What is still available first: a screen that leads with four sold-out cards
      // reads as a section not worth scrolling.
    ).map((meals) => meals..sort((a, b) {
        if (a.isSoldOut != b.isSoldOut) return a.isSoldOut ? 1 : -1;
        return a.name.compareTo(b.name);
      }));
  }

  @override
  Stream<List<DailyMeal>> watchForMerchant(String merchantId) {
    return watchRows(
      db: _db,
      table: 'daily_meals',
      map: _toMeal,
      columns: _columns,
      filters: [RowFilter('merchant_id', merchantId)],
      // Newest day first: a cook opens this to deal with today, not with last week.
      orderBy: 'date',
      ascending: false,
    );
  }

  @override
  Future<Result<DailyMeal>> saveMeal(DailyMeal meal) {
    // The count is decided once, at creation. An edit carries everything but it —
    // stripped rather than refused, so editing a name never becomes an argument about
    // a field the caller did not mean to send.
    final row = {
      'merchant_id': meal.merchantId,
      'city_id': meal.cityId,
      'name': meal.name,
      'description': meal.description,
      'media_id': _uuidOrNull(meal.mediaId),
      'price': meal.price,
      'date': meal.date,
      'pickup_window_start': meal.pickupWindowStart,
      'pickup_window_end': meal.pickupWindowEnd,
      'delivery_option': meal.deliveryOption.name,
      'status': meal.status.name,
      if (meal.id.isEmpty) ...{
        'total_qty': meal.totalQty,
        'remaining_qty': meal.remainingQty,
      },
    };
    if (meal.id.isEmpty) {
      return Result.guard(() async {
        final saved = await _db.from('daily_meals').insert(row).select().single();
        return _toMeal(saved);
      });
    }
    return Result.guardWrite(
      () => _db.from('daily_meals').update(row).eq('id', meal.id).select(),
      _toMeal,
    );
  }

  @override
  Future<Result<void>> setStatus(String mealId, DailyMealStatus status) {
    return Result.guardWrite(
      () => _db.from('daily_meals').update({
        'status': status.name,
      }).eq('id', mealId).select('id'),
      (_) {},
    );
  }

  /// The row plus the picture it points at. See `_toMeal` for why the status matters.
  static const _columns = '*, media(url, status)';

  DailyMeal _toMeal(Map<String, dynamic> row) {
    final media = row['media'] as Map<String, dynamic>?;
    final flat = Map<String, dynamic>.from(row)..remove('media');
    // Unapproved is the same as absent, everywhere in the product.
    if (media != null && media['status'] == 'approved') {
      flat['image_url'] = media['url'];
    }
    return DailyMeal.fromJson(ColumnNames.toModel(flat));
  }
}

/// In-memory meals, for tests and for building the screens before the backend exists.
class FakeDailyMealRepository implements DailyMealRepository {
  FakeDailyMealRepository({List<DailyMeal> seed = const [], this.failure})
      : _meals = {for (final m in seed) m.id: m};

  final Map<String, DailyMeal> _meals;
  final Failure? failure;

  final _changed = StreamController<void>.broadcast();

  /// Everything held right now. A widget test runs on a fake clock and cannot await one
  /// of the streams below.
  List<DailyMeal> get all => List.unmodifiable(_meals.values);

  DailyMeal? operator [](String id) => _meals[id];

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
  Stream<List<DailyMeal>> watchToday({
    required String cityId,
    required String day,
  }) {
    if (failure != null) return Stream.error(failure!);
    return _live(
      () => _meals.values
          .where((m) =>
              m.cityId == cityId &&
              m.date == day &&
              m.status == DailyMealStatus.published)
          .toList()
        ..sort((a, b) {
          if (a.isSoldOut != b.isSoldOut) return a.isSoldOut ? 1 : -1;
          return a.name.compareTo(b.name);
        }),
    );
  }

  @override
  Stream<List<DailyMeal>> watchForMerchant(String merchantId) {
    if (failure != null) return Stream.error(failure!);
    return _live(
      () => _meals.values.where((m) => m.merchantId == merchantId).toList()
        ..sort((a, b) => b.date.compareTo(a.date)),
    );
  }

  @override
  Future<Result<DailyMeal>> saveMeal(DailyMeal meal) async {
    if (failure != null) return Result.err(failure!);

    final isNew = meal.id.isEmpty;
    final saved = isNew ? meal.copyWith(id: 'meal-${_meals.length + 1}') : meal;

    // Same rule as the real one: the count is the server's after creation.
    final existing = _meals[saved.id];
    if (!isNew && existing == null) return const Result.err(NotFoundFailure());
    _meals[saved.id] = existing == null
        ? saved
        : saved.copyWith(
            remainingQty: existing.remainingQty,
            totalQty: existing.totalQty,
          );

    _notify();
    return Result.ok(_meals[saved.id]!);
  }

  @override
  Future<Result<void>> setStatus(String mealId, DailyMealStatus status) async {
    if (failure != null) return Result.err(failure!);

    final meal = _meals[mealId];
    if (meal == null) return const Result.err(NotFoundFailure());

    _meals[mealId] = meal.copyWith(status: status);
    _notify();
    return const Result.ok(null);
  }
}
