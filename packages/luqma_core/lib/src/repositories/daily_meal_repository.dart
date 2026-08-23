import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

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

class FirestoreDailyMealRepository implements DailyMealRepository {
  FirestoreDailyMealRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _meals =>
      _firestore.collection('dailyMeals');

  @override
  Stream<List<DailyMeal>> watchToday({
    required String cityId,
    required String day,
  }) {
    return _meals
        .where('cityId', isEqualTo: cityId)
        .where('date', isEqualTo: day)
        .where('status', isEqualTo: DailyMealStatus.published.name)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_toMeal).toList()
          // What is still available first: a screen that leads with four sold-out cards
          // reads as a section not worth scrolling.
          ..sort((a, b) {
            if (a.isSoldOut != b.isSoldOut) return a.isSoldOut ? 1 : -1;
            return a.name.compareTo(b.name);
          }));
  }

  @override
  Stream<List<DailyMeal>> watchForMerchant(String merchantId) {
    return _meals
        .where('merchantId', isEqualTo: merchantId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_toMeal).toList()
          // Newest day first: a cook opens this to deal with today, not with last week.
          ..sort((a, b) => b.date.compareTo(a.date)));
  }

  @override
  Future<Result<DailyMeal>> saveMeal(DailyMeal meal) {
    return Result.guard(() async {
      final isNew = meal.id.isEmpty;
      final doc = isNew ? _meals.doc() : _meals.doc(meal.id);
      final saved = meal.copyWith(id: doc.id);

      final json = saved.toJson()..remove('id');
      if (!isNew) {
        // Stripped rather than refused, so editing a name never becomes an argument
        // about a field the caller did not mean to send. The security rules refuse the
        // same write; this is what stops the app offering it in the first place.
        json
          ..remove('remainingQty')
          ..remove('totalQty');
      }

      await doc.set(json, SetOptions(merge: true));
      return isNew ? saved : _toMeal(await doc.get());
    });
  }

  @override
  Future<Result<void>> setStatus(String mealId, DailyMealStatus status) {
    return Result.guard(
      () => _meals.doc(mealId).update({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  DailyMeal _toMeal(DocumentSnapshot<Map<String, dynamic>> doc) =>
      DailyMeal.fromJson({...doc.data()!, 'id': doc.id});
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
