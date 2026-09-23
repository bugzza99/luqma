import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const address = Address(
    id: 'a1',
    zoneId: 'z1',
    landmarkName: 'صيدلية النور',
    street: 'شارع البحر',
    building: '12',
    floor: '3',
  );

  Order makeOrder({
    required String id,
    required String merchantId,
    required String merchantName,
    int number = 100,
    OrderStatus status = OrderStatus.preparing,
    DeliveryBy deliveryBy = DeliveryBy.merchant,
  }) =>
      Order(
        id: id,
        cityId: 'edku',
        orderNumber: number,
        customerUid: 'u1',
        customerName: 'أحمد محمود',
        customerPhone: '01000000000',
        merchantId: merchantId,
        merchantName: merchantName,
        zoneId: 'z1',
        address: address,
        type: OrderType.instant,
        items: const [
          OrderLine(itemId: 'i1', name: 'وجبة', unitPrice: 5000, quantity: 1),
        ],
        pricing: const OrderPricing(
          subtotal: 5000,
          deliveryFee: 1000,
          total: 6000,
        ),
        status: status,
        deliveryBy: deliveryBy,
      );

  group('FakeCourierOrderRepository.watchCarried', () {
    test('carries orders for attached shops only', () async {
      final fishOrder = makeOrder(
        id: 'o_fish',
        merchantId: 'm_fish',
        merchantName: 'مطعم السمك',
      );
      final koshariOrder = makeOrder(
        id: 'o_koshari',
        merchantId: 'm_koshari',
        merchantName: 'الكشري',
      );

      final repo = FakeCourierOrderRepository(
        seed: [fishOrder, koshariOrder],
        carriedMerchants: const ['m_fish'],
      );

      final carried = await repo.watchCarried().first;

      expect(carried.map((o) => o.id), ['o_fish']);
    });

    test('carries orders for multiple attached shops in one queue', () async {
      final fishOrder = makeOrder(
        id: 'o_fish',
        merchantId: 'm_fish',
        merchantName: 'مطعم السمك',
        number: 101,
      );
      final koshariOrder = makeOrder(
        id: 'o_koshari',
        merchantId: 'm_koshari',
        merchantName: 'الكشري',
        number: 102,
      );
      final pizzaOrder = makeOrder(
        id: 'o_pizza',
        merchantId: 'm_pizza',
        merchantName: 'بيتزا',
        number: 103,
      );

      final repo = FakeCourierOrderRepository(
        seed: [fishOrder, koshariOrder, pizzaOrder],
        carriedMerchants: const ['m_fish', 'm_koshari'],
      );

      final carried = await repo.watchCarried().first;

      expect(carried.map((o) => o.id), ['o_fish', 'o_koshari']);
    });

    test('carries platform orders when attached to platform (null)', () async {
      final platformOrder = makeOrder(
        id: 'o_kitchen',
        merchantId: 'm_kitchen',
        merchantName: 'أكل بيتي أم محمد',
        deliveryBy: DeliveryBy.platform,
      );
      final shopOrder = makeOrder(
        id: 'o_shop',
        merchantId: 'm_shop',
        merchantName: 'مطعم الشاطئ',
        deliveryBy: DeliveryBy.merchant,
      );

      final repo = FakeCourierOrderRepository(
        seed: [platformOrder, shopOrder],
        carriedMerchants: const [null],
      );

      final carried = await repo.watchCarried().first;

      expect(carried.map((o) => o.id), ['o_kitchen']);
    });

    test('does not carry platform orders when not attached to platform', () async {
      final platformOrder = makeOrder(
        id: 'o_kitchen',
        merchantId: 'm_kitchen',
        merchantName: 'أكل بيتي أم محمد',
        deliveryBy: DeliveryBy.platform,
      );

      final repo = FakeCourierOrderRepository(
        seed: [platformOrder],
        carriedMerchants: const ['m_other'],
      );

      final carried = await repo.watchCarried().first;

      expect(carried, isEmpty);
    });

    test('carries shop orders and platform deliveries together', () async {
      final shopOrder = makeOrder(
        id: 'o_shop',
        merchantId: 'm_fish',
        merchantName: 'مطعم السمك',
        number: 101,
      );
      final platformOrder = makeOrder(
        id: 'o_platform',
        merchantId: 'm_kitchen',
        merchantName: 'أكل بيتي أم محمد',
        number: 102,
        deliveryBy: DeliveryBy.platform,
      );
      final unattachedOrder = makeOrder(
        id: 'o_unattached',
        merchantId: 'm_pizza',
        merchantName: 'بيتزا',
        number: 103,
      );

      final repo = FakeCourierOrderRepository(
        seed: [shopOrder, platformOrder, unattachedOrder],
        carriedMerchants: const ['m_fish', null],
      );

      final carried = await repo.watchCarried().first;

      expect(carried.map((o) => o.id), ['o_shop', 'o_platform']);
    });

    test('only includes orders in preparing or outForDelivery statuses', () async {
      final preparing = makeOrder(
        id: 'o_prep',
        merchantId: 'm1',
        merchantName: 'م1',
        status: OrderStatus.preparing,
      );
      final onTheRoad = makeOrder(
        id: 'o_road',
        merchantId: 'm1',
        merchantName: 'م1',
        status: OrderStatus.outForDelivery,
      );
      final placed = makeOrder(
        id: 'o_placed',
        merchantId: 'm1',
        merchantName: 'م1',
        status: OrderStatus.placed,
      );
      final delivered = makeOrder(
        id: 'o_delivered',
        merchantId: 'm1',
        merchantName: 'م1',
        status: OrderStatus.delivered,
      );
      final cancelled = makeOrder(
        id: 'o_cancelled',
        merchantId: 'm1',
        merchantName: 'م1',
        status: OrderStatus.cancelled,
      );

      final repo = FakeCourierOrderRepository(
        seed: [preparing, onTheRoad, placed, delivered, cancelled],
        carriedMerchants: const ['m1'],
      );

      final carried = await repo.watchCarried().first;

      expect(carried.map((o) => o.id), ['o_prep', 'o_road']);
    });

    test('sorts orders by orderNumber ascending', () async {
      final later = makeOrder(
        id: 'o_late',
        merchantId: 'm1',
        merchantName: 'م1',
        number: 200,
      );
      final earlier = makeOrder(
        id: 'o_early',
        merchantId: 'm1',
        merchantName: 'م1',
        number: 100,
      );

      final repo = FakeCourierOrderRepository(
        seed: [later, earlier],
        carriedMerchants: const ['m1'],
      );

      final carried = await repo.watchCarried().first;

      expect(carried.map((o) => o.id), ['o_early', 'o_late']);
    });

    test('updates dynamically on attach and detach', () async {
      final fishOrder = makeOrder(
        id: 'o_fish',
        merchantId: 'm_fish',
        merchantName: 'مطعم السمك',
      );
      final koshariOrder = makeOrder(
        id: 'o_koshari',
        merchantId: 'm_koshari',
        merchantName: 'الكشري',
      );

      final repo = FakeCourierOrderRepository(
        seed: [fishOrder, koshariOrder],
        carriedMerchants: const ['m_fish'],
      );

      final emissions = <List<String>>[];
      final sub = repo.watchCarried().listen((orders) {
        emissions.add(orders.map((o) => o.id).toList());
      });

      // Give first event time to land
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, ['o_fish']);

      // Attach second shop
      repo.attach('m_koshari');
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, ['o_fish', 'o_koshari']);

      // Detach first shop
      repo.detach('m_fish');
      await Future<void>.delayed(Duration.zero);
      expect(emissions.last, ['o_koshari']);

      await sub.cancel();
      repo.dispose();
    });

    test('surfaces errors when repository has a failure', () async {
      final repo = FakeCourierOrderRepository(
        seed: [
          makeOrder(id: 'o1', merchantId: 'm1', merchantName: 'م1'),
        ],
        failure: const OfflineFailure(),
        carriedMerchants: const ['m1'],
      );

      expect(
        repo.watchCarried(),
        emitsError(isA<OfflineFailure>()),
      );
    });
  });

  group('FakeCourierOrderRepository.daySummary', () {
    const rider = 'rider-1';
    const other = 'rider-2';

    test('counts deliveries and cash in hand for this courier', () async {
      final repo = FakeCourierOrderRepository(
        seed: [
          makeOrder(id: 'o1', merchantId: 'm_fish', merchantName: 'السمك', status: OrderStatus.delivered)
              .copyWith(courierUid: rider, pricing: const OrderPricing(subtotal: 12000, deliveryFee: 0, total: 12000)),
          makeOrder(id: 'o2', merchantId: 'm_fish', merchantName: 'السمك', status: OrderStatus.delivered)
              .copyWith(courierUid: rider, pricing: const OrderPricing(subtotal: 8000, deliveryFee: 0, total: 8000)),
          makeOrder(id: 'o3', merchantId: 'm_koshari', merchantName: 'الكشري', status: OrderStatus.delivered)
              .copyWith(courierUid: rider, pricing: const OrderPricing(subtotal: 5000, deliveryFee: 0, total: 5000)),
        ],
        courierUid: rider,
      );

      final result = await repo.daySummary();
      final summary = result.valueOrThrow;

      expect(summary.delivered, 3);
      expect(summary.returned, 0);
      expect(summary.cash, 25000);
      expect(summary.shops.length, 2);
    });

    test('counts courier-cancelled order as return and adds no cash', () async {
      final repo = FakeCourierOrderRepository(
        seed: [
          makeOrder(id: 'o1', merchantId: 'm_fish', merchantName: 'السمك', status: OrderStatus.delivered)
              .copyWith(courierUid: rider, pricing: const OrderPricing(subtotal: 10000, deliveryFee: 0, total: 10000)),
          makeOrder(id: 'o2', merchantId: 'm_fish', merchantName: 'السمك', status: OrderStatus.cancelled)
              .copyWith(
                courierUid: rider,
                cancelledBy: OrderActor.courier,
                pricing: const OrderPricing(subtotal: 9000, deliveryFee: 0, total: 9000),
              ),
        ],
        courierUid: rider,
      );

      final result = await repo.daySummary();
      final summary = result.valueOrThrow;

      expect(summary.delivered, 1);
      expect(summary.returned, 1);
      expect(summary.cash, 10000);
    });

    test('does not count customer-cancelled order as return', () async {
      final repo = FakeCourierOrderRepository(
        seed: [
          makeOrder(id: 'o1', merchantId: 'm_fish', merchantName: 'السمك', status: OrderStatus.cancelled)
              .copyWith(
                courierUid: rider,
                cancelledBy: OrderActor.customer,
                pricing: const OrderPricing(subtotal: 7000, deliveryFee: 0, total: 7000),
              ),
        ],
        courierUid: rider,
      );

      final result = await repo.daySummary();
      final summary = result.valueOrThrow;

      expect(summary.delivered, 0);
      expect(summary.returned, 0);
      expect(summary.cash, 0);
    });

    test('never counts another rider work', () async {
      final repo = FakeCourierOrderRepository(
        seed: [
          makeOrder(id: 'o1', merchantId: 'm_fish', merchantName: 'السمك', status: OrderStatus.delivered)
              .copyWith(courierUid: other, pricing: const OrderPricing(subtotal: 30000, deliveryFee: 0, total: 30000)),
        ],
        courierUid: rider,
      );

      final result = await repo.daySummary();
      final summary = result.valueOrThrow;

      expect(summary.delivered, 0);
      expect(summary.cash, 0);
    });

    test('only counts orders from today', () async {
      final today = DateTime(2026, 9, 25, 14, 0);
      final past = DateTime(2020, 1, 1, 10, 0);

      final repo = FakeCourierOrderRepository(
        seed: [
          makeOrder(id: 'o_today', merchantId: 'm_fish', merchantName: 'السمك', status: OrderStatus.delivered)
              .copyWith(courierUid: rider, deliveredAt: today, pricing: const OrderPricing(subtotal: 5000, deliveryFee: 0, total: 5000)),
          makeOrder(id: 'o_past', merchantId: 'm_fish', merchantName: 'السمك', status: OrderStatus.delivered)
              .copyWith(courierUid: rider, deliveredAt: past, pricing: const OrderPricing(subtotal: 40000, deliveryFee: 0, total: 40000)),
        ],
        courierUid: rider,
        now: () => today,
      );

      final result = await repo.daySummary();
      final summary = result.valueOrThrow;

      expect(summary.delivered, 1);
      expect(summary.cash, 5000);
    });

    test('splits by shop, biggest cash first', () async {
      final repo = FakeCourierOrderRepository(
        seed: [
          makeOrder(id: 'o1', merchantId: 'm_koshari', merchantName: 'الكشري', status: OrderStatus.delivered)
              .copyWith(courierUid: rider, pricing: const OrderPricing(subtotal: 5000, deliveryFee: 0, total: 5000)),
          makeOrder(id: 'o2', merchantId: 'm_fish', merchantName: 'السمك', status: OrderStatus.delivered)
              .copyWith(courierUid: rider, pricing: const OrderPricing(subtotal: 20000, deliveryFee: 0, total: 20000)),
        ],
        courierUid: rider,
      );

      final result = await repo.daySummary();
      final summary = result.valueOrThrow;

      expect(summary.shops.length, 2);
      expect(summary.shops[0].merchantName, 'السمك');
      expect(summary.shops[0].cash, 20000);
      expect(summary.shops[1].merchantName, 'الكشري');
      expect(summary.shops[1].cash, 5000);
    });

    test('rider who did nothing today gets empty summary', () async {
      final repo = FakeCourierOrderRepository(
        seed: const [],
        courierUid: rider,
      );

      final result = await repo.daySummary();
      final summary = result.valueOrThrow;

      expect(summary.isEmpty, isTrue);
      expect(summary.delivered, 0);
      expect(summary.returned, 0);
      expect(summary.cash, 0);
      expect(summary.shops, isEmpty);
    });

    test('surfaces errors when repository has a failure', () async {
      final repo = FakeCourierOrderRepository(
        failure: const OfflineFailure(),
        courierUid: rider,
      );

      final result = await repo.daySummary();
      expect(result.failureOrNull, isA<OfflineFailure>());
    });
  });

  /// The real pre-check, with the database replaced by a canned row. A reply that died on
  /// the way back leaves a write queued that has already committed; its replay reads the
  /// order where that write put it, and until now called that a conflict.
  group('a replay of a write that already landed settles instead of rejecting', () {
    Map<String, dynamic> row({
      required String status,
      String? courierUid,
      String deliveryBy = 'merchant',
      String? cancelledBy,
    }) =>
        {
          'id': 'o1',
          'city_id': 'edku',
          'order_number': 101,
          'customer_uid': 'u1',
          'customer_name': 'أحمد',
          'customer_phone': '01000000000',
          'merchant_id': 'm1',
          'merchant_name': 'مطعم',
          'zone_id': 'z1',
          'delivery_by': deliveryBy,
          'type': 'instant',
          'items': <Object>[],
          'pricing': {'subtotal': 5000, 'deliveryFee': 1000, 'total': 6000},
          'status': status,
          'courier_uid': courierUid,
          'cancelled_by': cancelledBy,
        };

    /// A repository reading [order], acting as [me], and recording every write it sends.
    (SupabaseCourierOrderRepository, List<String>) against(
      Map<String, dynamic> order, {
      required String me,
    }) {
      final writes = <String>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async {
          if (request.method != 'GET') writes.add(request.method);
          final wantsObject =
              request.headers['Accept']?.contains('vnd.pgrst.object') ?? false;
          return http.Response(
            jsonEncode(
              request.method == 'GET'
                  ? (wantsObject ? order : [order])
                  : [
                      {'id': 'o1'},
                    ],
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      return (SupabaseCourierOrderRepository(client, currentUid: () => me), writes);
    }

    test('delivered, carried by this courier, is success and sends nothing', () async {
      final (repo, writes) =
          against(row(status: 'delivered', courierUid: 'c1'), me: 'c1');

      expect((await repo.markDelivered('o1')).isOk, isTrue);
      expect(writes, isEmpty, reason: 'there is nothing left to write');
    });

    test("delivered on a shop's order nobody's name went out on is its rider's",
        () async {
      final (repo, _) = against(row(status: 'delivered'), me: 'c1');
      expect((await repo.markDelivered('o1')).isOk, isTrue);
    });

    test('delivered by another courier stays a conflict', () async {
      final (repo, writes) =
          against(row(status: 'delivered', courierUid: 'c2'), me: 'c1');

      expect((await repo.markDelivered('o1')).failureOrNull, isA<ConflictFailure>());
      expect(writes, isEmpty);
    });

    test('a platform order delivered with nobody on it is nobody\'s to claim', () async {
      final (repo, _) =
          against(row(status: 'delivered', deliveryBy: 'platform'), me: 'c1');
      expect((await repo.markDelivered('o1')).failureOrNull, isA<ConflictFailure>());
    });

    test('out with this courier on it is success; with another it is a conflict',
        () async {
      final (mine, _) =
          against(row(status: 'outForDelivery', courierUid: 'c1'), me: 'c1');
      expect((await mine.markOnTheWay('o1', courierUid: 'c1')).isOk, isTrue);

      final (theirs, _) =
          against(row(status: 'outForDelivery', courierUid: 'c2'), me: 'c1');
      expect((await theirs.markOnTheWay('o1', courierUid: 'c1')).failureOrNull,
          isA<ConflictFailure>());
    });

    test('a return this courier recorded is success; the shop\'s is a conflict',
        () async {
      final (mine, _) = against(
        row(status: 'cancelled', courierUid: 'c1', cancelledBy: 'courier'),
        me: 'c1',
      );
      expect((await mine.markFailed('o1', reason: 'مفيش حد')).isOk, isTrue);

      final (shop, _) = against(
        row(status: 'cancelled', courierUid: 'c1', cancelledBy: 'merchant'),
        me: 'c1',
      );
      expect((await shop.markFailed('o1', reason: 'مفيش حد')).failureOrNull,
          isA<ConflictFailure>());
    });

    test('a delivery that finds a return is a conflict', () async {
      final (repo, _) = against(
        row(status: 'cancelled', courierUid: 'c1', cancelledBy: 'courier'),
        me: 'c1',
      );
      expect((await repo.markDelivered('o1')).failureOrNull, isA<ConflictFailure>());
    });

    test('an order still waiting is written, as before', () async {
      final (repo, writes) =
          against(row(status: 'outForDelivery', courierUid: 'c1'), me: 'c1');

      expect((await repo.markDelivered('o1')).isOk, isTrue);
      expect(writes, ['PATCH']);
    });
  });
}
