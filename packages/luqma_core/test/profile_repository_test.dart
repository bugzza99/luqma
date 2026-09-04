import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The customer's own profile and the boundary around deleting it.
void main() {
  group('FakeProfileRepository.deleteMyAccount', () {
    test('deletes an ordinary account and remains safe to call twice', () async {
      final repository = FakeProfileRepository();
      await repository.savePhone(uid: 'customer-1', phone: '01012345678');

      expect((await repository.deleteMyAccount()).isOk, true);
      expect(repository.accountDeleted, true);
      expect(repository.phones, isEmpty);

      expect((await repository.deleteMyAccount()).isOk, true);
    });

    // A fake that permits this would let the customer screen promise an operation the
    // server refuses, leaving the first real merchant or courier account as the test.
    test('refuses an account that belongs to staff', () async {
      final repository = FakeProfileRepository(isStaffAccount: true);

      final result = await repository.deleteMyAccount();

      expect(result.failureOrNull, isA<PermissionFailure>());
      expect(repository.accountDeleted, false);
    });

    test('passes a repository failure through without deleting locally', () async {
      final repository = FakeProfileRepository(failure: const OfflineFailure());

      final result = await repository.deleteMyAccount();

      expect(result.failureOrNull, isA<OfflineFailure>());
      expect(repository.accountDeleted, false);
    });
  });

  group('FakeProfileRepository marketing', () {
    // The column defaults to on, so an account nobody has touched must answer on. A fake
    // that answered false would draw the switch off and quietly disagree with the server.
    test('an account that never touched it is subscribed', () async {
      final repository = FakeProfileRepository();

      expect((await repository.readMarketingPush(uid: 'c1')).valueOrNull, true);
    });

    test('turning it off is remembered, and reads back off', () async {
      final repository = FakeProfileRepository();

      await repository.setMarketingPush(uid: 'c1', on: false);

      expect((await repository.readMarketingPush(uid: 'c1')).valueOrNull, false);
      // One customer's choice is not another's.
      expect((await repository.readMarketingPush(uid: 'c2')).valueOrNull, true);
    });

    test('a failure changes nothing', () async {
      final repository = FakeProfileRepository(failure: const OfflineFailure());

      final result = await repository.setMarketingPush(uid: 'c1', on: false);

      expect(result.failureOrNull, isA<OfflineFailure>());
      expect(repository.marketing, isEmpty);
    });
  });
}
