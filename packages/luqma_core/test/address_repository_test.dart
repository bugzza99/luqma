import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// A customer's saved addresses.
///
/// They live under the customer's own user document, which is what makes the security
/// rule a single `isUser(uid)` rather than a per-document owner check.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreAddressRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreAddressRepository(firestore);
  });

  const home = Address(
    id: '',
    zoneId: 'z1',
    landmarkId: 'lm1',
    landmarkName: 'صيدلية النور',
    building: '12',
    label: 'البيت',
  );

  group('saving', () {
    test('a new address gets an id and comes back', () async {
      final saved = await repository.saveAddress('u1', home);

      expect(saved.valueOrNull?.id, isNotEmpty);
      final list = (await repository.addresses('u1')).valueOrNull!;
      expect(list.single.label, 'البيت');
    });

    test('editing an address does not create a second one', () async {
      final created = (await repository.saveAddress('u1', home)).valueOrNull!;

      await repository.saveAddress('u1', created.copyWith(building: '14'));

      final list = (await repository.addresses('u1')).valueOrNull!;
      expect(list, hasLength(1));
      expect(list.single.building, '14');
    });

    // One customer's addresses must never appear under another's, whatever else breaks.
    test('addresses are scoped to their owner', () async {
      await repository.saveAddress('u1', home);

      expect((await repository.addresses('u2')).valueOrNull, isEmpty);
    });
  });

  group('the default', () {
    test('the first address saved becomes the default on its own', () async {
      final created = (await repository.saveAddress('u1', home)).valueOrNull!;

      // Otherwise a customer with exactly one address is asked to choose it, every time.
      expect((await repository.defaultAddressId('u1')).valueOrNull, created.id);
    });

    test('a second address does not steal the default', () async {
      final first = (await repository.saveAddress('u1', home)).valueOrNull!;
      await repository.saveAddress(
        'u1',
        const Address(id: '', zoneId: 'z2', label: 'الشغل'),
      );

      expect((await repository.defaultAddressId('u1')).valueOrNull, first.id);
    });

    test('the default can be moved', () async {
      await repository.saveAddress('u1', home);
      final work = (await repository.saveAddress(
        'u1',
        const Address(id: '', zoneId: 'z2', label: 'الشغل'),
      )).valueOrNull!;

      await repository.setDefaultAddress('u1', work.id);

      expect((await repository.defaultAddressId('u1')).valueOrNull, work.id);
    });

    test('a customer with no addresses has no default', () async {
      expect((await repository.defaultAddressId('u1')).valueOrNull, isNull);
    });
  });

  group('deleting', () {
    test('a deleted address is gone', () async {
      final created = (await repository.saveAddress('u1', home)).valueOrNull!;

      await repository.deleteAddress('u1', created.id);

      expect((await repository.addresses('u1')).valueOrNull, isEmpty);
    });

    // Otherwise checkout points at an address that no longer exists and shows nothing,
    // with no way for the customer to tell why.
    test('deleting the default clears the default', () async {
      final created = (await repository.saveAddress('u1', home)).valueOrNull!;

      await repository.deleteAddress('u1', created.id);

      expect((await repository.defaultAddressId('u1')).valueOrNull, isNull);
    });

    // Being dropped back to "no address chosen" because one of three was deleted makes
    // the customer redo a choice they already made.
    test('deleting the default promotes one of the survivors', () async {
      final first = (await repository.saveAddress('u1', home)).valueOrNull!;
      final work = (await repository.saveAddress(
        'u1',
        const Address(id: '', zoneId: 'z2', label: 'الشغل'),
      )).valueOrNull!;

      await repository.deleteAddress('u1', first.id);

      expect((await repository.defaultAddressId('u1')).valueOrNull, work.id);
    });

    test('the fake promotes a survivor the same way', () async {
      final fake = FakeAddressRepository();
      final first = (await fake.saveAddress('u1', home)).valueOrNull!;
      final work = (await fake.saveAddress(
        'u1',
        const Address(id: '', zoneId: 'z2', label: 'الشغل'),
      )).valueOrNull!;

      await fake.deleteAddress('u1', first.id);

      expect((await fake.defaultAddressId('u1')).valueOrNull, work.id);
    });

    test('deleting a different address leaves the default alone', () async {
      final first = (await repository.saveAddress('u1', home)).valueOrNull!;
      final work = (await repository.saveAddress(
        'u1',
        const Address(id: '', zoneId: 'z2', label: 'الشغل'),
      )).valueOrNull!;

      await repository.deleteAddress('u1', work.id);

      expect((await repository.defaultAddressId('u1')).valueOrNull, first.id);
    });
  });

  group('the fake', () {
    test('behaves the same way about the first default', () async {
      final fake = FakeAddressRepository();

      final created = (await fake.saveAddress('u1', home)).valueOrNull!;

      expect((await fake.defaultAddressId('u1')).valueOrNull, created.id);
    });

    test('reports the failure it was given', () async {
      final fake = FakeAddressRepository(failure: const OfflineFailure());

      expect((await fake.addresses('u1')).failureOrNull, isA<OfflineFailure>());
    });
  });
}
