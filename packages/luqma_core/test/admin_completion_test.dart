import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  group('FakeCustomerRepository', () {
    final ahmed = CustomerSummary(
      id: 'u1',
      name: 'أحمد',
      phone: '01001234567',
      isBlocked: false,
      rejectedOrdersCount: 2,
      createdAt: DateTime(2026, 8, 1),
    );

    test('search matches name and phone', () async {
      final repo = FakeCustomerRepository(seed: [ahmed]);

      expect((await repo.search('أحمد')).valueOrNull, hasLength(1));
      expect((await repo.search('0100')).valueOrNull, hasLength(1));
      // A phone typed with spaces still finds its person.
      expect((await repo.search('0100 123')).valueOrNull, hasLength(1));
      expect((await repo.search('محمود')).valueOrNull, isEmpty);
    });

    test('setBlocked flips the flag and records what it did', () async {
      final repo = FakeCustomerRepository(seed: [ahmed]);

      await repo.setBlocked('u1', blocked: true);
      expect(repo.blockCalls, [('u1', true)]);
      expect((await repo.search('أحمد')).valueOrNull!.first.isBlocked, isTrue);

      await repo.setBlocked('u1', blocked: false);
      expect((await repo.search('أحمد')).valueOrNull!.first.isBlocked, isFalse);
    });

    // A customer's account has no mailbox and no OTP behind it, so a forgotten password
    // has exactly one way back: they call, and an admin does this.
    test('resetting a password hands back one to read down the phone', () async {
      final repo = FakeCustomerRepository(seed: [ahmed]);

      final password = (await repo.resetPassword('u1')).valueOrNull;

      expect(password, isNotNull);
      expect(password, isNotEmpty);
      expect(repo.resetCalls, ['u1']);
    });

    test('resetting nobody is a not-found', () async {
      expect(
        (await FakeCustomerRepository().resetPassword('x')).failureOrNull,
        isA<NotFoundFailure>(),
      );
    });

    test('blocking nobody is a not-found, and failure passes through', () async {
      expect(
        (await FakeCustomerRepository().setBlocked('x', blocked: true))
            .failureOrNull,
        isA<NotFoundFailure>(),
      );
      expect(
        (await FakeCustomerRepository(failure: const OfflineFailure())
                .search(''))
            .failureOrNull,
        isA<OfflineFailure>(),
      );
    });
  });

  group('FakeIssueRepository', () {
    OrderIssue issue(String id, {String status = OrderIssue.open}) =>
        OrderIssue(
          id: id,
          orderId: 'o-$id',
          customerUid: 'c1',
          merchantId: 'm1',
          reason: 'الأوردر اتأخر',
          status: status,
          createdAt: DateTime(2026, 8, 20),
        );

    test('open tickets sort before closed ones', () async {
      final repo = FakeIssueRepository(seed: [
        issue('closed-early', status: OrderIssue.closed),
        issue('open'),
      ]);

      final seen = await repo.watchIssues().first;
      expect(seen.first.id, 'open');
    });

    test('close answers and closes in one write', () async {
      final repo = FakeIssueRepository(seed: [issue('i1')]);
      await repo.close('i1', adminNote: 'اتصلنا بالمطعم');

      final ticket =
          (await repo.watchIssues().first).single;
      expect(ticket.isOpen, isFalse);
      expect(ticket.adminNote, 'اتصلنا بالمطعم');
    });
  });

  group('FakeStaffRepository', () {
    test('deactivating keeps the account but shuts the door', () async {
      final courier = StaffMember(
        uid: 's1',
        scope: 'merchant',
        role: 'courier',
        merchantId: 'm1',
        name: 'ساعي',
        isActive: true,
      );
      final repo = FakeStaffRepository(seed: [courier]);

      await repo.setActive('s1', active: false);

      final member = (await repo.watchStaff().first).single;
      expect(member.isActive, isFalse);
      expect(member.uid, 's1');
    });

    test('the last active platform admin cannot be deactivated', () async {
      final admin = StaffMember(
        uid: 'admin-1',
        scope: 'platform',
        role: 'admin',
        isActive: true,
      );
      final repo = FakeStaffRepository(seed: [admin]);

      final result = await repo.setActive(admin.uid, active: false);

      expect(result.failureOrNull, isA<ConflictFailure>());
      expect(repo.all.single.isActive, isTrue);
    });

    test('an admin can be deactivated while another remains active', () async {
      StaffMember admin(String uid) => StaffMember(
            uid: uid,
            scope: 'platform',
            role: 'admin',
            isActive: true,
          );
      final repo = FakeStaffRepository(seed: [admin('admin-1'), admin('admin-2')]);

      final result = await repo.setActive('admin-1', active: false);

      expect(result.isOk, isTrue);
      expect(repo.all.singleWhere((member) => member.uid == 'admin-1').isActive,
          isFalse);
    });
  });

  group('FakeBillingRepository.savePlan', () {
    Plan plan({int priceMonthly = 25000}) => Plan(
          id: 'basic',
          name: 'أساسية',
          priceMonthly: priceMonthly,
          sortOrder: 1,
        );

    test('saving replaces the plan with the same id', () async {
      final repo = FakeBillingRepository(seedPlans: [plan()]);
      await repo.savePlan(plan(priceMonthly: 30000));

      expect(repo.audit.last['action'], 'savePlan');
      expect(
        (await repo.plans(includeInactive: true)).valueOrNull!.single
            .priceMonthly,
        30000,
      );
    });
  });

  group('FakeMerchantRepository.deleteMerchant', () {
    Merchant merchant(String id) => Merchant(
          id: id,
          cityId: 'edku',
          type: MerchantType.restaurant,
          name: 'مطعم',
          zoneId: 'z1',
          phone: '010',
          status: MerchantStatus.pending,
        );

    test('a merchant that never traded deletes cleanly', () async {
      final repo = FakeMerchantRepository(seed: [merchant('m1')]);
      expect((await repo.deleteMerchant('m1')).isOk, isTrue);
      expect((await repo.getMerchant('m1')).failureOrNull,
          isA<NotFoundFailure>());
    });

    test('a merchant with orders is a conflict, not a delete', () async {
      final repo = FakeMerchantRepository(
        seed: [merchant('m2')],
        orderCounts: {'m2': 7},
      );
      expect((await repo.deleteMerchant('m2')).failureOrNull,
          isA<ConflictFailure>());
    });

    test('orderCount is the real number the delete control is decided on', () async {
      final repo = FakeMerchantRepository(
        seed: [merchant('m1'), merchant('m2')],
        orderCounts: {'m2': 7},
      );

      expect((await repo.orderCount('m1')).valueOrNull, 0);
      expect((await repo.orderCount('m2')).valueOrNull, 7);
    });
  });
}
