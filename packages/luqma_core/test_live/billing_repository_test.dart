import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// Plans, subscriptions, and the cash that pays for them, against a real Postgres.
///
/// Every figure here is money that changed hands in a shop, so the money functions are
/// exercised as functions — receipt, state and memory landing together or not at all.
void main() {
  late LiveDatabase live;
  late SupabaseBillingRepository repository;
  late String cityId;
  late String zoneId;
  late String merchantId;
  late String adminUid;

  setUpAll(() async {
    live = await LiveDatabase.open();
    repository = SupabaseBillingRepository(live.client);
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
      'revenue_model': 'subscription',
    }).select().single().then((row) => row['id'] as String);
    adminUid = await live.makeCustomer();

    // Plans are global with fixed ids, so seeding is an upsert rather than an insert.
    await live.client.from('plans').upsert([
      {
        'id': 'free', 'name': 'مجانية', 'price_monthly': 0,
        'sort_order': 0, 'is_active': true,
        'features': {'maxItems': 20, 'verifiedBadge': false},
      },
      {
        'id': 'basic', 'name': 'أساسية', 'price_monthly': 25000,
        'sort_order': 1, 'is_active': true,
        'features': {'maxItems': 0, 'verifiedBadge': true, 'analytics': true},
      },
      {
        'id': 'retired', 'name': 'قديمة', 'price_monthly': 10000,
        'sort_order': 3, 'is_active': false, 'features': <String, dynamic>{},
      },
    ]);
  });

  tearDown(() async {
    // Subscriptions and the audit entries reference this merchant; they go first.
    await live.client.from('audit_log').delete().eq('merchant_id', merchantId);
    await live.client.from('subscriptions').delete().eq('merchant_id', merchantId);
    await live.dropCity(cityId);
  });

  group('plans', () {
    test('come back in the order the admin set', () async {
      final ids = (await repository.plans()).valueOrNull!.map((p) => p.id).toList();

      // Plans are global, so Edku's own seeded plans sit beside these. What this
      // test owns is the two it upserted and their relative order - sort_order,
      // not the whole list, is the contract.
      expect(ids, containsAllInOrder(['free', 'basic']));
      expect(ids, isNot(contains('retired')));
    });

    // A plan withdrawn from sale must not vanish for merchants already on it.
    test('a retired plan is not offered but is still readable', () async {
      final all = (await repository.plans(includeInactive: true)).valueOrNull!;

      expect(all.map((p) => p.id), containsAll(['retired']));
      expect(
        (await repository.plans()).valueOrNull!.map((p) => p.id),
        isNot(contains('retired')),
      );
    });

    // Zero means unlimited, not "no items allowed".
    test('an unlimited item count reads as unlimited', () async {
      final plans = (await repository.plans()).valueOrNull!;
      final basic = plans.firstWhere((p) => p.id == 'basic');

      expect(basic.features.maxItems, 0);
      expect(basic.features.hasUnlimitedItems, isTrue);
      expect(plans.firstWhere((p) => p.id == 'free').features.hasUnlimitedItems,
          isFalse);
    });
  });

  group('recording a payment', () {
    test('writes a subscription that runs from today', () async {
      final result = await repository.recordPayment(
        merchantId: merchantId,
        planId: 'basic',
        amount: 25000,
        months: 1,
        recordedBy: adminUid,
      );

      final saved = result.valueOrNull!;
      expect(saved.planId, 'basic');
      expect(saved.isActiveAt(DateTime.now()), isTrue);

      // The subscription is the receipt; the plan on the merchant is the state.
      final merchant = await live.client
          .from('merchants')
          .select('plan_id')
          .eq('id', merchantId)
          .single();
      expect(merchant['plan_id'], 'basic');

      final log = await live.client
          .from('audit_log')
          .select()
          .eq('merchant_id', merchantId);
      expect(log.single['action'], 'recordSubscriptionPayment');
    });

    // Renewing before the old term runs out adds to it. Restarting from today would
    // quietly throw away the days already paid for.
    test('renewing an unexpired term extends it rather than restarting', () async {
      await repository.recordPayment(
        merchantId: merchantId,
        planId: 'basic',
        amount: 25000,
        months: 1,
        recordedBy: adminUid,
      );
      final first = (await repository.watchSubscription(merchantId).first)!;
      final expectedFrom = first.expiresAt;

      await repository.recordPayment(
        merchantId: merchantId,
        planId: 'basic',
        amount: 25000,
        months: 2,
        recordedBy: adminUid,
      );

      final current = (await repository.watchSubscription(merchantId).first)!;
      // Thirty days per month, deliberately not a calendar month.
      expect(current.expiresAt.difference(expectedFrom).inDays, 30 * 2);
    });
  });

  group('watching one subscription', () {
    test('nothing at all for a merchant who never paid', () async {
      expect(await repository.watchSubscription(merchantId).first, isNull);
    });
  });

  group('topping up a wallet', () {
    test('adds to the balance rather than replacing it', () async {
      // Seeded by insertion rather than update: the column guards stop a raw client
      // from moving a wallet, which is precisely the point of them.
      final id = await live.client.from('merchants').insert({
        'city_id': cityId,
        'type': 'restaurant',
        'name': 'مطعم مدفوع',
        'zone_id': zoneId,
        'phone': '01000000002',
        'status': 'approved',
        'revenue_model': 'prepaid',
        'wallet_balance': 2000,
      }).select().single().then((row) => row['id'] as String);

      await repository.topUpWallet(
        merchantId: id,
        amount: 5000,
        recordedBy: adminUid,
      );

      final merchant = await live.client
          .from('merchants')
          .select('wallet_balance')
          .eq('id', id)
          .single();
      expect(merchant['wallet_balance'], 7000);
    });

    test('leaves a trail too', () async {
      await repository.topUpWallet(
        merchantId: merchantId,
        amount: 5000,
        recordedBy: adminUid,
      );

      final log = await live.client
          .from('audit_log')
          .select()
          .eq('merchant_id', merchantId);
      expect(log.single['action'], 'topUpWallet');
    });

    // Cash does not move backwards at a counter, and a negative top-up is a typo that
    // would quietly cancel somebody's credit.
    test('refuses an amount of zero or less', () async {
      final result = await repository.topUpWallet(
        merchantId: merchantId,
        amount: 0,
        recordedBy: adminUid,
      );

      expect(result.failureOrNull, isNotNull);
    });
  });

  group('the fake', () {
    test('records a payment the same way', () async {
      final fake = FakeBillingRepository();

      await fake.recordPayment(
        merchantId: 'm1',
        planId: 'basic',
        amount: 25000,
        months: 1,
        recordedBy: 'admin1',
      );

      expect((await fake.watchSubscription('m1').first)?.planId, 'basic');
    });

    test('reports the failure it was given', () async {
      final fake = FakeBillingRepository(failure: const OfflineFailure());

      expect((await fake.plans()).failureOrNull, isA<OfflineFailure>());
    });
  });
}
