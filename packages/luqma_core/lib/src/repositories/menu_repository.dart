import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/column_names.dart';
import '../data/live_query.dart';
import '../models/menu_item.dart';
import '../models/merchant.dart';
import '../result.dart';

/// A merchant's menu: the categories that order it, and the items that sell from it.
abstract interface class MenuRepository {
  Stream<List<MenuCategory>> watchCategories(String merchantId);
  Stream<List<MenuItem>> watchItems(String merchantId);

  /// Creates or replaces an item. An empty [MenuItem.id] means create.
  Future<Result<MenuItem>> saveItem(MenuItem item);
  Future<Result<void>> deleteItem(String itemId);
  Future<Result<void>> saveCategories(String merchantId, List<MenuCategory> categories);
}

class SupabaseMenuRepository implements MenuRepository {
  SupabaseMenuRepository(this._db);

  final SupabaseClient _db;

  /// An empty id means "none" everywhere else in this codebase, and an empty string is
  /// not a uuid — the column would refuse it before any policy had spoken.
  static String? _uuidOrNull(String? id) =>
      (id == null || id.isEmpty) ? null : id;

  @override
  Stream<List<MenuCategory>> watchCategories(String merchantId) {
    return watchRows(
      db: _db,
      table: 'menu_categories',
      map: (row) => MenuCategory.fromJson(ColumnNames.toModel(row)),
      filters: [RowFilter('merchant_id', merchantId)],
      orderBy: 'sort_order',
    );
  }

  @override
  Stream<List<MenuItem>> watchItems(String merchantId) {
    return watchRows(
      db: _db,
      table: 'menu_items',
      map: _toItem,
      // The picture, resolved. `watchRows` selects `*` unless told otherwise, so without
      // this every dish on every menu draws the tinted placeholder however many
      // photographs the owner has taken and approved.
      columns: '*, media(url, status)',
      filters: [RowFilter('merchant_id', merchantId)],
      orderBy: 'sort_order',
    );
  }

  @override
  Future<Result<MenuItem>> saveItem(MenuItem item) {
    final row = {
      'merchant_id': item.merchantId,
      // An item can outlive its category: the column allows null, the model carries
      // an empty string for it.
      'category_id': _uuidOrNull(item.categoryId),
      'name': item.name,
      'description': item.description,
      'price': item.price,
      'media_id': _uuidOrNull(item.mediaId),
      'is_available': item.isAvailable,
      // jsonb whose inner keys the app itself wrote, already camelCase.
      'options': [for (final o in item.options) o.toJson()],
      'sort_order': item.sortOrder,
    };
    if (item.id.isEmpty) {
      return Result.guard(() async {
        final saved = await _db.from('menu_items').insert(row).select().single();
        return _toItem(saved);
      });
    }
    return Result.guardWrite(
      () => _db.from('menu_items').update(row).eq('id', item.id).select(),
      _toItem,
    );
  }

  @override
  Future<Result<void>> deleteItem(String itemId) {
    return Result.guardWrite(
      () => _db.from('menu_items').delete().eq('id', itemId).select('id'),
      (_) {},
    );
  }

  @override
  Future<Result<void>> saveCategories(
    String merchantId,
    List<MenuCategory> categories,
  ) {
    return Result.guard(
      () => _db.rpc('save_menu_categories', params: {
        'p_merchant_id': merchantId,
        'p_categories': [
          for (final c in categories)
            {'id': c.id, 'name': c.name, 'sort_order': c.sortOrder},
        ],
      }),
    );
  }
}

MenuItem _toItem(Map<String, dynamic> row) {
  final media = row['media'] as Map<String, dynamic>?;
  final flat = Map<String, dynamic>.from(row)..remove('media');
  // Unapproved is the same as absent: the moderation queue is worth nothing if the
  // photograph is on a menu before anybody has looked at it.
  if (media != null && media['status'] == 'approved') {
    flat['image_url'] = media['url'];
  }
  return MenuItem.fromRow(flat);
}

/// In-memory menu, for tests and for entering data before the backend exists.
class FakeMenuRepository implements MenuRepository {
  FakeMenuRepository({
    List<MenuCategory> categories = const [],
    List<MenuItem> items = const [],
    this.failure,
  })  : _categories = List.of(categories),
        _items = List.of(items);

  final List<MenuCategory> _categories;
  final List<MenuItem> _items;
  final Failure? failure;

  /// Every item written through this repository, in order. Lets a test assert on what the
  /// editor produced rather than on what it displayed.
  final List<MenuItem> saved = [];

  @override
  Stream<List<MenuCategory>> watchCategories(String merchantId) =>
      failure != null ? Stream.error(failure!) : Stream.value(List.of(_categories));

  @override
  Stream<List<MenuItem>> watchItems(String merchantId) => failure != null
      ? Stream.error(failure!)
      : Stream.value(_items.where((i) => i.merchantId == merchantId).toList());

  @override
  Future<Result<MenuItem>> saveItem(MenuItem item) async {
    if (failure != null) return Result.err(failure!);
    if (item.id.isNotEmpty && !_items.any((existing) => existing.id == item.id)) {
      return const Result.err(NotFoundFailure());
    }
    final stored = item.id.isEmpty
        ? item.copyWith(id: 'generated-${saved.length + 1}')
        : item;
    saved.add(stored);
    _items
      ..removeWhere((i) => i.id == stored.id)
      ..add(stored);
    return Result.ok(stored);
  }

  @override
  Future<Result<void>> deleteItem(String itemId) async {
    if (failure != null) return Result.err(failure!);
    if (!_items.any((item) => item.id == itemId)) {
      return const Result.err(NotFoundFailure());
    }
    _items.removeWhere((i) => i.id == itemId);
    return const Result.ok(null);
  }

  @override
  Future<Result<void>> saveCategories(String merchantId, List<MenuCategory> categories) async {
    if (failure != null) return Result.err(failure!);
    _categories
      ..clear()
      ..addAll(categories);
    return const Result.ok(null);
  }
}
