import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The fake applies the server's rules for asking for a plan, so screens built on it are
/// refused where production refuses them.
void main() {
  const basic = Plan(id: 'basic', name: 'أساسية', priceMonthly: 100000);
  const retired = Plan(id: 'old', name: 'قديمة', priceMonthly: 5000, isActive: false);

  test('a shop asks: the price is the plan times the months, and it is pending', () async {
    final repo = FakeSubscriptionRequestRepository(plans: const [basic], merchantId: 'm1');

    final r = (await repo.request(
      planId: 'basic',
      months: 3,
      paymentMethod: SubscriptionPaymentMethod.transfer,
      transferReference: '  VF123  ',
    ))
        .valueOrNull!;

    expect(r.quotedAmount, 300000);
    expect(r.isPending, isTrue);
    expect(r.transferReference, 'VF123');
  });

  test('one pending request per shop, active plans only, the four lengths only', () async {
    final repo = FakeSubscriptionRequestRepository(plans: const [basic, retired], merchantId: 'm1');

    expect((await repo.request(planId: 'old', months: 1, paymentMethod: SubscriptionPaymentMethod.cash))
        .failureOrNull, isA<ValidationFailure>());
    expect((await repo.request(planId: 'basic', months: 2, paymentMethod: SubscriptionPaymentMethod.cash))
        .failureOrNull, isA<ValidationFailure>());
    await repo.request(planId: 'basic', months: 1, paymentMethod: SubscriptionPaymentMethod.cash);
    expect((await repo.request(planId: 'basic', months: 6, paymentMethod: SubscriptionPaymentMethod.cash))
        .failureOrNull, isA<ConflictFailure>());
  });

  test('an admin activates or rejects a pending request once, and a reason is required', () async {
    final seed = [
      SubscriptionRequest(
        id: 'a',
        merchantId: 'm1',
        planId: 'basic',
        months: 1,
        quotedAmount: 100000,
        paymentMethod: SubscriptionPaymentMethod.cash,
        status: SubscriptionRequestStatus.pending,
        createdAt: DateTime(2026, 9, 17),
      ),
      SubscriptionRequest(
        id: 'b',
        merchantId: 'm2',
        planId: 'basic',
        months: 1,
        quotedAmount: 100000,
        paymentMethod: SubscriptionPaymentMethod.cash,
        status: SubscriptionRequestStatus.pending,
        createdAt: DateTime(2026, 9, 17),
      ),
    ];
    final admin = FakeSubscriptionRequestRepository(seed: seed);

    expect(await admin.activate('a', amount: 80000), isA<Ok<void>>());
    expect(admin.activations.single, ('a', 80000));
    expect((await admin.activate('a')).failureOrNull, isA<ConflictFailure>());
    expect((await admin.reject('b', '  ')).failureOrNull, isA<ValidationFailure>());
    expect(await admin.reject('b', 'مفيش تحويل وصل'), isA<Ok<void>>());
    expect((await admin.pending()).valueOrNull, isEmpty);
  });

  test('a shop cannot answer requests or read the overview', () async {
    final shop = FakeSubscriptionRequestRepository(plans: const [basic], merchantId: 'm1');
    final r = (await shop.request(planId: 'basic', months: 1, paymentMethod: SubscriptionPaymentMethod.cash))
        .valueOrNull!;

    expect((await shop.activate(r.id)).failureOrNull, isA<PermissionFailure>());
    expect((await shop.overview()).failureOrNull, isA<PermissionFailure>());
    expect(await shop.cancel(r.id), isA<Ok<void>>());
  });

  test('where a plan stands', () {
    final now = DateTime(2026, 9, 17, 12);
    SubscriptionOverviewRow row(DateTime? expires) => SubscriptionOverviewRow(
          merchantId: 'm',
          merchantName: 'x',
          planId: expires == null ? null : 'basic',
          planExpiresAt: expires,
        );

    expect(row(null).standingAt(now), PlanStanding.none);
    expect(row(now.add(const Duration(days: 20))).standingAt(now), PlanStanding.active);
    expect(row(now.add(const Duration(days: 3))).standingAt(now), PlanStanding.endingSoon);
    expect(row(now.subtract(const Duration(hours: 1))).standingAt(now), PlanStanding.expired);
  });
}
