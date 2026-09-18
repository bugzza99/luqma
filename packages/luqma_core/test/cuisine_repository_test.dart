import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  group('FakeCuisineRepository.cuisinesOf', () {
    test('returns empty set when merchant belongs to no cuisines', () async {
      final repo = FakeCuisineRepository(
        seed: const [
          Cuisine(id: 'c1', cityId: 'edku', name: 'مشويات'),
        ],
        members: const {
          'c1': {'m1', 'm2'},
        },
      );

      final result = await repo.cuisinesOf('m-unknown');
      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isEmpty);
    });

    test('returns all cuisines merchant belongs to by inverting members', () async {
      final repo = FakeCuisineRepository(
        seed: const [
          Cuisine(id: 'c1', cityId: 'edku', name: 'مشويات'),
          Cuisine(id: 'c2', cityId: 'edku', name: 'صيدليات'),
          Cuisine(id: 'c3', cityId: 'edku', name: 'سوبرماركت'),
        ],
        members: const {
          'c1': {'m1', 'm2'},
          'c2': {'m1'},
          'c3': {'m2', 'm3'},
        },
      );

      final m1Cuisines = await repo.cuisinesOf('m1');
      expect(m1Cuisines.isOk, isTrue);
      expect(m1Cuisines.valueOrNull, equals({'c1', 'c2'}));

      final m2Cuisines = await repo.cuisinesOf('m2');
      expect(m2Cuisines.isOk, isTrue);
      expect(m2Cuisines.valueOrNull, equals({'c1', 'c3'}));

      final m3Cuisines = await repo.cuisinesOf('m3');
      expect(m3Cuisines.isOk, isTrue);
      expect(m3Cuisines.valueOrNull, equals({'c3'}));
    });

    test('updates correctly after setMerchantCuisines', () async {
      final repo = FakeCuisineRepository(
        members: const {
          'c1': {'m1'},
        },
      );

      expect((await repo.cuisinesOf('m1')).valueOrNull, equals({'c1'}));

      // Reassign to c2 and c3
      final updateResult = await repo.setMerchantCuisines('m1', {'c2', 'c3'});
      expect(updateResult.isOk, isTrue);

      final updated = await repo.cuisinesOf('m1');
      expect(updated.isOk, isTrue);
      expect(updated.valueOrNull, equals({'c2', 'c3'}));

      // Clear all cuisines for m1
      await repo.setMerchantCuisines('m1', {});
      final cleared = await repo.cuisinesOf('m1');
      expect(cleared.isOk, isTrue);
      expect(cleared.valueOrNull, isEmpty);
    });

    test('propagates failure when failure is set', () async {
      final repo = FakeCuisineRepository(
        members: const {
          'c1': {'m1'},
        },
        failure: const OfflineFailure(),
      );

      final result = await repo.cuisinesOf('m1');
      expect(result.isOk, isFalse);
      expect(result.failureOrNull, isA<OfflineFailure>());
    });
  });
}
