import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// A merchant's menu, against a real Postgres.
///
/// There was no direct Firestore test for this repository — the editor above it carried
/// the coverage. Moving the menu onto its own tables earns it real ones: category sync
/// is a function with deletes in it now, and items live in a table the merchants
/// repository also reads through its embed.
void main() {
  late LiveDatabase live;
  late SupabaseMenuRepository repository;
  late String cityId;
  late String zoneId;
  late String merchantId;

  setUpAll(() async {
    live = await LiveDatabase.open();
    repository = SupabaseMenuRepository(live.client);
  });

  setUp(() async {
    cityId = await live.makeCity();
    zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'المعمورة'})
        .select()
        .single()
        .then((row) => row['id'] as String);
    merchantId = await live.client.from('merchants').insert({
      'city_id': cityId,
      'type': 'restaurant',
      'name': 'مطعم',
      'zone_id': zoneId,
      'phone': '01000000000',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);
  });

  tearDown(() => live.dropCity(cityId));
  tearDownAll(() => live.close());

  MenuItem item(String name, {int sortOrder = 0, String categoryId = ''}) =>
      MenuItem(
        id: '',
        merchantId: merchantId,
        categoryId: categoryId,
        name: name,
        price: 5000,
        sortOrder: sortOrder,
      );

  group('categories', () {
    test('a save creates, renames and removes in one call', () async {
      await repository.saveCategories(merchantId, const [
        MenuCategory(id: '', name: 'مشويات', sortOrder: 0),
        MenuCategory(id: '', name: 'أرز', sortOrder: 1),
      ]);

      final afterFirst = await repository.watchCategories(merchantId).first;
      expect(afterFirst.map((c) => c.name), ['مشويات', 'أرز']);
      expect(afterFirst.every((c) => c.id.isNotEmpty), isTrue);

      // One renamed, one gone, one added — the whole list lands together or not at all.
      await repository.saveCategories(merchantId, [
        afterFirst.first.copyWith(name: 'مشويات مشكّلة'),
        MenuCategory(id: '', name: 'حلويات', sortOrder: 2),
      ]);

      final afterSecond = await repository.watchCategories(merchantId).first;
      expect(afterSecond.map((c) => c.name), ['مشويات مشكّلة', 'حلويات']);
      expect(afterSecond, hasLength(2));
    });

    test('an empty save clears the list', () async {
      await repository.saveCategories(merchantId, const [
        MenuCategory(id: '', name: 'مشويات'),
      ]);
      expect(await repository.watchCategories(merchantId).first, hasLength(1));

      await repository.saveCategories(merchantId, const []);

      expect(await repository.watchCategories(merchantId).first, isEmpty);
    });

    // The categories belong to one merchant; another's menu must not see them.
    test('another merchant does not see them', () async {
      await repository.saveCategories(merchantId, const [
        MenuCategory(id: '', name: 'مشويات'),
      ]);
      final otherMerchant = await live.client.from('merchants').insert({
        'city_id': cityId,
        'type': 'restaurant',
        'name': 'مطعم تاني',
        'zone_id': zoneId,
        'phone': '01000000001',
        'status': 'approved',
      }).select().single().then((row) => row['id'] as String);

      final other = await repository.watchCategories(otherMerchant).first;

      expect(other, isEmpty);
    });
  });

  group('items', () {
    Future<String> addCategory(String name) async {
      await repository.saveCategories(merchantId, [
        ...(await repository.watchCategories(merchantId).first),
        MenuCategory(id: '', name: name, sortOrder: 99),
      ]);
      return (await repository.watchCategories(merchantId).first)
          .lastWhere((c) => c.name == name)
          .id;
    }

    test('a new item gets an id and comes back', () async {
      final saved = await repository.saveItem(item('كفتة'));

      expect(saved.valueOrNull?.id, isNotEmpty);
      expect(saved.valueOrNull?.price, 5000);
      expect(await repository.watchItems(merchantId).first, hasLength(1));
    });

    test('editing does not create a second one', () async {
      final created = (await repository.saveItem(item('كفتة'))).valueOrNull!;

      await repository.saveItem(created.copyWith(price: 6000));

      final items = await repository.watchItems(merchantId).first;
      expect(items, hasLength(1));
      expect(items.single.price, 6000);
    });

    // The column allows null where the model demands a string — an item can outlive
    // its category, and the read maps that to the model's "none".
    test('an item whose category is deleted reads back with none', () async {
      final categoryId = await addCategory('مشويات');
      await repository.saveItem(item('كفتة', categoryId: categoryId));

      await live.client.from('menu_categories').delete().eq('id', categoryId);

      final items = await repository.watchItems(merchantId).first;
      expect(items.single.categoryId, isEmpty);
    });

    test('options survive the round trip', () async {
      const options = [
        MenuOption(id: 'o1', name: 'كبير', price: 2000),
        MenuOption(id: 'o2', name: 'سوري', price: 0),
      ];
      (await repository.saveItem(
        item('كفتة').copyWith(options: options),
      )).valueOrNull!;

      final read = (await repository.watchItems(merchantId).first).single;
      expect(read.options.map((o) => o.name), ['كبير', 'سوري']);
      expect(read.options.first.price, 2000);
    });

    test('availability survives the round trip', () async {
      await repository.saveItem(
        item('كفتة').copyWith(isAvailable: false),
      );

      final read = (await repository.watchItems(merchantId).first).single;

      expect(read.isAvailable, isFalse);
    });

    test('deleting removes it', () async {
      final created = (await repository.saveItem(item('كفتة'))).valueOrNull!;

      await repository.deleteItem(created.id);

      expect(await repository.watchItems(merchantId).first, isEmpty);
    });
  });
}
