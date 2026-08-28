import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'harness.dart';

/// The three numbers screens the owner reads, against the SQL that computes them.
///
/// `admin_today`, `admin_statistics` and `admin_attention` are `security definer`
/// functions: they run as the owner of the function, and the only thing standing between
/// a customer and every order total in the city is the `is_admin()` line at the top of
/// each. That line is worth a test of its own.
///
/// The counting itself is worth one too. These are read-only numbers, which sounds safe
/// until you remember that a wrong one is *believed* — nobody re-derives the day's
/// takings by hand.
void main() {
  late LiveDatabase live;
  late String cityId, zoneId, merchantId;
  late SupabaseClient admin;
  late AdminRepository repository;

  setUpAll(() async {
    live = await LiveDatabase.open();
    admin = await live.openAsAdmin();
    repository = SupabaseAdminRepository(admin);
  });

  tearDownAll(() async {
    await admin.dispose();
    await live.close();
  });

  setUp(() async {
    cityId = await live.makeCity();
    zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'المعمورة', 'default_delivery_fee': 1500})
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

  tearDown(() async => live.dropCity(cityId));

  /// An order sitting in [status] with [total] piastres on it.
  Future<String> order({
    required String status,
    int total = 10000,
    DateTime? createdAt,
    DateTime? deliveredAt,
  }) async {
    final uid = await live.makeCustomer();
    addTearDown(() async => live.client.from('users').delete().eq('id', uid));
    return live.client.from('orders').insert({
      'city_id': cityId,
      'customer_uid': uid,
      'customer_name': 'عميل',
      'customer_phone': '01000000000',
      'merchant_id': merchantId,
      'merchant_name': 'مطعم البحر',
      'zone_id': zoneId,
      'type': 'instant',
      'items': [],
      'pricing': {'total': total},
      'status': status,
      if (createdAt != null) 'created_at': createdAt.toUtc().toIso8601String(),
      if (deliveredAt != null)
        'delivered_at': deliveredAt.toUtc().toIso8601String(),
    }).select().single().then((row) => row['id'] as String);
  }

  group('today', () {
    test('a customer cannot read the day at all', () async {
      final (customer, _) = await live.openAsCustomer();
      addTearDown(customer.dispose);

      final result = await SupabaseAdminRepository(customer).today();

      // `security definer` runs as the function's owner, so the guard inside it is the
      // entire boundary — there is no policy behind it to catch a miss.
      expect(result.failureOrNull, isNotNull,
          reason: 'every order total in the city sits behind this one line');
    });

    test('an order handed over today is money in, in piastres', () async {
      final before = (await repository.today()).valueOrNull!;
      await order(status: 'delivered', total: 45000, deliveredAt: DateTime.now());

      final after = (await repository.today()).valueOrNull!;

      expect(after.ordersToday, before.ordersToday + 1);
      expect(after.moneyToday - before.moneyToday, 45000,
          reason: 'the row stores piastres and so does this figure — the screen divides');
    });

    // The owner's rule: this figure is the cash that actually came in, not the value of
    // what was ordered. The two differ by every order still in a kitchen.
    test('an order placed today but not yet handed over is not money in', () async {
      final before = (await repository.today()).valueOrNull!;
      await order(status: 'preparing', total: 60000);

      final after = (await repository.today()).valueOrNull!;

      expect(after.ordersToday, before.ordersToday + 1,
          reason: 'it is still an order placed today');
      expect(after.moneyToday, before.moneyToday,
          reason: 'nobody has paid for food that is still on the stove');
    });

    test('an order nobody answered is not money in either', () async {
      final before = (await repository.today()).valueOrNull!;
      await order(status: 'needsAttention', total: 70000);

      final after = (await repository.today()).valueOrNull!;
      expect(after.moneyToday, before.moneyToday,
          reason: 'an order the shop never answered is the least likely of all to be '
              'paid for');
    });

    // Cash arrives when the courier is handed it, whatever day the order was made.
    test('an order placed yesterday and handed over today counts today', () async {
      final before = (await repository.today()).valueOrNull!;
      await order(
        status: 'delivered',
        total: 25000,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        deliveredAt: DateTime.now(),
      );

      final after = (await repository.today()).valueOrNull!;
      expect(after.moneyToday - before.moneyToday, 25000);
    });

    test('and one handed over yesterday is not', () async {
      final before = (await repository.today()).valueOrNull!;
      await order(
        status: 'delivered',
        total: 31000,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        deliveredAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      final after = (await repository.today()).valueOrNull!;
      expect(after.moneyToday, before.moneyToday);
    });

    test('a cancelled order counts for nothing', () async {
      final before = (await repository.today()).valueOrNull!;
      await order(status: 'cancelled', total: 99000);

      final after = (await repository.today()).valueOrNull!;

      expect(after.ordersToday, before.ordersToday);
      expect(after.moneyToday, before.moneyToday,
          reason: 'an order nobody received did not move any cash');
    });

    test('an order placed two days ago is not one of the day orders', () async {
      final before = (await repository.today()).valueOrNull!;
      await order(
        status: 'placed',
        total: 33000,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      );

      expect((await repository.today()).valueOrNull!.ordersToday, before.ordersToday);
    });

    test('an order nobody answered is listed with the shop to ring', () async {
      final id = await order(status: 'needsAttention');

      final today = (await repository.today()).valueOrNull!;
      final waiting = today.needsAttention.where((i) => i.id == id);

      expect(waiting, hasLength(1));
      // An order number with no shop beside it tells the owner nothing about who to call,
      // and calling is the entire point of the queue.
      expect(waiting.single.merchantName, 'مطعم البحر');
      expect(waiting.single.merchantId, merchantId);
    });
  });

  group('attention', () {
    test('a customer cannot read it either', () async {
      final (customer, _) = await live.openAsCustomer();
      addTearDown(customer.dispose);

      expect((await SupabaseAdminRepository(customer).attention()).failureOrNull,
          isNotNull);
    });

    test('an unanswered order raises the count the grid draws', () async {
      final before = (await repository.attention()).valueOrNull!;
      await order(status: 'needsAttention');

      final after = (await repository.attention()).valueOrNull!;
      expect(after.ordersNeedingAttention, before.ordersNeedingAttention + 1,
          reason: 'the badge on the module grid is this number');
    });

    test('a merchant waiting for approval raises its own count', () async {
      final before = (await repository.attention()).valueOrNull!;
      await live.client.from('merchants').insert({
        'city_id': cityId,
        'type': 'restaurant',
        'name': 'مطعم مستني',
        'zone_id': zoneId,
        'phone': '01000000002',
        'status': 'pending',
      });

      final after = (await repository.attention()).valueOrNull!;
      expect(after.pendingMerchants, before.pendingMerchants + 1);
    });
  });

  group('statistics', () {
    test('a customer cannot read them', () async {
      final (customer, _) = await live.openAsCustomer();
      addTearDown(customer.dispose);

      expect((await SupabaseAdminRepository(customer).statistics()).failureOrNull,
          isNotNull);
    });

    test('merchants are broken down by the status they are actually in', () async {
      final stats = (await repository.statistics()).valueOrNull!;

      expect(stats.merchantsByStatus['approved'], greaterThanOrEqualTo(1),
          reason: 'the shop this test made is approved');
    });

    test('the average order is an average, not a sum', () async {
      await order(status: 'delivered', total: 10000);
      await order(status: 'delivered', total: 20000);

      final stats = (await repository.statistics()).valueOrNull!;

      // A sum shown where an average belongs grows all year and reads as a city where
      // every order is enormous.
      expect(stats.avgOrderValue, lessThan(stats.ordersTotal * 20000));
      expect(stats.avgOrderValue, greaterThan(0));
    });

    test('the growth series come back as series, not as nulls', () async {
      final stats = (await repository.statistics()).valueOrNull!;

      // The screen renders these directly; a null here is a crash rather than an empty
      // chart, and a brand-new city is exactly when it would happen.
      expect(stats.byWeek, isNotNull);
      expect(stats.byMonth, isNotNull);
    });
  });
}
