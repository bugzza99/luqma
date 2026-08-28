import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/menu_item.dart';
import '../models/merchant.dart';
import '../data/column_names.dart';
import '../result.dart';

/// What one search turned up.
///
/// Two lists rather than one mixed one, because they are answers to two different
/// questions — "which shop" and "who makes this" — and a screen that interleaves them
/// makes the customer sort them out by eye.
class SearchResults {
  const SearchResults({this.merchants = const [], this.dishes = const []});

  final List<Merchant> merchants;

  /// Dishes, each paired with the shop that makes it — a dish with no shop beside it is
  /// something the customer cannot act on.
  final List<({MenuItem item, Merchant merchant})> dishes;

  bool get isEmpty => merchants.isEmpty && dishes.isEmpty;
}

/// Searching the city.
///
/// This exists because there is no categories tab. `docs/04` settled that on the grounds
/// that Edku has thirty merchants and "search covers the rest" — and then the search box
/// shipped as a text field with `readOnly: true` and an empty `onTap`, so the thing the
/// whole decision leaned on did nothing at all.
///
/// Dishes as well as shops, because somebody typing into it is looking for food, not for
/// a building: "كشري" should find whoever makes it, not nothing.
///
/// Not daily meals. They expire in the evening, and a result that is gone in two hours is
/// worse than one that was never offered — they are at the top of the home instead.
abstract interface class SearchRepository {
  /// Matches [query] against merchant names and dish names.
  ///
  /// An empty or whitespace query returns nothing rather than everything: a list of the
  /// entire city is not a search result, it is the home screen.
  Future<Result<SearchResults>> search({
    required String cityId,
    required String query,
  });
}

class SupabaseSearchRepository implements SearchRepository {
  SupabaseSearchRepository(this._db);

  final SupabaseClient _db;

  /// Edku is thirty merchants and a few hundred dishes. `ilike` over that is instant and
  /// needs no extension, no index maintenance and no tokeniser that has to be taught
  /// Arabic — full-text search here would be machinery for a problem this city does not
  /// have.
  static const _limit = 30;

  @override
  Future<Result<SearchResults>> search({
    required String cityId,
    required String query,
  }) {
    return Result.guard(() async {
      final trimmed = query.trim();
      if (trimmed.isEmpty) return const SearchResults();

      // `%` and `_` are wildcards to ilike, so a customer typing one would silently
      // widen their own search.
      final pattern = '%${trimmed.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

      final merchantRows = await _db
          .from('merchants')
          .select()
          .eq('city_id', cityId)
          .eq('status', 'approved')
          .ilike('name', pattern)
          .limit(_limit);

      final merchants =
          merchantRows.map((r) => Merchant.fromJson(ColumnNames.toModel(r))).toList();

      // The dish carries its shop, so one query answers both halves — and a dish whose
      // shop is suspended or in another city never reaches the screen.
      final dishRows = await _db
          .from('menu_items')
          .select('*, merchants!inner(*)')
          .eq('merchants.city_id', cityId)
          .eq('merchants.status', 'approved')
          .eq('is_available', true)
          .ilike('name', pattern)
          .limit(_limit);

      final dishes = <({MenuItem item, Merchant merchant})>[];
      for (final row in dishRows) {
        final merchantRow = row['merchants'] as Map<String, dynamic>?;
        if (merchantRow == null) continue;

        final withoutJoin = Map<String, dynamic>.from(row)..remove('merchants');
        dishes.add((
          item: MenuItem.fromJson(ColumnNames.toModel(withoutJoin)),
          merchant: Merchant.fromJson(ColumnNames.toModel(merchantRow)),
        ));
      }

      return SearchResults(merchants: merchants, dishes: dishes);
    });
  }
}

/// In-memory search, for tests and for building the screen above it.
class FakeSearchRepository implements SearchRepository {
  FakeSearchRepository({
    this.merchants = const [],
    this.menus = const {},
    this.failure,
  });

  /// The shops this fake knows about. Public, like every other fake's contents, so a
  /// test can assert against what it was given.
  final List<Merchant> merchants;

  /// Menus by merchant id.
  final Map<String, List<MenuItem>> menus;
  final Failure? failure;

  /// Every query this fake was asked, for assertions about debouncing.
  final List<String> queries = [];

  @override
  Future<Result<SearchResults>> search({
    required String cityId,
    required String query,
  }) async {
    if (failure != null) return Result.err(failure!);

    queries.add(query);
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const Result.ok(SearchResults());

    final matched =
        merchants.where((m) => m.name.contains(trimmed)).toList();

    final dishes = <({MenuItem item, Merchant merchant})>[];
    for (final merchant in merchants) {
      for (final item in menus[merchant.id] ?? const <MenuItem>[]) {
        if (item.name.contains(trimmed)) {
          dishes.add((item: item, merchant: merchant));
        }
      }
    }

    return Result.ok(SearchResults(merchants: matched, dishes: dishes));
  }
}
