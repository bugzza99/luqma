import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// What AdminApp needs from the merchant repository, which is not what a customer needs.
///
/// A customer sees approved merchants only. The admin has to see the ones waiting for
/// approval — that queue is the entire point of the screen — and the ones suspended, or
/// suspending someone would make them disappear from the only place they could be
/// brought back.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreMerchantRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreMerchantRepository(firestore);
  });

  Merchant merchant(String id, {MerchantStatus status = MerchantStatus.approved}) =>
      Merchant(
        id: id,
        cityId: 'edku',
        type: MerchantType.restaurant,
        name: id,
        zoneId: 'z1',
        phone: '01000000000',
        status: status,
      );

  group('the admin list', () {
    test('includes merchants waiting for approval', () async {
      await repository.saveMerchant(merchant('a'));
      await repository.saveMerchant(merchant('b', status: MerchantStatus.pending));

      final all = await repository.watchAllMerchants(cityId: 'edku').first;

      expect(all.map((m) => m.id), containsAll(['a', 'b']));
    });

    test('includes suspended merchants, so they can be brought back', () async {
      await repository.saveMerchant(merchant('a', status: MerchantStatus.suspended));

      final all = await repository.watchAllMerchants(cityId: 'edku').first;

      expect(all.single.id, 'a');
    });

    test('still respects the city', () async {
      await repository.saveMerchant(merchant('a'));
      await repository.saveMerchant(
        merchant('elsewhere').copyWith(cityId: 'rosetta'),
      );

      final all = await repository.watchAllMerchants(cityId: 'edku').first;

      expect(all.map((m) => m.id), ['a']);
    });

    // Pending first: the queue is the reason to open this screen, and a merchant waiting
    // on approval is waiting on a person, not on a system.
    test('puts the ones needing a decision at the top', () async {
      await repository.saveMerchant(merchant('approved'));
      await repository.saveMerchant(merchant('waiting', status: MerchantStatus.pending));
      await repository.saveMerchant(
        merchant('suspended', status: MerchantStatus.suspended),
      );

      final all = await repository.watchAllMerchants(cityId: 'edku').first;

      expect(all.first.id, 'waiting');
    });
  });

  group('saving', () {
    test('a new merchant gets an id', () async {
      final saved = await repository.saveMerchant(merchant('').copyWith(name: 'الشاطئ'));

      expect(saved.valueOrNull?.id, isNotEmpty);
    });

    test('editing does not create a second one', () async {
      final created = (await repository.saveMerchant(merchant(''))).valueOrNull!;

      await repository.saveMerchant(created.copyWith(name: 'الاسم الجديد'));

      final all = await repository.watchAllMerchants(cityId: 'edku').first;
      expect(all, hasLength(1));
      expect(all.single.name, 'الاسم الجديد');
    });

    test('a merchant keeps its menu categories through an edit', () async {
      final created = (await repository.saveMerchant(
        merchant('').copyWith(
          menuCategories: const [MenuCategory(id: 'c1', name: 'مشويات')],
        ),
      )).valueOrNull!;

      await repository.saveMerchant(created.copyWith(phone: '01111111111'));

      final read = (await repository.getMerchant(created.id)).valueOrNull!;
      expect(read.menuCategories.single.name, 'مشويات');
    });
  });

  group('approving and suspending', () {
    test('approving makes a merchant visible to customers', () async {
      final created = (await repository.saveMerchant(
        merchant('', status: MerchantStatus.pending),
      )).valueOrNull!;

      expect(await repository.watchMerchants(cityId: 'edku').first, isEmpty);

      await repository.setStatus(created.id, MerchantStatus.approved);

      expect(await repository.watchMerchants(cityId: 'edku').first, hasLength(1));
    });

    test('suspending takes them back out', () async {
      final created = (await repository.saveMerchant(merchant(''))).valueOrNull!;

      await repository.setStatus(created.id, MerchantStatus.suspended);

      expect(await repository.watchMerchants(cityId: 'edku').first, isEmpty);
      expect(await repository.watchAllMerchants(cityId: 'edku').first, hasLength(1));
    });
  });
}
