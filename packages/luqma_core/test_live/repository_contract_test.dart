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
  // E8. The contracts above run through an admin's token, and the fakes answer the same
  // questions for a shop and a courier. Here the shop's owner and a platform courier ask
  // them of the real policies, and the "missing" target is the one the fakes cannot
  // have: an order that exists, belonging to another shop or carried by another rider,
  // which this token's policy hides. That must come back NotFoundFailure, never `ok`.
  group('through the people who run the orders', () {
    late String otherMerchantId;

    /// An order at [status], written as the server writes one.
    Future<String> anOrder(String merchant, OrderStatus status,
            {String deliveryBy = 'merchant', String? courier}) =>
        live.client.from('orders').insert({
          'city_id': cityId,
          'customer_name': 'عميل',
          'customer_phone': '01000000000',
          'merchant_id': merchant,
          'merchant_name': 'مطعم',
          'zone_id': zoneId,
          'address': {'id': 'a1', 'zoneId': zoneId, 'label': 'البيت'},
          'delivery_by': deliveryBy,
          'type': 'instant',
          'items': [],
          'pricing': {'subtotal': 1000, 'deliveryFee': 0, 'total': 1000},
          'revenue': {'model': 'commission', 'value': 0},
          'status': status.name,
          'accept_deadline_at':
              DateTime.now().add(const Duration(minutes: 30)).toUtc().toIso8601String(),
          'courier_uid': ?courier,
        }).select('id').single().then((row) => row['id'] as String);

    Future<OrderStatus> statusOf(String id) => live.client
        .from('orders')
        .select('status')
        .eq('id', id)
        .single()
        .then((row) => OrderStatus.values.byName(row['status'] as String));

    // The outer teardown deletes the shop before the city, and these tests leave orders
    // — delivered ones with settlements that are `on delete restrict` — behind it.
    tearDown(() async {
      final orders = await live.client.from('orders').select('id').eq('city_id', cityId);
      final ids = [for (final o in orders) o['id'] as String];
      if (ids.isEmpty) return;
      await live.client.from('courier_settlements').delete().inFilter('order_id', ids);
      await live.client.from('order_settlements').delete().inFilter('order_id', ids);
      await live.client.from('orders').delete().inFilter('id', ids);
    });

    setUp(() async {
      otherMerchantId = await live.client.from('merchants').insert({
        'city_id': cityId,
        'type': 'restaurant',
        'name': 'مطعم تاني',
        'zone_id': zoneId,
        'phone': '01000000001',
        'status': 'approved',
      }).select().single().then((row) => row['id'] as String);
    });

    Future<SupabaseMerchantOrderRepository> asOwner() async {
      final (db, _) =
          await live.openAsStaff(scope: 'merchant', role: 'owner', merchantId: merchantId);
      addTearDown(db.dispose);
      return SupabaseMerchantOrderRepository(db);
    }

    late String mine;
    repositoryContract<SupabaseMerchantOrderRepository>(
      name: "live owner accept, and another shop's order is not theirs",
      repository: asOwner,
      writeExisting: (repository) async {
        mine = await anOrder(merchantId, OrderStatus.placed);
        return (await repository.accept(mine, prepMinutes: 20)).failureOrNull;
      },
      changed: (_) async => await statusOf(mine) == OrderStatus.accepted,
      writeMissing: (repository) async {
        final theirs = await anOrder(otherMerchantId, OrderStatus.placed);
        final failure = (await repository.accept(theirs, prepMinutes: 20)).failureOrNull;
        expect(await statusOf(theirs), OrderStatus.placed, reason: 'nothing moved');
        return failure;
      },
    );

    repositoryContract<SupabaseMerchantOrderRepository>(
      name: "live owner reject, and another shop's order is not theirs",
      repository: asOwner,
      writeExisting: (repository) async {
        mine = await anOrder(merchantId, OrderStatus.placed);
        return (await repository.reject(mine, reason: 'مقفولين')).failureOrNull;
      },
      changed: (_) async => await statusOf(mine) == OrderStatus.cancelled,
      writeMissing: (repository) async {
        final theirs = await anOrder(otherMerchantId, OrderStatus.placed);
        return (await repository.reject(theirs, reason: 'مقفولين')).failureOrNull;
      },
    );

    repositoryContract<SupabaseMerchantOrderRepository>(
      name: "live owner advance, and another shop's order is not theirs",
      repository: asOwner,
      writeExisting: (repository) async {
        mine = await anOrder(merchantId, OrderStatus.accepted);
        return (await repository.advance(mine, to: OrderStatus.preparing)).failureOrNull;
      },
      changed: (_) async => await statusOf(mine) == OrderStatus.preparing,
      writeMissing: (repository) async {
        final theirs = await anOrder(otherMerchantId, OrderStatus.accepted);
        return (await repository.advance(theirs, to: OrderStatus.preparing))
            .failureOrNull;
      },
    );

    late String courierUid;
    Future<SupabaseCourierOrderRepository> asCourier() async {
      final (db, uid) = await live.openAsStaff(scope: 'platform', role: 'courier');
      addTearDown(db.dispose);
      courierUid = uid;
      return SupabaseCourierOrderRepository(db);
    }

    /// A second platform rider, who carries the order the first one must not reach.
    Future<String> anotherRider() async {
      final (db, uid) = await live.openAsStaff(scope: 'platform', role: 'courier');
      await db.dispose();
      return uid;
    }

    repositoryContract<SupabaseCourierOrderRepository>(
      name: "live courier markDelivered, and another rider's order is not theirs",
      repository: asCourier,
      writeExisting: (repository) async {
        mine = await anOrder(merchantId, OrderStatus.outForDelivery,
            deliveryBy: 'platform', courier: courierUid);
        return (await repository.markDelivered(mine)).failureOrNull;
      },
      changed: (_) async => await statusOf(mine) == OrderStatus.delivered,
      writeMissing: (repository) async {
        final theirs = await anOrder(merchantId, OrderStatus.outForDelivery,
            deliveryBy: 'platform', courier: await anotherRider());
        final failure = (await repository.markDelivered(theirs)).failureOrNull;
        expect(await statusOf(theirs), OrderStatus.outForDelivery,
            reason: 'nobody else is paid for a delivery they did not make');
        return failure;
      },
    );

    repositoryContract<SupabaseCourierOrderRepository>(
      name: "live courier markFailed, and another rider's order is not theirs",
      repository: asCourier,
      writeExisting: (repository) async {
        mine = await anOrder(merchantId, OrderStatus.outForDelivery,
            deliveryBy: 'platform', courier: courierUid);
        return (await repository.markFailed(mine, reason: 'محدش فتح')).failureOrNull;
      },
      changed: (_) async => await statusOf(mine) == OrderStatus.cancelled,
      writeMissing: (repository) async {
        final theirs = await anOrder(merchantId, OrderStatus.outForDelivery,
            deliveryBy: 'platform', courier: await anotherRider());
        return (await repository.markFailed(theirs, reason: 'محدش فتح')).failureOrNull;
      },
    );
  });
}
