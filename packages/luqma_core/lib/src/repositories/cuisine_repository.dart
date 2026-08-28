import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cuisine.dart';
import '../result.dart';

/// The city's kinds of food, and which merchants are each one.
///
/// A small list that changes rarely, so it is fetched whole rather than queried per
/// screen — one cached list beats a fresh query on every home-screen open, on a
/// connection that is often a bar of 3G in a flat.
///
/// Reads are open to everybody, including a customer who has not signed in: this is the
/// top of the home screen and it draws before anyone has an account. Writes are the
/// admin's alone, and the policies say so rather than trusting this interface.
abstract interface class CuisineRepository {
  /// Every cuisine in the city, in the order the admin arranged them, each already
  /// carrying the URL of its approved picture.
  Future<Result<List<Cuisine>>> forCity(String cityId);

  /// The merchants tagged with [cuisineId] — the ids only, because the list of merchants
  /// itself comes from `MerchantRepository` and is already cached there.
  Future<Result<Set<String>>> merchantsIn(String cuisineId);

  /// Creates or replaces. An empty id means create.
  Future<Result<Cuisine>> save(Cuisine cuisine);

  Future<Result<void>> delete(String cuisineId);

  /// Replaces the whole set of cuisines a merchant belongs to.
  ///
  /// Whole rather than add/remove: the admin's editor shows every cuisine with a tick
  /// beside it, so what it knows is the final set. Two calls to add and remove would
  /// leave a half-applied state if the second one failed.
  Future<Result<void>> setMerchantCuisines(String merchantId, Set<String> cuisineIds);
}

class SupabaseCuisineRepository implements CuisineRepository {
  SupabaseCuisineRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<List<Cuisine>>> forCity(String cityId) {
    return Result.guard(() async {
      // The picture comes back with the row: a circle that fetched its own image would
      // be one request per cuisine, on the screen that has to be fastest.
      //
      // The join is filtered to approved on purpose. An image awaiting review must not
      // appear on the customer's home just because an admin attached it — that is the
      // whole point of the queue, and doing it here rather than in Dart means the row
      // arrives already correct.
      final rows = await _db
          .from('cuisines')
          .select('id, city_id, name, media_id, sort_order, media(url, status)')
          .eq('city_id', cityId)
          // `ascending: true`, spelled out: `order()` in this SDK defaults to
          // *descending*, so the bare call put the circles in the reverse of the order
          // the admin arranged them in — and the "الترتيب" field on the admin's screen
          // did the opposite of what it says. Every other ordered query in this package
          // passes the flag; this one did not, which is the whole story.
          .order('sort_order', ascending: true);

      return rows.map((row) {
        final media = row['media'] as Map<String, dynamic>?;
        final approved = media != null && media['status'] == 'approved';
        return Cuisine(
          id: row['id'] as String,
          cityId: row['city_id'] as String,
          name: row['name'] as String,
          mediaId: row['media_id'] as String?,
          imageUrl: approved ? media['url'] as String? : null,
          sortOrder: (row['sort_order'] as num?)?.toInt() ?? 0,
        );
      }).toList();
    });
  }

  @override
  Future<Result<Set<String>>> merchantsIn(String cuisineId) {
    return Result.guard(() async {
      final rows = await _db
          .from('merchant_cuisines')
          .select('merchant_id')
          .eq('cuisine_id', cuisineId);
      return rows.map((r) => r['merchant_id'] as String).toSet();
    });
  }

  @override
  Future<Result<Cuisine>> save(Cuisine cuisine) {
    return Result.guard(() async {
      final values = {
        'city_id': cuisine.cityId,
        'name': cuisine.name,
        // An empty id means "none" everywhere else in this codebase, and an empty string
        // is not a uuid — the column would refuse it before any policy had spoken.
        'media_id': (cuisine.mediaId?.isEmpty ?? true) ? null : cuisine.mediaId,
        'sort_order': cuisine.sortOrder,
      };

      final row = cuisine.id.isEmpty
          ? await _db.from('cuisines').insert(values).select().single()
          : await _db
              .from('cuisines')
              .update(values)
              .eq('id', cuisine.id)
              .select()
              .single();

      return cuisine.copyWith(id: row['id'] as String);
    });
  }

  @override
  Future<Result<void>> delete(String cuisineId) {
    return Result.guard(
      () => _db.from('cuisines').delete().eq('id', cuisineId),
    );
  }

  @override
  Future<Result<void>> setMerchantCuisines(
    String merchantId,
    Set<String> cuisineIds,
  ) {
    return Result.guard(() async {
      await _db.from('merchant_cuisines').delete().eq('merchant_id', merchantId);
      if (cuisineIds.isEmpty) return;

      await _db.from('merchant_cuisines').insert([
        for (final id in cuisineIds) {'merchant_id': merchantId, 'cuisine_id': id},
      ]);
    });
  }
}

/// In-memory cuisines, for tests and for building screens above it.
class FakeCuisineRepository implements CuisineRepository {
  FakeCuisineRepository({
    List<Cuisine> seed = const [],
    Map<String, Set<String>> members = const {},
    this.failure,
  })  : _cuisines = {for (final c in seed) c.id: c},
        _members = {for (final e in members.entries) e.key: {...e.value}};

  final Map<String, Cuisine> _cuisines;
  final Map<String, Set<String>> _members;
  /// Settable, like the courier and customer fakes: a test needs to make the connection
  /// drop *between* opening a sheet and tapping save, which is when a half-typed form is
  /// at stake.
  Failure? failure;

  var _counter = 0;

  /// Everything held right now, for assertions.
  List<Cuisine> get all => List.unmodifiable(_cuisines.values);

  @override
  Future<Result<List<Cuisine>>> forCity(String cityId) async {
    if (failure != null) return Result.err(failure!);
    final list = _cuisines.values.where((c) => c.cityId == cityId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Result.ok(list);
  }

  @override
  Future<Result<Set<String>>> merchantsIn(String cuisineId) async {
    if (failure != null) return Result.err(failure!);
    return Result.ok(_members[cuisineId] ?? const {});
  }

  @override
  Future<Result<Cuisine>> save(Cuisine cuisine) async {
    if (failure != null) return Result.err(failure!);
    final saved = cuisine.id.isEmpty
        ? cuisine.copyWith(id: 'fake-cuisine-${++_counter}')
        : cuisine;
    _cuisines[saved.id] = saved;
    return Result.ok(saved);
  }

  @override
  Future<Result<void>> delete(String cuisineId) async {
    if (failure != null) return Result.err(failure!);
    _cuisines.remove(cuisineId);
    for (final set in _members.values) {
      set.remove(cuisineId);
    }
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> setMerchantCuisines(
    String merchantId,
    Set<String> cuisineIds,
  ) async {
    if (failure != null) return Result.err(failure!);
    for (final entry in _members.entries) {
      entry.value.remove(merchantId);
    }
    for (final id in cuisineIds) {
      (_members[id] ??= {}).add(merchantId);
    }
    return const Result.ok(null);
  }
}
