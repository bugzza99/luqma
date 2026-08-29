import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'harness.dart';

/// الأقسام — the circles across the top of the customer's home.
///
/// Admin-only writes, and the reason is commercial rather than tidy: a merchant who
/// could put itself into a circle it does not belong in would have the cheapest
/// promotion in the product, right next to the ones other merchants are paying for.
///
/// Reads are public, because the circles are the first thing a customer sees and they
/// see it before signing in.
void main() {
  late LiveDatabase live;
  late String cityId, zoneId, merchantId;
  late SupabaseClient admin;
  late CuisineRepository repository;

  setUpAll(() async {
    live = await LiveDatabase.open();
    admin = await live.openAsAdmin();
    repository = SupabaseCuisineRepository(admin);
  });

  tearDownAll(() async {
    await admin.dispose();
    await live.close();
  });

  setUp(() async {
    cityId = await live.makeCity();
    zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'منطقة', 'default_delivery_fee': 1500})
        .select()
        .single()
        .then((row) => row['id'] as String);
    merchantId = await live.client.from('merchants').insert({
      'city_id': cityId,
      'type': 'restaurant',
      'name': 'مطعم البحر',
      'zone_id': zoneId,
      'phone': '01000000000',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);
  });

  tearDown(() async {
    await live.client.from('merchant_cuisines').delete().eq('merchant_id', merchantId);
    await live.client.from('cuisines').delete().eq('city_id', cityId);
    await live.dropCity(cityId);
  });

  Cuisine draft({String name = 'مشويات', int sortOrder = 0}) =>
      Cuisine(id: '', cityId: cityId, name: name, sortOrder: sortOrder);

  test('an admin creates one and it comes back with an id', () async {
    final saved = (await repository.save(draft())).valueOrNull!;

    expect(saved.id, isNotEmpty);
    expect(saved.name, 'مشويات');

    final listed = (await repository.forCity(cityId)).valueOrNull!;
    expect(listed.map((c) => c.id), contains(saved.id));
  });

  test('saving an existing one edits rather than making a second', () async {
    final saved = (await repository.save(draft(name: 'مشويات'))).valueOrNull!;
    await repository.save(saved.copyWith(name: 'مشويات وفراخ'));

    final listed = (await repository.forCity(cityId)).valueOrNull!;
    expect(listed.where((c) => c.id == saved.id).single.name, 'مشويات وفراخ');
    expect(listed, hasLength(1));
  });

  test('the circles come back in the order the admin arranged them', () async {
    final second = (await repository.save(draft(name: 'كشري', sortOrder: 2))).valueOrNull!;
    final first = (await repository.save(draft(name: 'مشويات', sortOrder: 1))).valueOrNull!;

    final listed = (await repository.forCity(cityId)).valueOrNull!;
    expect(listed.map((c) => c.id).toList(), [first.id, second.id],
        reason: 'the order is the admin\'s decision about what the city sees first');
  });

  test('another city has its own circles', () async {
    await repository.save(draft(name: 'مشويات'));

    final otherCity = await live.makeCity();
    addTearDown(() => live.dropCity(otherCity));

    expect((await repository.forCity(otherCity)).valueOrNull, isEmpty);
  });

  test('a customer who has not signed in still sees the circles', () async {
    final saved = (await repository.save(draft(name: 'مشويات'))).valueOrNull!;

    final anon = live.openAnonymously();
    addTearDown(anon.dispose);

    final result = await SupabaseCuisineRepository(anon).forCity(cityId);

    // They are the first thing on the home screen, and the home screen is reachable
    // before there is an account.
    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull!.map((c) => c.id), contains(saved.id));
  });

  test('a merchant owner cannot invent a cuisine', () async {
    final (ownerDb, _) = await live.openAsStaff(
        scope: 'merchant', role: 'owner', merchantId: merchantId);
    addTearDown(ownerDb.dispose);

    await SupabaseCuisineRepository(ownerDb).save(draft(name: 'أفخم مطاعم إدكو'));

    expect((await repository.forCity(cityId)).valueOrNull, isEmpty,
        reason: 'a circle a merchant wrote for itself is an advertisement nobody sold');
  });

  test('nor put itself into one somebody else made', () async {
    final saved = (await repository.save(draft(name: 'مشويات'))).valueOrNull!;

    final (ownerDb, _) = await live.openAsStaff(
        scope: 'merchant', role: 'owner', merchantId: merchantId);
    addTearDown(ownerDb.dispose);

    await SupabaseCuisineRepository(ownerDb)
        .setMerchantCuisines(merchantId, {saved.id});

    expect((await repository.merchantsIn(saved.id)).valueOrNull, isEmpty,
        reason: 'this is the cheapest promotion in the product if it is allowed');
  });

  test('an admin files a merchant under a cuisine, and can take it back out',
      () async {
    final saved = (await repository.save(draft(name: 'مشويات'))).valueOrNull!;

    expect((await repository.setMerchantCuisines(merchantId, {saved.id})).failureOrNull,
        isNull);
    expect((await repository.merchantsIn(saved.id)).valueOrNull, {merchantId});

    expect((await repository.setMerchantCuisines(merchantId, {})).failureOrNull, isNull);
    expect((await repository.merchantsIn(saved.id)).valueOrNull, isEmpty,
        reason: 'filing is reversible, or a mistake is permanent');
  });

  test('deleting a cuisine takes its filings with it, not the merchants', () async {
    final saved = (await repository.save(draft(name: 'مشويات'))).valueOrNull!;
    await repository.setMerchantCuisines(merchantId, {saved.id});

    expect((await repository.delete(saved.id)).failureOrNull, isNull);

    expect((await repository.forCity(cityId)).valueOrNull, isEmpty);
    final merchant = await live.client
        .from('merchants')
        .select('id')
        .eq('id', merchantId)
        .maybeSingle();
    expect(merchant, isNotNull,
        reason: 'removing a circle from the home screen must not close a shop');
  });
}
