import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// These run the real repository against an in-memory Firestore, so the queries, the
/// field names and the Timestamp mapping are all genuinely exercised — the parts that
/// break silently when they are stubbed out instead.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreMerchantRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreMerchantRepository(firestore);
  });

  Future<void> seed(
    String id, {
    String cityId = 'edku',
    MerchantStatus status = MerchantStatus.approved,
    String name = 'مطعم',
    DateTime? pausedUntil,
  }) {
    return firestore.collection('merchants').doc(id).set({
      'id': id,
      'cityId': cityId,
      'type': 'restaurant',
      'name': name,
      'zoneId': 'z1',
      'phone': '01000000000',
      'status': status.name,
      'openingHours': const <Map<String, Object>>[],
      if (pausedUntil != null) 'pausedUntil': Timestamp.fromDate(pausedUntil),
    });
  }

  group('watchMerchants', () {
    test('returns approved merchants in the requested city', () async {
      await seed('a');
      await seed('b');

      final merchants = await repository.watchMerchants(cityId: 'edku').first;

      expect(merchants.map((m) => m.id), containsAll(['a', 'b']));
    });

    test('hides merchants awaiting approval from customers', () async {
      await seed('approved');
      await seed('pending', status: MerchantStatus.pending);

      final merchants = await repository.watchMerchants(cityId: 'edku').first;

      expect(merchants.map((m) => m.id), ['approved']);
    });

    test('hides suspended merchants', () async {
      await seed('good');
      await seed('suspended', status: MerchantStatus.suspended);

      final merchants = await repository.watchMerchants(cityId: 'edku').first;

      expect(merchants.map((m) => m.id), ['good']);
    });

    // The model carries cityId everywhere precisely so this filter exists from day one
    // and a second city is a data change rather than a migration.
    test('does not leak merchants from another city', () async {
      await seed('here');
      await seed('elsewhere', cityId: 'rosetta');

      final merchants = await repository.watchMerchants(cityId: 'edku').first;

      expect(merchants.map((m) => m.id), ['here']);
    });

    test('emits again when a merchant changes', () async {
      await seed('a');
      final stream = repository.watchMerchants(cityId: 'edku');

      expect(
        stream.map((list) => list.length),
        emitsInOrder([1, 2]),
      );

      await seed('b');
    });
  });

  group('getMerchant', () {
    test('reads a merchant back with its fields intact', () async {
      await seed('a', name: 'كشري المحطة');

      final result = await repository.getMerchant('a');

      expect(result.valueOrNull?.name, 'كشري المحطة');
    });

    // Firestore hands back a Timestamp, not a string. If this mapping is wrong the
    // failure is a merchant that never reopens after a busy pause.
    test('maps a Firestore Timestamp back into a DateTime', () async {
      final until = DateTime(2026, 8, 18, 14, 30);
      await seed('a', pausedUntil: until);

      final result = await repository.getMerchant('a');

      expect(result.valueOrNull?.pausedUntil, until);
    });

    test('a missing merchant is a not-found failure, not an empty merchant', () async {
      final result = await repository.getMerchant('nobody');

      expect(result.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('pause', () {
    test('setting a pause is visible on the next read', () async {
      await seed('a');
      final until = DateTime(2026, 8, 18, 15, 0);

      await repository.setPausedUntil('a', until);

      expect((await repository.getMerchant('a')).valueOrNull?.pausedUntil, until);
    });

    test('clearing a pause removes it', () async {
      await seed('a', pausedUntil: DateTime(2026, 8, 18, 15));

      await repository.setPausedUntil('a', null);

      expect((await repository.getMerchant('a')).valueOrNull?.pausedUntil, isNull);
    });
  });

  group('the fake repository behaves like the real one', () {
    test('it filters by status and city the same way', () async {
      final fake = FakeMerchantRepository(seed: [
        _merchant('a'),
        _merchant('b', status: MerchantStatus.pending),
        _merchant('c', cityId: 'rosetta'),
      ]);

      final merchants = await fake.watchMerchants(cityId: 'edku').first;

      expect(merchants.map((m) => m.id), ['a']);
    });

    test('it reports a missing merchant as not found', () async {
      final fake = FakeMerchantRepository();
      expect((await fake.getMerchant('nobody')).failureOrNull, isA<NotFoundFailure>());
    });

    // A fake that always succeeds only ever tests the happy path, and the failure
    // branches are exactly the ones that reach a customer standing in the street.
    test('it can be told to fail, so error paths are testable', () async {
      final fake = FakeMerchantRepository(failure: const OfflineFailure());
      expect((await fake.getMerchant('a')).failureOrNull, isA<OfflineFailure>());
    });
  });
}

Merchant _merchant(
  String id, {
  String cityId = 'edku',
  MerchantStatus status = MerchantStatus.approved,
}) {
  return Merchant(
    id: id,
    cityId: cityId,
    type: MerchantType.restaurant,
    name: id,
    zoneId: 'z1',
    phone: '01000000000',
    status: status,
  );
}
