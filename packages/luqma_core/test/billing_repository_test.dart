import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Plans, subscriptions, and the cash that pays for them.
///
/// Every figure here is money that changed hands in a shop, so nothing is inferred: a
/// subscription exists because somebody recorded a payment, and it expires on a date.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreBillingRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreBillingRepository(firestore);
  });

  Future<void> seedPlans() async {
    await firestore.collection('plans').doc('free').set({
      'name': 'مجانية',
      'priceMonthly': 0,
      'sortOrder': 0,
      'isActive': true,
      'features': {'maxItems': 20, 'verifiedBadge': false},
    });
    await firestore.collection('plans').doc('basic').set({
      'name': 'أساسية',
      'priceMonthly': 25000,
      'sortOrder': 1,
      'isActive': true,
      'features': {'maxItems': 0, 'verifiedBadge': true, 'analytics': true},
    });
    await firestore.collection('plans').doc('retired').set({
      'name': 'قديمة',
      'priceMonthly': 10000,
      'sortOrder': 3,
      'isActive': false,
      'features': <String, dynamic>{},
    });
  }

  group('plans', () {
    test('come back in the order the admin set', () async {
      await seedPlans();

      final plans = (await repository.plans()).valueOrNull!;

      expect(plans.map((p) => p.id), ['free', 'basic']);
    });

    // A plan withdrawn from sale must not vanish for merchants already on it, so it is
    // still readable by id — it just stops being offered.
    test('a retired plan is not offered but is still readable', () async {
      await seedPlans();

      final plans = (await repository.plans()).valueOrNull!;
      expect(plans.map((p) => p.id), isNot(contains('retired')));

      final all = (await repository.plans(includeInactive: true)).valueOrNull!;
      expect(all.map((p) => p.id), contains('retired'));
    });

    // Zero means unlimited, not "no items allowed". A plan that silently allowed nothing
    // would look like a bug in the menu editor rather than a pricing decision.
    test('an unlimited item count reads as unlimited', () async {
      await seedPlans();

      final plans = (await repository.plans()).valueOrNull!;
      final basic = plans.firstWhere((p) => p.id == 'basic');

      expect(basic.features.maxItems, 0);
      expect(basic.features.hasUnlimitedItems, isTrue);
      expect(plans.firstWhere((p) => p.id == 'free').features.hasUnlimitedItems,
          isFalse);
    });

    // A feature added on the server before this build knew about it must read as absent
    // rather than crashing every screen that checks a plan.
    test('a plan with features this build does not know still reads', () async {
      await firestore.collection('plans').doc('odd').set({
        'name': 'تجريبية',
        'priceMonthly': 1,
        'sortOrder': 0,
        'isActive': true,
        'features': {'timeTravel': true},
      });

      final plans = (await repository.plans()).valueOrNull!;

      expect(plans.single.features.verifiedBadge, isFalse);
    });
  });

  group('recording a payment', () {
    test('writes a subscription that runs from today', () async {
      final result = await repository.recordPayment(
        merchantId: 'm1',
        planId: 'basic',
        amount: 25000,
        months: 1,
        recordedBy: 'admin1',
      );

      final sub = result.valueOrNull!;
      expect(sub.merchantId, 'm1');
      expect(sub.planId, 'basic');
      expect(sub.amount, 25000);
      expect(sub.expiresAt.difference(sub.startedAt).inDays, inInclusiveRange(28, 31));
    });

    // Somebody paying for three months on the spot is normal here, and charging them
    // three times over three visits is how a merchant stops paying at all.
    test('several months at once run to the end of them', () async {
      final sub = (await repository.recordPayment(
        merchantId: 'm1',
        planId: 'basic',
        amount: 75000,
        months: 3,
        recordedBy: 'admin1',
      ))
          .valueOrNull!;

      expect(sub.expiresAt.difference(sub.startedAt).inDays, inInclusiveRange(89, 92));
    });

    // Renewing before the old term runs out must add to it, not throw the rest away.
    // The alternative is a merchant losing the days they already paid for.
    test('renewing early extends the term rather than restarting it', () async {
      final first = (await repository.recordPayment(
        merchantId: 'm1',
        planId: 'basic',
        amount: 25000,
        months: 1,
        recordedBy: 'admin1',
      ))
          .valueOrNull!;

      final second = (await repository.recordPayment(
        merchantId: 'm1',
        planId: 'basic',
        amount: 25000,
        months: 1,
        recordedBy: 'admin1',
      ))
          .valueOrNull!;

      expect(second.expiresAt.isAfter(first.expiresAt), isTrue);
      expect(
        second.expiresAt.difference(first.expiresAt).inDays,
        inInclusiveRange(28, 31),
      );
    });

    // Cash that moved between two people, recorded by a third. Without a name on it,
    // a disputed payment has nobody to ask.
    test('leaves a trail naming who recorded it', () async {
      await repository.recordPayment(
        merchantId: 'm1',
        planId: 'basic',
        amount: 25000,
        months: 1,
        recordedBy: 'admin1',
      );

      final log = await firestore.collection('auditLog').get();
      expect(log.docs.single.data()['by'], 'admin1');
      expect(log.docs.single.data()['action'], 'recordSubscriptionPayment');
    });
  });

  group('what a merchant is on', () {
    test('the live subscription, if there is one', () async {
      await repository.recordPayment(
        merchantId: 'm1',
        planId: 'basic',
        amount: 25000,
        months: 1,
        recordedBy: 'admin1',
      );

      final current = await repository.watchSubscription('m1').first;

      expect(current?.planId, 'basic');
      expect(current?.isActiveAt(DateTime.now()), isTrue);
    });

    test('nothing at all for a merchant who never paid', () async {
      expect(await repository.watchSubscription('m1').first, isNull);
    });

    // Expiry is a date passing, not a flag somebody has to remember to flip. The daily
    // pass downgrades the merchant; until it runs, this already reads as expired.
    test('an expired subscription reads as expired', () async {
      await firestore.collection('subscriptions').doc('s1').set({
        'merchantId': 'm1',
        'planId': 'basic',
        'amount': 25000,
        'startedAt': DateTime(2026, 1, 1),
        'expiresAt': DateTime(2026, 2, 1),
        'recordedBy': 'admin1',
      });

      final current = await repository.watchSubscription('m1').first;

      expect(current?.isActiveAt(DateTime(2026, 8, 23)), isFalse);
    });
  });

  group('topping up a wallet', () {
    test('adds to the balance rather than replacing it', () async {
      await firestore.collection('merchants').doc('m1').set({
        'cityId': 'edku',
        'type': 'restaurant',
        'name': 'مطعم',
        'zoneId': 'z1',
        'phone': '0100',
        'status': 'approved',
        'revenueModel': 'prepaid',
        'revenueValue': 500,
        'walletBalance': 2000,
      });

      await repository.topUpWallet(
        merchantId: 'm1',
        amount: 5000,
        recordedBy: 'admin1',
      );

      final doc = await firestore.collection('merchants').doc('m1').get();
      expect(doc.data()!['walletBalance'], 7000);
    });

    test('leaves a trail too', () async {
      await firestore.collection('merchants').doc('m1').set({
        'cityId': 'edku',
        'type': 'restaurant',
        'name': 'مطعم',
        'zoneId': 'z1',
        'phone': '0100',
        'status': 'approved',
        'walletBalance': 0,
      });

      await repository.topUpWallet(
        merchantId: 'm1',
        amount: 5000,
        recordedBy: 'admin1',
      );

      final log = await firestore.collection('auditLog').get();
      expect(log.docs.single.data()['action'], 'topUpWallet');
    });

    // Cash does not move backwards at a counter, and a negative top-up is a typo that
    // would quietly cancel somebody's credit.
    test('refuses an amount of zero or less', () async {
      final result = await repository.topUpWallet(
        merchantId: 'm1',
        amount: 0,
        recordedBy: 'admin1',
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
