import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// Home kitchens, against a real Postgres.
///
/// The port of `test/daily_meal_repository_test.dart`. The `yyyy-MM-dd` day key retires
/// here — the column is a real date and equality does what it always should have — but
/// the model keeps its string, because a day key reads correctly on a screen.
void main() {
  late LiveDatabase live;
  late SupabaseDailyMealRepository repository;
  late String cityId;
  late String zoneId;
  late String merchantId;
  late String otherMerchantId;

  setUpAll(() async {
    live = await LiveDatabase.open();
    repository = SupabaseDailyMealRepository(live.client);
  });

  setUp(() async {
    cityId = await live.makeCity();
    zoneId = await live.client
        .from('zones')
        .insert({'city_id': cityId, 'name': 'المعمورة'})
        .select()
        .single()
        .then((row) => row['id'] as String);
    merchantId = await live.client.from('merchants').insert({
      'city_id': cityId,
      'type': 'homeKitchen',
      'name': 'مطبخ أم محمد',
      'zone_id': zoneId,
      'phone': '01000000000',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);
    otherMerchantId = await live.client.from('merchants').insert({
      'city_id': cityId,
      'type': 'homeKitchen',
      'name': 'مطبخ تاني',
      'zone_id': zoneId,
      'phone': '01000000001',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);
  });

  tearDown(() => live.dropCity(cityId));
  tearDownAll(() => live.close());

  DailyMeal meal({
    String id = '',
    String? merchantIdOverride,
    String date = '2026-08-23',
    int remainingQty = 8,
    int totalQty = 20,
    DailyMealStatus status = DailyMealStatus.published,
  }) =>
      DailyMeal(
        id: id,
        merchantId: merchantIdOverride ?? merchantId,
        cityId: cityId,
        name: 'محشي كرنب',
        price: 9000,
        date: date,
        totalQty: totalQty,
        remainingQty: remainingQty,
        // Open all day: see the note in order_repository_test — a fixed afternoon
        // window makes a test that is not about the hour fail after four o'clock.
        pickupWindowStart: 0,
        pickupWindowEnd: 24 * 60 - 1,
        status: status,
      );

  group('publishing', () {
    test('a new meal gets an id and comes back', () async {
      final saved = await repository.saveMeal(meal());

      expect(saved.valueOrNull?.id, isNotEmpty);
      final today =
          await repository.watchToday(cityId: cityId, day: '2026-08-23').first;
      expect(today.single.name, 'محشي كرنب');
    });

    test('editing does not create a second one', () async {
      final created = (await repository.saveMeal(meal())).valueOrNull!;

      await repository.saveMeal(created.copyWith(name: 'محشي ورق عنب'));

      final today =
          await repository.watchToday(cityId: cityId, day: '2026-08-23').first;
      expect(today, hasLength(1));
      expect(today.single.name, 'محشي ورق عنب');
    });

    // The count is the server's to move. A kitchen that could write it could sell the
    // same portion twice, which is the one thing this whole table exists to stop.
    test('saving an existing meal cannot rewrite what is left', () async {
      final created =
          (await repository.saveMeal(meal(remainingQty: 8))).valueOrNull!;

      await repository.saveMeal(created.copyWith(remainingQty: 999, totalQty: 999));

      final today =
          await repository.watchToday(cityId: cityId, day: '2026-08-23').first;
      expect(today.single.remainingQty, 8);
    });

    // Raising the count on a *new* meal is just deciding how much to cook. And the
    // database refuses nonsense the old rules never saw: more remaining than were
    // ever cooked fails a CHECK, not a code review.
    test('a new meal sets its own count', () async {
      final created = (await repository.saveMeal(
        meal(remainingQty: 30, totalQty: 30),
      )).valueOrNull!;

      expect(created.remainingQty, 30);
    });
  });

  group('what a customer sees today', () {
    test('published meals for today, in this city', () async {
      await repository.saveMeal(meal());
      await repository.saveMeal(meal(date: '2026-08-22'));
      await repository.saveMeal(meal(status: DailyMealStatus.draft));

      final today =
          await repository.watchToday(cityId: cityId, day: '2026-08-23').first;

      expect(today, hasLength(1));
    });

    // Sold out still shows. A section that quietly loses a meal at eight o'clock makes
    // the whole thing look like it was never there — and "خلص" is information: it is
    // what teaches somebody to order earlier tomorrow.
    test('a sold-out meal is still shown', () async {
      await repository.saveMeal(meal(remainingQty: 0));

      final today =
          await repository.watchToday(cityId: cityId, day: '2026-08-23').first;

      expect(today.single.isSoldOut, isTrue);
    });

    test('a closed meal is not', () async {
      await repository.saveMeal(meal(status: DailyMealStatus.closed));

      expect(
        await repository.watchToday(cityId: cityId, day: '2026-08-23').first,
        isEmpty,
      );
    });
  });

  group("one kitchen's own", () {
    test('sees its drafts as well as what is published, newest day first', () async {
      await repository.saveMeal(
        meal(status: DailyMealStatus.draft, date: '2026-08-20'),
      );
      await repository.saveMeal(meal(date: '2026-08-23'));
      await repository.saveMeal(meal(merchantIdOverride: otherMerchantId));

      final mine = await repository.watchForMerchant(merchantId).first;

      expect(mine.map((m) => m.date), ['2026-08-23', '2026-08-20']);
    });
  });

  group('closing one early', () {
    test("takes it off the customer's screen without touching the count", () async {
      final created = (await repository.saveMeal(meal())).valueOrNull!;

      await repository.setStatus(created.id, DailyMealStatus.closed);

      expect(
        await repository.watchToday(cityId: cityId, day: '2026-08-23').first,
        isEmpty,
      );
      final mine = await repository.watchForMerchant(merchantId).first;
      expect(mine.single.remainingQty, 8);
    });
  });

  group('the fake', () {
    test('publishes and finds today the same way', () async {
      final fake = FakeDailyMealRepository();

      await fake.saveMeal(meal());

      final today =
          await fake.watchToday(cityId: cityId, day: '2026-08-23').first;
      expect(today.single.name, 'محشي كرنب');
    });

    test('reports the failure it was given', () async {
      final fake = FakeDailyMealRepository(failure: const OfflineFailure());

      expect((await fake.saveMeal(meal())).failureOrNull, isA<OfflineFailure>());
    });
  });
}
