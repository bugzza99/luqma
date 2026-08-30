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
    // `requested_by` is `uuid not null references auth.users`, and the merchant app was
    // sending the *merchant's* id — a row in `merchants`, which is not a row in
    // `auth.users`. Every request a merchant ever made was refused by the foreign key.
    //
    // This suite did not catch it because it supplies `customerUid` here: a valid uid
    // the app never had. The two ids are both uuids, so nothing about the shape gave it
    // away, and the assertion that existed only checked `merchantId`. Pinned now, so a
    // merchant id can never be mistaken for a person again.
    test('a merchant id is not a person, and the foreign key says so', () async {
      final refused = await repository.request(
        promotion().copyWith(requestedBy: merchantId),
      );

      expect(refused.failureOrNull, isA<ConflictFailure>(),
          reason: '23503 — merchants.id is not a row in auth.users');
      expect(await repository.watchQueue(cityId).first, isEmpty);
    });

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
      // Approved for next week, so not sent: it has spent nobody's attention yet.
      //
      // Approved and *started* does count — an approved push whose start date has passed
      // has gone out, whatever its status still says. That is the H3 fix in
      // `launch_fixes`, and it is the difference between a cap that works and one that
      // never saw a single push.
      await push('approved', DateTime.now().add(const Duration(days: 7)));

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

  // The other half of the asymmetry, and the one AdminApp had no way to reach: the owner
  // could approve and reject what merchants asked for, and could not put up a banner of
  // their own. Announcing free delivery meant signing into a merchant account to ask
  // themselves for it first.
  group('the admin putting one up', () {
    test('an admin creates one already approved', () async {
      final admin = await live.openAsAdmin();
      addTearDown(admin.dispose);
      final adminUid = admin.auth.currentUser!.id;

      final made = await SupabasePromotionRepository(admin)
          .createApproved(promotion(), approvedBy: adminUid);

      expect(made.failureOrNull, isNull);
      expect(made.valueOrNull?.status, PromotionStatus.approved);
      expect(made.valueOrNull?.approvedBy, adminUid);
      // And it is not sitting in the queue waiting for the person who just made it.
      expect(await repository.watchQueue(cityId).first, isEmpty);
    });

    // Approved is not live. A banner made today for next week must not appear the moment
    // it is saved — that is `startAt`'s question and it stays `startAt`'s question.
    test('and approved is still not live before it starts', () async {
      final admin = await live.openAsAdmin();
      addTearDown(admin.dispose);

      final now = DateTime.now();
      await SupabasePromotionRepository(admin).createApproved(
        promotion(
          startAt: now.add(const Duration(days: 3)),
          endAt: now.add(const Duration(days: 10)),
        ),
        approvedBy: admin.auth.currentUser!.id,
      );

      final live_ = await repository.watchLive(cityId: cityId, now: now).first;
      expect(live_, isEmpty, reason: 'startAt decides, not the status');
    });

    // The policy, asked directly. `merchant_requests_promotion` permits `requested` and
    // nothing else, so an owner writing `approved` is refused rather than downgraded.
    test('a merchant owner cannot put up an approved one', () async {
      final (ownerDb, ownerUid) = await live.openAsStaff(
        scope: 'merchant', role: 'owner', merchantId: merchantId);
      addTearDown(ownerDb.dispose);

      final refused = await SupabasePromotionRepository(ownerDb)
          .createApproved(promotion(), approvedBy: ownerUid);

      expect(refused.failureOrNull, isA<PermissionFailure>());
      expect(await repository.watchQueue(cityId).first, isEmpty);
    });
  });
}
