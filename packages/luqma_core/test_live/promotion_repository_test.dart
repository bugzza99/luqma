import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

import 'harness.dart';

/// Paid placements, against a real Postgres.
///
/// The asymmetry is the design: a merchant may ask, only an admin approves — and here
/// the admin is a real signed-in account, because the boundary evaluates tokens rather
/// than intentions.
void main() {
  late LiveDatabase live;
  late SupabasePromotionRepository repository;
  
  late String cityId;
  late String zoneId;
  late String merchantId;
  late String customerUid;

  setUpAll(() async {
    live = await LiveDatabase.open();
    repository = SupabasePromotionRepository(live.client);
    
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
      'type': 'restaurant',
      'name': 'مطعم',
      'zone_id': zoneId,
      'phone': '01000000000',
      'status': 'approved',
    }).select().single().then((row) => row['id'] as String);
    customerUid = await live.makeCustomer();
  });

  tearDown(() => live.dropCity(cityId));
  tearDownAll(() => live.close());

  Promotion promotion({
    PromotionStatus status = PromotionStatus.requested,
    PromotionChannel channel = PromotionChannel.homeBanner,
    DateTime? startAt,
    DateTime? endAt,
    int priority = 0,
  }) =>
      Promotion(
        id: '',
        cityId: cityId,
        merchantId: merchantId,
        channel: channel,
        status: status,
        title: 'عرض',
        startAt: startAt ?? DateTime.now(),
        endAt: endAt ?? DateTime.now().add(const Duration(days: 7)),
        requestedBy: customerUid,
        priority: priority,
      );

  group('asking', () {
    // A merchant may ask; only an admin may approve. The status is forced whatever the
    // caller claimed.
    test('a request always lands as requested', () async {
      final asked = await repository.request(
        promotion().copyWith(status: PromotionStatus.approved),
      );

      expect(asked.valueOrNull?.status, PromotionStatus.requested);
      expect(await repository.watchQueue(cityId).first, hasLength(1));
    });
  });

  group('the admin decides', () {
    test('approving puts it in front of customers once its time comes', () async {
      final asked = (await repository.request(promotion())).valueOrNull!;

      final before = await repository.watchLive(
          cityId: cityId, now: DateTime.now()).first;
      expect(before, isEmpty, reason: 'requested is not live');

      await repository.approve(asked.id, approvedBy: customerUid);

      final after =
          await repository.watchLive(cityId: cityId, now: DateTime.now()).first;
      expect(after.single.id, asked.id);
    });

    // The database refuses what the interface only checks: no reason, no rejection.
    test('a rejection without a reason is refused', () async {
      final asked = (await repository.request(promotion())).valueOrNull!;

      final result =
          await repository.reject(asked.id, reason: '  ', by: customerUid);

      expect(result.failureOrNull, isNotNull);
    });

    test('a rejection records the reason', () async {
      final asked = (await repository.request(promotion())).valueOrNull!;

      await repository.reject(
        asked.id,
        reason: 'الصورة مش مناسبة',
        by: customerUid,
      );

      expect(await repository.watchQueue(cityId).first, isEmpty);
    });
  });

  group('what is on screen', () {
    // Approved is not live: a campaign signed off today for next week must not appear
    // the moment somebody approved it.
    test('a campaign for next week is not on screen today', () async {
      final asked = (await repository.request(
        promotion(
          status: PromotionStatus.approved,
          startAt: DateTime.now().add(const Duration(days: 5)),
          endAt: DateTime.now().add(const Duration(days: 9)),
        ),
      )).valueOrNull!;
      await repository.approve(asked.id, approvedBy: customerUid);

      final now = await repository.watchLive(
          cityId: cityId, now: DateTime.now()).first;

      expect(now, isEmpty);

      final nextWeek = await repository.watchLive(
          cityId: cityId,
          now: DateTime.now().add(const Duration(days: 6))).first;

      expect(nextWeek.single.id, asked.id);
    });

    // Whoever paid more for the slot gets it.
    test('priority decides a contested slot', () async {
      final low = (await repository.request(
        promotion(status: PromotionStatus.approved, priority: 1),
      )).valueOrNull!;
      final high = (await repository.request(
        promotion(status: PromotionStatus.approved, priority: 9),
      )).valueOrNull!;
      await repository.approve(low.id, approvedBy: customerUid);
      await repository.approve(high.id, approvedBy: customerUid);

      final liveNow = await repository.watchLive(
          cityId: cityId, now: DateTime.now()).first;

      expect(liveNow.map((p) => p.id), [high.id, low.id]);
    });
  });

  group('the push cap', () {
    // Counted from what was *sent*, not what was approved. An approved campaign that
    // never went out has not spent anybody's attention.
    test('counts ended pushes since a date', () async {
      // Seeded raw in its final state: the repository's own path forces `requested`,
      // and what the cap counts is what already went out.
      Future<String> push(String status, DateTime start) async =>
          await live.client.from('promotions').insert({
            'city_id': cityId,
            'merchant_id': merchantId,
            'channel': 'push',
            'status': status,
            'title': 'دفعية',
            'start_at': start.toUtc().toIso8601String(),
            'end_at':
                start.add(const Duration(days: 1)).toUtc().toIso8601String(),
            'requested_by': customerUid,
          }).select().single().then((row) => row['id'] as String);

      await push(
        'ended',
        DateTime.now().subtract(const Duration(days: 3)),
      );
      // Approved but not sent: it has not spent anybody's attention, so it does not
      // count.
      await push('approved', DateTime.now());

      // One sent push against a limit of two leaves the slot open; against a limit of
      // one it is spent.
      expect(
        (await repository.pushSlotAvailable(cityId: cityId, limit: 2)).valueOrNull,
        isTrue,
      );
      expect(
        (await repository.pushSlotAvailable(cityId: cityId, limit: 1)).valueOrNull,
        isFalse,
      );
    });
  });
}
