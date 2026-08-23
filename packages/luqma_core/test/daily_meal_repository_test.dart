import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Publishing a meal, and finding today's.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreDailyMealRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestoreDailyMealRepository(firestore);
  });

  DailyMeal meal({
    String id = '',
    String merchantId = 'm1',
    String date = '2026-08-23',
    int remainingQty = 8,
    DailyMealStatus status = DailyMealStatus.published,
  }) =>
      DailyMeal(
        id: id,
        merchantId: merchantId,
        cityId: 'edku',
        name: 'محشي كرنب',
        price: 9000,
        date: date,
        totalQty: 20,
        remainingQty: remainingQty,
        pickupWindowStart: 13 * 60,
        pickupWindowEnd: 16 * 60,
        status: status,
      );

  group('publishing', () {
    test('a new meal gets an id and comes back', () async {
      final saved = await repository.saveMeal(meal());

      expect(saved.valueOrNull?.id, isNotEmpty);
      final today = await repository.watchToday(cityId: 'edku', day: '2026-08-23').first;
      expect(today.single.name, 'محشي كرنب');
    });

    test('editing does not create a second one', () async {
      final created = (await repository.saveMeal(meal())).valueOrNull!;

      await repository.saveMeal(created.copyWith(name: 'محشي ورق عنب'));

      final today = await repository.watchToday(cityId: 'edku', day: '2026-08-23').first;
      expect(today, hasLength(1));
      expect(today.single.name, 'محشي ورق عنب');
    });

    // The count is the server's to move. A kitchen that could write it could sell the
    // same portion twice, which is the one thing this whole collection exists to stop.
    test('saving an existing meal cannot rewrite what is left', () async {
      final created = (await repository.saveMeal(meal(remainingQty: 8))).valueOrNull!;

      await repository.saveMeal(created.copyWith(remainingQty: 999, totalQty: 999));

      final today = await repository.watchToday(cityId: 'edku', day: '2026-08-23').first;
      expect(today.single.remainingQty, 8);
    });

    // Raising the count on a *new* meal is just deciding how much to cook.
    test('a new meal sets its own count', () async {
      final created = (await repository.saveMeal(meal(remainingQty: 30))).valueOrNull!;

      expect(created.remainingQty, 30);
    });
  });

  group("what a customer sees today", () {
    test('published meals for today, in this city', () async {
      await repository.saveMeal(meal());
      await repository.saveMeal(meal(date: '2026-08-22'));
      await repository.saveMeal(meal(status: DailyMealStatus.draft));

      final today = await repository.watchToday(cityId: 'edku', day: '2026-08-23').first;

      expect(today, hasLength(1));
    });

    // Sold out still shows. A section that quietly loses a meal at eight o'clock makes
    // the whole thing look like it was never there — and "خلص" is information: it is
    // what teaches somebody to order earlier tomorrow.
    test('a sold-out meal is still shown', () async {
      await repository.saveMeal(meal(remainingQty: 0));

      final today = await repository.watchToday(cityId: 'edku', day: '2026-08-23').first;

      expect(today.single.isSoldOut, isTrue);
    });

    test('a closed meal is not', () async {
      await repository.saveMeal(meal(status: DailyMealStatus.closed));

      expect(
        await repository.watchToday(cityId: 'edku', day: '2026-08-23').first,
        isEmpty,
      );
    });
  });

  group("one kitchen's own", () {
    test('sees its drafts as well as what is published', () async {
      await repository.saveMeal(meal(status: DailyMealStatus.draft));
      await repository.saveMeal(meal(id: '', status: DailyMealStatus.published));
      await repository.saveMeal(meal(merchantId: 'm2'));

      final mine = await repository.watchForMerchant('m1').first;

      expect(mine, hasLength(2));
    });
  });

  group('closing one early', () {
    test('takes it off the customer\'s screen without touching the count', () async {
      final created = (await repository.saveMeal(meal())).valueOrNull!;

      await repository.setStatus(created.id, DailyMealStatus.closed);

      expect(
        await repository.watchToday(cityId: 'edku', day: '2026-08-23').first,
        isEmpty,
      );
      final mine = await repository.watchForMerchant('m1').first;
      expect(mine.single.remainingQty, 8);
    });
  });

  group('the fake', () {
    test('publishes and finds today the same way', () async {
      final fake = FakeDailyMealRepository();

      await fake.saveMeal(meal());

      final today = await fake.watchToday(cityId: 'edku', day: '2026-08-23').first;
      expect(today.single.name, 'محشي كرنب');
    });

    test('reports the failure it was given', () async {
      final fake = FakeDailyMealRepository(failure: const OfflineFailure());

      expect((await fake.saveMeal(meal())).failureOrNull, isA<OfflineFailure>());
    });
  });
}
