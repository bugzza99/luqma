import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/menu_item.dart';
import '../models/merchant.dart';
import '../result.dart';

/// A merchant's menu: the categories that live inline on the merchant document, and the
/// items that live in their own collection.
abstract interface class MenuRepository {
  Stream<List<MenuCategory>> watchCategories(String merchantId);
  Stream<List<MenuItem>> watchItems(String merchantId);

  /// Creates or replaces an item. An empty [MenuItem.id] means create.
  Future<Result<MenuItem>> saveItem(MenuItem item);
  Future<Result<void>> deleteItem(String itemId);
  Future<Result<void>> saveCategories(String merchantId, List<MenuCategory> categories);
}

class FirestoreMenuRepository implements MenuRepository {
  FirestoreMenuRepository(this._firestore);

  final FirebaseFirestore _firestore;

  @override
  Stream<List<MenuCategory>> watchCategories(String merchantId) {
    return _firestore.collection('merchants').doc(merchantId).snapshots().map((doc) {
      final raw = (doc.data()?['menuCategories'] as List?) ?? const [];
      return raw
          .map((e) => MenuCategory.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    });
  }

  @override
  Stream<List<MenuItem>> watchItems(String merchantId) {
    return _firestore
        .collection('menuItems')
        .where('merchantId', isEqualTo: merchantId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => MenuItem.fromJson({...doc.data(), 'id': doc.id}))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));
  }

  @override
  Future<Result<MenuItem>> saveItem(MenuItem item) {
    return Result.guard(() async {
      final items = _firestore.collection('menuItems');
      final doc = item.id.isEmpty ? items.doc() : items.doc(item.id);
      final saved = item.copyWith(id: doc.id);
      await doc.set(saved.toJson()..remove('id'), SetOptions(merge: true));
      return saved;
    });
  }

  @override
  Future<Result<void>> deleteItem(String itemId) {
    return Result.guard(() => _firestore.collection('menuItems').doc(itemId).delete());
  }

  @override
  Future<Result<void>> saveCategories(String merchantId, List<MenuCategory> categories) {
    return Result.guard(() async {
      await _firestore.collection('merchants').doc(merchantId).update({
        'menuCategories': categories.map((c) => c.toJson()).toList(),
      });
    });
  }
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
