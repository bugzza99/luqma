import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../test/repository_contract_test.dart' show repositoryContract;
import 'harness.dart';

/// The same write contract the fakes are held to, against real Postgres.
///
/// This is the half that matters. CLAUDE.md is blunt about why: the fakes are more
/// permissive than Postgres plus the policies, so a green suite over them proves the
/// screens work against the fake and nothing more. The expectations live in
/// `test/repository_contract_test.dart` and are imported rather than restated, because
/// two copies of "what a write means" is exactly how the fake and the server drift.
///
/// What each contract asserts is one sentence: a write against something that is there
/// succeeds and changes it, and the same write against something that is **not** there
/// comes back `NotFoundFailure` rather than a cheerful `ok`. On this side "not there"
/// covers the case the fakes cannot have — a row that exists but which this token's
/// policy hides — and that is the failure the whole rule was written for.
void main() {
  late LiveDatabase live;
  late SupabaseClient admin;
  late String cityId, zoneId, merchantId;
  late String categoryId;

  setUpAll(() async {
    live = await LiveDatabase.open();
    admin = await live.openAsAdmin();
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
      'name': 'مطعم العقد',
      'zone_id': zoneId,
      'phone': '01000000000',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);
  });

  tearDown(() async {
    await live.client.from('menu_items').delete().eq('merchant_id', merchantId);
    await live.client.from('menu_categories').delete().eq('merchant_id', merchantId);
    await live.client.from('cuisines').delete().eq('city_id', cityId);
    await live.client.from('landmarks').delete().eq('city_id', cityId);
    await live.client.from('merchants').delete().eq('id', merchantId);
    await live.dropCity(cityId);
  });

  // A uuid that is syntactically valid and belongs to nothing. A malformed id would be
  // refused by Postgres for the wrong reason and prove nothing about the rule.
  const missing = '00000000-0000-4000-8000-000000000000';

  /// The merchant's one category, created for real and read back for its id.
  ///
  /// `menu_categories.id` is a uuid the database generates, so a made-up 'cat-1' is not
  /// a category that does not exist — it is not a uuid at all, and the item insert would
  /// fail for a reason that has nothing to do with the rule under test.
  Future<String> aCategory(MenuRepository repository) async {
    await repository.saveCategories(merchantId, [
      const MenuCategory(id: '', name: 'الرئيسي'),
    ]);
    return (await repository.watchCategories(merchantId).first).single.id;
  }

  repositoryContract<CuisineRepository>(
    name: 'live SupabaseCuisineRepository.save edit',
    repository: () async => SupabaseCuisineRepository(admin),
    writeExisting: (repository) async {
      final saved = (await repository.save(
        Cuisine(id: '', cityId: cityId, name: 'سمك'),
      )).valueOrNull!;
      return (await repository.save(saved.copyWith(name: 'مشويات'))).failureOrNull;
    },
    changed: (repository) async =>
        (await repository.forCity(cityId)).valueOrNull!.single.name == 'مشويات',
    writeMissing: (repository) async => (await repository.save(
      const Cuisine(id: missing, cityId: 'edku', name: 'حاجة مش موجودة'),
    )).failureOrNull,
  );

  repositoryContract<CuisineRepository>(
    name: 'live SupabaseCuisineRepository.delete',
    repository: () async => SupabaseCuisineRepository(admin),
    writeExisting: (repository) async {
      final saved = (await repository.save(
        Cuisine(id: '', cityId: cityId, name: 'مشويات'),
      )).valueOrNull!;
      return (await repository.delete(saved.id)).failureOrNull;
    },
    changed: (repository) async =>
        (await repository.forCity(cityId)).valueOrNull!.isEmpty,
    writeMissing: (repository) async =>
        (await repository.delete(missing)).failureOrNull,
  );

  repositoryContract<GeographyRepository>(
    name: 'live SupabaseGeographyRepository.saveLandmark edit',
    repository: () async => SupabaseGeographyRepository(admin),
    writeExisting: (repository) async {
      final saved = (await repository.saveLandmark(
        Landmark(id: '', cityId: cityId, zoneId: zoneId, name: 'المسجد'),
      )).valueOrNull!;
      return (await repository.saveLandmark(saved.copyWith(name: 'المدرسة')))
          .failureOrNull;
    },
    changed: (repository) async =>
        (await repository.landmarks(cityId: cityId)).valueOrNull!.single.name ==
        'المدرسة',
    writeMissing: (repository) async => (await repository.saveLandmark(
      Landmark(id: missing, cityId: cityId, zoneId: zoneId, name: 'مكان مش موجود'),
    )).failureOrNull,
  );

  repositoryContract<MerchantRepository>(
    name: 'live SupabaseMerchantRepository.setStatus',
    repository: () async => SupabaseMerchantRepository(admin),
    writeExisting: (repository) async =>
        (await repository.setStatus(merchantId, MerchantStatus.suspended))
            .failureOrNull,
    changed: (repository) async =>
        (await repository.getMerchant(merchantId)).valueOrNull!.status ==
        MerchantStatus.suspended,
    writeMissing: (repository) async =>
        (await repository.setStatus(missing, MerchantStatus.suspended))
            .failureOrNull,
  );

  repositoryContract<MenuRepository>(
    name: 'live SupabaseMenuRepository.saveItem edit',
    repository: () async => SupabaseMenuRepository(admin),
    writeExisting: (repository) async {
      categoryId = await aCategory(repository);
      final saved = (await repository.saveItem(
        MenuItem(
          id: '',
          merchantId: merchantId,
          categoryId: categoryId,
          name: 'كشري',
          price: 1500,
        ),
      )).valueOrNull!;
      return (await repository.saveItem(saved.copyWith(price: 2000))).failureOrNull;
    },
    // Items are a live stream rather than a one-shot read — the merchant's menu screen
    // watches them — so the check waits for the first emission after the write.
    changed: (repository) async =>
        (await repository.watchItems(merchantId).first).single.price == 2000,
    writeMissing: (repository) async => (await repository.saveItem(
      MenuItem(
        id: missing,
        merchantId: merchantId,
        categoryId: categoryId,
        name: 'صنف وهمي',
        price: 1000,
      ),
    )).failureOrNull,
  );
}
