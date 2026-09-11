import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  group('CourierRosterItem', () {
    test('isAvailableAt delegates to StaffMember and mirrors pausedUntil', () {
      final now = DateTime(2026, 9, 23, 14, 0);

      // Null pausedUntil means available.
      const unpaused = CourierRosterItem(
        id: 'cm-1',
        courierUid: 'c-1',
        merchantId: 'm-1',
        isActive: true,
        pausedUntil: null,
      );
      expect(unpaused.isAvailableAt(now), isTrue);

      // Past pausedUntil means available.
      final pastPaused = CourierRosterItem(
        id: 'cm-2',
        courierUid: 'c-2',
        merchantId: 'm-1',
        isActive: true,
        pausedUntil: now.subtract(const Duration(minutes: 5)),
      );
      expect(pastPaused.isAvailableAt(now), isTrue);

      // Future pausedUntil means paused (not available).
      final futurePaused = CourierRosterItem(
        id: 'cm-3',
        courierUid: 'c-3',
        merchantId: 'm-1',
        isActive: true,
        pausedUntil: now.add(const Duration(minutes: 30)),
      );
      expect(futurePaused.isAvailableAt(now), isFalse);
    });

    test('fromRow decodes joined staff data and dates', () {
      final row = {
        'id': 'cm-10',
        'courier_uid': 'c-10',
        'merchant_id': 'm-1',
        'is_active': true,
        'attached_at': '2026-09-23T10:00:00.000Z',
        'staff': {
          'uid': 'c-10',
          'name': 'محمود الكابتن',
          'phone': '01000000002',
          'paused_until': '2026-09-23T16:00:00.000Z',
        },
      };

      final item = CourierRosterItem.fromRow(row);
      expect(item.id, 'cm-10');
      expect(item.courierUid, 'c-10');
      expect(item.merchantId, 'm-1');
      expect(item.isActive, isTrue);
      expect(item.name, 'محمود الكابتن');
      expect(item.phone, '01000000002');
      expect(item.attachedAt, isNotNull);
      expect(item.pausedUntil, isNotNull);
    });

    test('fromRow decodes direct fields without nested staff', () {
      final row = {
        'id': 'cm-11',
        'courier_uid': 'c-11',
        'merchant_id': 'm-2',
        'is_active': true,
        'name': 'علي',
        'phone': '01011111111',
      };

      final item = CourierRosterItem.fromRow(row);
      expect(item.id, 'cm-11');
      expect(item.name, 'علي');
      expect(item.phone, '01011111111');
    });
  });

  group('FakeCourierRosterRepository', () {
    const shopId = 'shop-fish';
    const otherShopId = 'shop-koshari';

    late FakeCourierRosterRepository repo;

    setUp(() {
      repo = FakeCourierRosterRepository(
        seed: [
          const CourierRosterItem(
            id: 'cm-1',
            courierUid: 'c-1',
            merchantId: shopId,
            isActive: true,
            name: 'أحمد',
            phone: '01000000001',
          ),
          const CourierRosterItem(
            id: 'cm-2',
            courierUid: 'c-2',
            merchantId: shopId,
            isActive: false, // Detached!
            name: 'محمود',
            phone: '01000000002',
          ),
          const CourierRosterItem(
            id: 'cm-3',
            courierUid: 'c-3',
            merchantId: otherShopId,
            isActive: true,
            name: 'كريم',
            phone: '01000000003',
          ),
        ],
        staffByPhone: {
          '01000000001': const StaffMember(
            uid: 'c-1',
            scope: 'merchant',
            role: 'courier',
            isActive: true,
            name: 'أحمد',
            phone: '01000000001',
          ),
          '01000000002': const StaffMember(
            uid: 'c-2',
            scope: 'merchant',
            role: 'courier',
            isActive: true,
            name: 'محمود',
            phone: '01000000002',
          ),
          '01000000004': const StaffMember(
            uid: 'c-4',
            scope: 'merchant',
            role: 'courier',
            isActive: true,
            name: 'طارق',
            phone: '01000000004',
          ),
        },
      );
    });

    test('watchRoster and getRoster only return active couriers for this shop', () async {
      final initial = (await repo.getRoster(shopId)).valueOrNull!;
      expect(initial.map((i) => i.courierUid), ['c-1']);

      final streamItems = await repo.watchRoster(shopId).first;
      expect(streamItems.map((i) => i.courierUid), ['c-1']);
    });

    test('attachCourier adds a new courier and notifies listeners', () async {
      final streamFuture = repo.watchRoster(shopId).take(2).toList();

      final result = await repo.attachCourier(
        merchantId: shopId,
        phone: '01000000004',
      );

      expect(result.isOk, isTrue);
      final attached = result.valueOrNull!;
      expect(attached.courierUid, 'c-4');
      expect(attached.name, 'طارق');
      expect(attached.isActive, isTrue);

      final emissions = await streamFuture;
      expect(emissions.first.map((i) => i.courierUid), ['c-1']);
      expect(emissions.last.map((i) => i.courierUid), ['c-1', 'c-4']);
    });

    test('attachCourier re-activates a detached courier rather than duplicating', () async {
      final result = await repo.attachCourier(
        merchantId: shopId,
        phone: '01000000002',
      );

      expect(result.isOk, isTrue);
      final attached = result.valueOrNull!;
      expect(attached.id, 'cm-2', reason: 're-uses the existing attachment row');
      expect(attached.courierUid, 'c-2');
      expect(attached.isActive, isTrue);

      // Verify no duplicate row created
      final roster = (await repo.getRoster(shopId)).valueOrNull!;
      expect(roster.where((i) => i.courierUid == 'c-2').length, 1);
    });

    test('attachCourier normalizes Arabic-Indic digits', () async {
      final result = await repo.attachCourier(
        merchantId: shopId,
        phone: '٠١٠٠٠٠٠٠٠٠٤',
      );
      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.courierUid, 'c-4');
    });

    test('attachCourier refuses a phone that belongs to no active courier', () async {
      final result = await repo.attachCourier(
        merchantId: shopId,
        phone: '01099999999',
      );
      expect(result.isOk, isFalse);
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('detachCourier deactivates the courier and removes from watchRoster', () async {
      final streamFuture = repo.watchRoster(shopId).take(2).toList();

      final detachResult = await repo.detachCourier(
        merchantId: shopId,
        courierUid: 'c-1',
      );
      expect(detachResult.isOk, isTrue);

      final emissions = await streamFuture;
      expect(emissions.first.map((i) => i.courierUid), ['c-1']);
      expect(emissions.last, isEmpty);

      // Still exists in all, but inactive
      final allItems = repo.all;
      final c1 = allItems.firstWhere((i) => i.courierUid == 'c-1');
      expect(c1.isActive, isFalse);
    });

    test('detachCourier returns NotFoundFailure if attachment not found', () async {
      final result = await repo.detachCourier(
        merchantId: shopId,
        courierUid: 'unknown-rider',
      );
      expect(result.isOk, isFalse);
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('surfaces failures correctly', () async {
      repo.failure = const OfflineFailure();
      expect((await repo.getRoster(shopId)).failureOrNull, isA<OfflineFailure>());
      expect(
        (await repo.attachCourier(merchantId: shopId, phone: '01000000001')).failureOrNull,
        isA<OfflineFailure>(),
      );
      expect(
        (await repo.detachCourier(merchantId: shopId, courierUid: 'c-1')).failureOrNull,
        isA<OfflineFailure>(),
      );
    });
  });
}
