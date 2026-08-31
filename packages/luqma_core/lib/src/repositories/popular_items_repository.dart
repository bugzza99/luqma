import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/menu_item.dart';
import '../result.dart';

/// What the city orders, across every shop in it.
///
/// Its own repository rather than a method on [MenuRepository] because it answers a
/// different question: that one is "what is on this shop's menu", scoped to a merchant
/// and written to by that merchant. This one is read-only, city-wide, and computed from
/// orders — nothing a menu screen ever needs.
abstract interface class PopularItemsRepository {
  /// The city's most-ordered dishes, most first.
  ///
  /// Falls back to the best-rated available food when nothing has been delivered yet, so
  /// the shelf is full from the first customer. That fallback lives in the SQL rather
  /// than here: a screen that has to know when to ask a second question is a screen that
  /// forgets on the one day it matters.
  Future<Result<List<MenuItem>>> forCity(String cityId, {int limit});
}

class SupabasePopularItemsRepository implements PopularItemsRepository {
  SupabasePopularItemsRepository(this._db);

  final SupabaseClient _db;

  @override
  Future<Result<List<MenuItem>>> forCity(String cityId, {int limit = 12}) {
    return Result.guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'popular_items',
        params: {'p_city_id': cityId, 'p_limit': limit},
      );
      return [
        for (final row in rows)
          MenuItem.fromRow(Map<String, dynamic>.from(row as Map)),
      ];
    });
  }
}

/// In-memory, for the screens that draw the shelf.
class FakePopularItemsRepository implements PopularItemsRepository {
  FakePopularItemsRepository({List<MenuItem> items = const [], this.failure})
      : _items = List.of(items);

  final List<MenuItem> _items;
  final Failure? failure;

  @override
  Future<Result<List<MenuItem>>> forCity(String cityId, {int limit = 12}) async {
    if (failure != null) return Result.err(failure!);
    // The same ordering the function applies, so a screen cannot look right here and
    // wrong against Postgres: delivered count first, then the rating fallback.
    final sorted = [..._items]..sort((a, b) {
        final byCount = b.orderedCount.compareTo(a.orderedCount);
        if (byCount != 0) return byCount;
        return b.ratingAvg.compareTo(a.ratingAvg);
      });
    return Result.ok(sorted.take(limit).toList());
  }
}
