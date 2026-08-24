import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Asking for a placement, approving one, and finding what is live.
void main() {
  late FakeFirebaseFirestore firestore;
  late FirestorePromotionRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = FirestorePromotionRepository(firestore);
  });

  final now = DateTime(2026, 8, 24, 12);

  Promotion promotion({
    String id = '',
    String merchantId = 'm1',
    PromotionChannel channel = PromotionChannel.homeBanner,
    PromotionStatus status = PromotionStatus.active,
    DateTime? startAt,
    DateTime? endAt,
    String? sectionKey,
    List<String> zoneIds = const [],
    int priority = 0,
  }) =>
      Promotion(
        id: id,
        cityId: 'edku',
        merchantId: merchantId,
        channel: channel,
        status: status,
        title: 'خصم',
        sectionKey: sectionKey,
        zoneIds: zoneIds,
        startAt: startAt ?? DateTime(2026, 8, 1),
        endAt: endAt ?? DateTime(2026, 9, 1),
        priority: priority,
        requestedBy: 'owner1',
      );

  group('asking for one', () {
    // A merchant may ask; only an admin may approve. That is what keeps unmoderated push
    // off every customer's phone, and it is enforced in the rules as well as here.
    test('a merchant request always lands as requested, whatever it claims', () async {
      final saved = await repository.request(
        promotion(status: PromotionStatus.active),
      );

      expect(saved.valueOrNull?.status, PromotionStatus.requested);
    });

    test('it gets an id and shows up in the queue', () async {
      await repository.request(promotion());

      final queue = await repository.watchQueue('edku').first;
      expect(queue.single.merchantId, 'm1');
    });
  });

  group('the admin queue', () {
    test('holds what is waiting, and nothing that was already decided', () async {
      await repository.request(promotion());
      await firestore.collection('promotions').doc('done').set(
            promotion(status: PromotionStatus.active).toJson()..remove('id'),
          );

      final queue = await repository.watchQueue('edku').first;

      expect(queue, hasLength(1));
      expect(queue.single.status, PromotionStatus.requested);
    });

    test('approving names who did it', () async {
      final asked = (await repository.request(promotion())).valueOrNull!;

      await repository.approve(asked.id, approvedBy: 'admin1');

      final live = await repository.watchLive(cityId: 'edku', now: now).first;
      expect(live.single.approvedBy, 'admin1');
    });

    // A refusal with no reason gives the merchant nothing to fix and guarantees they
    // ask again with the same thing.
    test('rejecting needs a reason', () async {
      final asked = (await repository.request(promotion())).valueOrNull!;

      final result = await repository.reject(asked.id, reason: '  ', by: 'admin1');

      expect(result.failureOrNull, isNotNull);
      expect(await repository.watchQueue('edku').first, hasLength(1));
    });

    test('a rejected one leaves the queue and never goes live', () async {
      final asked = (await repository.request(promotion())).valueOrNull!;

      await repository.reject(asked.id, reason: 'الصورة مش واضحة', by: 'admin1');

      expect(await repository.watchQueue('edku').first, isEmpty);
      expect(await repository.watchLive(cityId: 'edku', now: now).first, isEmpty);
    });
  });

  group('what is live', () {
    Future<void> put(String id, Promotion p) =>
        firestore.collection('promotions').doc(id).set(p.toJson()..remove('id'));

    test('an approved campaign inside its dates', () async {
      await put('live', promotion(status: PromotionStatus.approved));

      final live = await repository.watchLive(cityId: 'edku', now: now).first;
      expect(live.map((p) => p.id), ['live']);
    });

    test('never one still waiting for approval', () async {
      await put('waiting', promotion(status: PromotionStatus.requested));

      expect(await repository.watchLive(cityId: 'edku', now: now).first, isEmpty);
    });

    test('never one whose dates have passed', () async {
      await put(
        'over',
        promotion(startAt: DateTime(2026, 7, 1), endAt: DateTime(2026, 8, 1)),
      );

      expect(await repository.watchLive(cityId: 'edku', now: now).first, isEmpty);
    });

    // Whoever paid more for the slot gets it. Without an order, a contested slot would
    // show whichever document Firestore happened to return first.
    test('the higher priority comes first', () async {
      await put('low', promotion(priority: 1));
      await put('high', promotion(priority: 9));

      final live = await repository.watchLive(cityId: 'edku', now: now).first;
      expect(live.map((p) => p.id), ['high', 'low']);
    });
  });

  group('what a merchant can see of their own', () {
    test('every campaign they asked for, whatever became of it', () async {
      await repository.request(promotion());
      final rejected = (await repository.request(promotion())).valueOrNull!;
      await repository.reject(rejected.id, reason: 'مش مناسب', by: 'admin1');
      await repository.request(promotion(merchantId: 'm2'));

      final mine = await repository.watchForMerchant('m1').first;

      expect(mine, hasLength(2));
    });
  });

  group('the weekly push cap', () {
    // Unmoderated, uncapped push is the fastest way to make customers disable
    // notifications — and the operational channel goes with it.
    test('counts only pushes actually sent this week', () async {
      await firestore.collection('promotions').doc('sent').set(
            promotion(
              channel: PromotionChannel.push,
              status: PromotionStatus.ended,
              startAt: now.subtract(const Duration(days: 2)),
              endAt: now.subtract(const Duration(days: 2)),
            ).toJson()
              ..remove('id'),
          );
      await firestore.collection('promotions').doc('old').set(
            promotion(
              channel: PromotionChannel.push,
              status: PromotionStatus.ended,
              startAt: now.subtract(const Duration(days: 20)),
              endAt: now.subtract(const Duration(days: 20)),
            ).toJson()
              ..remove('id'),
          );
      await firestore.collection('promotions').doc('banner').set(
            promotion(status: PromotionStatus.active).toJson()..remove('id'),
          );

      final sent = await repository.pushesSentSince(
        cityId: 'edku',
        since: now.subtract(const Duration(days: 7)),
      );

      expect(sent.valueOrNull, 1);
    });
  });

  group('the fake', () {
    test('requests and approves the same way', () async {
      final fake = FakePromotionRepository();

      final asked = (await fake.request(promotion())).valueOrNull!;
      expect(asked.status, PromotionStatus.requested);

      await fake.approve(asked.id, approvedBy: 'admin1');

      expect(
        (await fake.watchLive(cityId: 'edku', now: now).first).single.approvedBy,
        'admin1',
      );
    });

    test('reports the failure it was given', () async {
      final fake = FakePromotionRepository(failure: const OfflineFailure());

      expect((await fake.request(promotion())).failureOrNull, isA<OfflineFailure>());
    });
  });
}
