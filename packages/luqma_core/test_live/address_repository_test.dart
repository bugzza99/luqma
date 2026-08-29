import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// A customer's saved addresses, against a real Postgres.
///
/// The port of `test/address_repository_test.dart`, which ran the real implementation
/// against an in-memory Firestore. There is no in-memory Supabase, and after the audit
/// that is a feature rather than a gap: the fake was what let a broken query look green.
void main() {
  late LiveDatabase live;
  late SupabaseAddressRepository repository;
  late String cityId;
  late String zoneId;
  late String uid;

  setUpAll(() async {
    live = await LiveDatabase.open();
    repository = SupabaseAddressRepository(live.client);
  });

  setUp(() async {
    cityId = await live.makeCity();
    zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'المعمورة'})
        .select()
        .single()
        .then((row) => row['id'] as String);
    uid = await live.makeCustomer();
  });

  tearDown(() async {
    // The user row first: addresses cascade with it, and zones refuse to be deleted
    // while an address still points at one.
    await live.client.from('users').delete().eq('id', uid);
    await live.dropCity(cityId);
  });
  tearDownAll(() => live.close());

  Address home() => Address(id: '', zoneId: zoneId, building: '12', label: 'البيت');

  group('saving', () {
    test('a new address gets an id and comes back', () async {
      final saved = await repository.saveAddress(uid, home());

      expect(saved.valueOrNull?.id, isNotEmpty);
      final list = (await repository.addresses(uid)).valueOrNull!;
      expect(list.single.label, 'البيت');
    });

    test('editing an address does not create a second one', () async {
      final created = (await repository.saveAddress(uid, home())).valueOrNull!;

      await repository.saveAddress(uid, created.copyWith(building: '14'));

      final list = (await repository.addresses(uid)).valueOrNull!;
      expect(list, hasLength(1));
      expect(list.single.building, '14');
    });

    // One customer's addresses must never appear under another's, whatever else breaks.
    test('addresses are scoped to their owner', () async {
      await repository.saveAddress(uid, home());

      final other = await live.makeCustomer();
      addTearDown(() => live.client.from('users').delete().eq('id', other));
      expect((await repository.addresses(other)).valueOrNull, isEmpty);
    });

    // The model's geo fields belong to an order's frozen copy; a saved address has no
    // column for them. The write must survive their presence — and the round trip
    // documents the drop rather than pretending they were kept.
    test('an address carrying lat and lng still saves', () async {
      final saved = (await repository.saveAddress(
        uid,
        home().copyWith(lat: 30.9, lng: 30.3),
      )).valueOrNull!;

      expect((await repository.addresses(uid)).valueOrNull, hasLength(1));
      expect(saved.lat, isNull);
    });

    // An empty landmark id means "none" here as everywhere else; the uuid column would
    // refuse the empty string before any policy had a chance to speak.
    test('an empty landmark id saves as no landmark', () async {
      final saved = (await repository.saveAddress(
        uid,
        home().copyWith(landmarkName: 'الجامع'),
      )).valueOrNull!;

      expect(saved.landmarkId, isNull);
      expect(saved.landmarkName, 'الجامع');
    });
  });

  group('the default', () {
    test('the first address saved becomes the default on its own', () async {
      final created = (await repository.saveAddress(uid, home())).valueOrNull!;

      // Otherwise a customer with exactly one address is asked to choose it, every time.
      expect((await repository.defaultAddressId(uid)).valueOrNull, created.id);
    });

    test('a second address does not steal the default', () async {
      final first = (await repository.saveAddress(uid, home())).valueOrNull!;
      await repository.saveAddress(uid, home().copyWith(label: 'الشغل'));

      expect((await repository.defaultAddressId(uid)).valueOrNull, first.id);
    });

    test('the default can be moved', () async {
      await repository.saveAddress(uid, home());
      final work =
          (await repository.saveAddress(uid, home().copyWith(label: 'الشغل')))
              .valueOrNull!;

      await repository.setDefaultAddress(uid, work.id);

      expect((await repository.defaultAddressId(uid)).valueOrNull, work.id);
    });

    test('a customer with no addresses has no default', () async {
      expect((await repository.defaultAddressId(uid)).valueOrNull, isNull);
    });
  });

  group('deleting', () {
    test('a deleted address is gone', () async {
      final created = (await repository.saveAddress(uid, home())).valueOrNull!;

      await repository.deleteAddress(uid, created.id);

      expect((await repository.addresses(uid)).valueOrNull, isEmpty);
    });

    // Otherwise checkout points at an address that no longer exists and shows nothing,
    // with no way for the customer to tell why.
    test('deleting the default clears the default', () async {
      final created = (await repository.saveAddress(uid, home())).valueOrNull!;

      await repository.deleteAddress(uid, created.id);

      expect((await repository.defaultAddressId(uid)).valueOrNull, isNull);
    });

    // Being dropped back to "no address chosen" because one of three was deleted makes
    // the customer redo a choice they already made.
    test('deleting the default promotes one of the survivors', () async {
      final first = (await repository.saveAddress(uid, home())).valueOrNull!;
      final work =
          (await repository.saveAddress(uid, home().copyWith(label: 'الشغل')))
              .valueOrNull!;

      await repository.deleteAddress(uid, first.id);

      expect((await repository.defaultAddressId(uid)).valueOrNull, work.id);
    });

    test('deleting a different address leaves the default alone', () async {
      final first = (await repository.saveAddress(uid, home())).valueOrNull!;
      final work =
          (await repository.saveAddress(uid, home().copyWith(label: 'الشغل')))
              .valueOrNull!;

      await repository.deleteAddress(uid, work.id);

      expect((await repository.defaultAddressId(uid)).valueOrNull, first.id);
    });
  });

  // The fake is the contract every screen test stands on, so it has to agree with the
  // database about the rules that matter most.
  group('the fake', () {
    test('behaves the same way about the first default', () async {
      final fake = FakeAddressRepository();

      final created = (await fake.saveAddress(uid, home())).valueOrNull!;

      expect((await fake.defaultAddressId(uid)).valueOrNull, created.id);
    });

    test('promotes a survivor the same way the database does', () async {
      final fake = FakeAddressRepository();
      final first = (await fake.saveAddress(uid, home())).valueOrNull!;
      final work =
          (await fake.saveAddress(uid, home().copyWith(label: 'الشغل')))
              .valueOrNull!;

      await fake.deleteAddress(uid, first.id);

      expect((await fake.defaultAddressId(uid)).valueOrNull, work.id);
    });

    test('reports the failure it was given', () async {
      final fake = FakeAddressRepository(failure: const OfflineFailure());

      expect((await fake.addresses(uid)).failureOrNull, isA<OfflineFailure>());
    });
  });
}
