import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'harness.dart';

/// Searching the city, as a customer's phone does it.
///
/// `docs/04` removed the categories tab on the grounds that Edku has thirty merchants and
/// "search covers the rest" — so this is not a convenience, it is the only way to find a
/// shop by anything other than scrolling. It then shipped as a text field with
/// `readOnly: true` and an empty `onTap`, which is worth remembering: the thing an entire
/// design decision leaned on did nothing at all, and nothing failed.
///
/// The dish half runs `menu_items` joined to `merchants` with `!inner`, and a join is
/// exactly where the boundary bites: a rule that allows less than a query asks for does
/// not return less — it returns nothing. A fake cannot tell you that.
void main() {
  late LiveDatabase live;
  late String cityId, zoneId, openMerchantId;
  late SupabaseClient customer;
  late SearchRepository repository;

  setUpAll(() async => live = await LiveDatabase.open());
  tearDownAll(() => live.close());

  Future<String> shop({
    required String name,
    String status = 'approved',
    String? inCity,
  }) =>
      live.client.from('merchants').insert({
        'city_id': inCity ?? cityId,
        'type': 'restaurant',
        'name': name,
        'zone_id': zoneId,
        'phone': '01000000000',
        'status': status,
      }).select().single().then((row) => row['id'] as String);

  Future<void> dish({
    required String merchantId,
    required String name,
    bool available = true,
  }) async {
    await live.client.from('menu_items').insert({
      'merchant_id': merchantId,
      'name': name,
      'price': 9000,
      'is_available': available,
    });
  }

  setUp(() async {
    cityId = await live.makeCity();
    zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'المعمورة', 'default_delivery_fee': 1500})
        .select()
        .single()
        .then((row) => row['id'] as String);

    openMerchantId = await shop(name: 'كشري التحرير');

    (customer, _) = await live.openAsCustomer();
    repository = SupabaseSearchRepository(customer);
  });

  tearDown(() async {
    await customer.dispose();
    await live.dropCity(cityId);
  });

  Future<SearchResults> find(String query) async {
    final result = await repository.search(cityId: cityId, query: query);
    // Checked rather than `!`-ed: a helper that dereferences a null turns "the query was
    // refused, and here is why" into "Null check operator used on a null value".
    expect(result.failureOrNull, isNull, reason: 'the search itself was refused');
    return result.valueOrNull!;
  }

  test('a shop is found by its name', () async {
    final results = await find('كشري');
    expect(results.merchants.map((m) => m.id), contains(openMerchantId));
  });

  test('a dish is found, and it arrives with the shop that makes it', () async {
    await dish(merchantId: openMerchantId, name: 'كشري بالعدس');

    final results = await find('عدس');

    // The join is the whole risk here: `menu_items` inner-joined to `merchants`, read by
    // a signed-in customer through both tables' policies at once.
    expect(results.dishes, hasLength(1));
    expect(results.dishes.single.item.name, 'كشري بالعدس');
    expect(results.dishes.single.merchant.id, openMerchantId,
        reason: 'a dish with no shop beside it is something nobody can act on');
  });

  test('a suspended shop is in neither half', () async {
    final suspended = await shop(name: 'كشري مقفول', status: 'suspended');
    await dish(merchantId: suspended, name: 'كشري مقفول بالعدس');

    final results = await find('كشري');

    expect(results.merchants.map((m) => m.id), isNot(contains(suspended)));
    expect(results.dishes.map((d) => d.merchant.id), isNot(contains(suspended)),
        reason: 'a dish whose shop is shut is a tap that ends in nothing');
  });

  test('a dish the kitchen has run out of is not offered', () async {
    await dish(merchantId: openMerchantId, name: 'سمك خلصان', available: false);
    expect((await find('سمك')).dishes, isEmpty);
  });

  test('another city is another product', () async {
    final otherCity = await live.makeCity();
    addTearDown(() => live.dropCity(otherCity));
    final otherZone = await live.client
        .from('zones')
        .insert({'city_id': otherCity, 'name': 'منطقة', 'default_delivery_fee': 1500})
        .select()
        .single()
        .then((row) => row['id'] as String);
    final elsewhere = await live.client.from('merchants').insert({
      'city_id': otherCity,
      'type': 'restaurant',
      'name': 'كشري إسكندرية',
      'zone_id': otherZone,
      'phone': '01000000000',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);

    final results = await find('كشري');
    expect(results.merchants.map((m) => m.id), isNot(contains(elsewhere)));
  });

  test('an empty query is not a list of the whole city', () async {
    expect((await find('')).isEmpty, isTrue);
    expect((await find('    ')).isEmpty, isTrue,
        reason: 'the entire city is the home screen, not a search result');
  });

  test('a percent sign is a character somebody typed, not a wildcard', () async {
    await dish(merchantId: openMerchantId, name: 'خصم 50%');
    await dish(merchantId: openMerchantId, name: 'سمك مشوي');

    // Unescaped, `%` widens the pattern to everything and the customer silently gets the
    // whole menu back as though they had searched for nothing. Escaped, it matches the
    // one dish whose name really does contain the character — which is the honest answer
    // to what they typed.
    final results = await find('%');
    expect(results.dishes.map((d) => d.item.name), ['خصم 50%'],
        reason: 'a literal, so the other dish is not swept in with it');
    expect((await find('50%')).dishes, hasLength(1));
  });

  test('an underscore is not a wildcard either', () async {
    await dish(merchantId: openMerchantId, name: 'طبق_مميز');

    expect((await find('ق_م')).dishes, hasLength(1));
    expect((await find('ق_ز')).dishes, isEmpty,
        reason: '`_` matching any single character would make this match too');
  });

  test('somebody browsing before they sign in can search', () async {
    final anon = live.openAnonymously();
    addTearDown(anon.dispose);

    final results = await SupabaseSearchRepository(anon)
        .search(cityId: cityId, query: 'كشري');

    // The search box sits on the home screen, which a customer reaches before signing in.
    // If the policies only admit an authenticated reader, the first thing a new customer
    // does returns nothing.
    expect(results.failureOrNull, isNull);
    expect(results.valueOrNull!.merchants.map((m) => m.id), contains(openMerchantId));
  });
}
