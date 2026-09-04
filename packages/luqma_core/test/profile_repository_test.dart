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
}
