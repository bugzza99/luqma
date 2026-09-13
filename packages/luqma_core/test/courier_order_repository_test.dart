import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

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
}
