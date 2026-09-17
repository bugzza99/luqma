import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  const address = Address(
    id: 'a1',
    zoneId: 'z1',
    landmarkName: 'صيدلية النور',
    street: 'شارع البحر',
  );

  Order makeOrder({
    required String id,
    required String merchantId,
    required String merchantName,
    required int total,
    OrderStatus status = OrderStatus.delivered,
    OrderActor? cancelledBy,
    DeliveryBy deliveryBy = DeliveryBy.merchant,
  }) =>
      Order(
        id: id,
        cityId: 'edku',
        orderNumber: 101,
        customerName: 'عميل',
        customerPhone: '01000000000',
        merchantId: merchantId,
        merchantName: merchantName,
        zoneId: 'z1',
        address: address,
        type: OrderType.instant,
        items: const [
          OrderLine(itemId: 'i1', name: 'وجبة', unitPrice: 1000, quantity: 1),
        ],
        pricing: OrderPricing(
          subtotal: total,
          deliveryFee: 0,
          total: total,
        ),
        status: status,
        cancelledBy: cancelledBy,
        deliveryBy: deliveryBy,
      );

  group('CourierDaySummary.fromJson', () {
    test('decodes delivered, returned, cash and shops', () {
      final json = {
        'delivered': 3,
        'returned': 1,
        // Large integer piastres decoded as num.toInt()
        'cash': 25000000000,
        'shops': [
          {
            'merchantId': 'm_fish',
            'merchantName': 'السمك',
            'platform': false,
            'delivered': 2,
            'returned': 1,
            'cash': 20000000000,
          },
          {
            'merchantId': 'm_koshari',
            'merchantName': 'الكشري',
            'platform': true,
            'delivered': 1,
            'returned': 0,
            'cash': 5000000000,
          },
        ],
      };

      final summary = CourierDaySummary.fromJson(json);

      expect(summary.delivered, 3);
      expect(summary.returned, 1);
      expect(summary.cash, 25000000000);
      expect(summary.shops.length, 2);

      final fish = summary.shops[0];
      expect(fish.merchantId, 'm_fish');
      expect(fish.merchantName, 'السمك');
      expect(fish.platform, isFalse);
      expect(fish.delivered, 2);
      expect(fish.returned, 1);
      expect(fish.cash, 20000000000);

      final koshari = summary.shops[1];
      expect(koshari.merchantId, 'm_koshari');
      expect(koshari.merchantName, 'الكشري');
      expect(koshari.platform, isTrue);
      expect(koshari.delivered, 1);
      expect(koshari.returned, 0);
      expect(koshari.cash, 5000000000);
    });

    test('handles missing or null fields gracefully', () {
      final summary = CourierDaySummary.fromJson(const {});
      expect(summary.delivered, 0);
      expect(summary.returned, 0);
      expect(summary.cash, 0);
      expect(summary.shops, isEmpty);
      expect(summary.isEmpty, isTrue);
    });
  });

  group('CourierDaySummary.of', () {
    test('aggregates deliveries, returns, and cash per shop', () {
      final orders = [
        makeOrder(
          id: 'o1',
          merchantId: 'm_fish',
          merchantName: 'السمك',
          total: 12000,
          status: OrderStatus.delivered,
        ),
        makeOrder(
          id: 'o2',
          merchantId: 'm_fish',
          merchantName: 'السمك',
          total: 8000,
          status: OrderStatus.delivered,
        ),
        makeOrder(
          id: 'o3',
          merchantId: 'm_koshari',
          merchantName: 'الكشري',
          total: 5000,
          status: OrderStatus.delivered,
        ),
        // Courier return: counts as returned, contributes no cash
        makeOrder(
          id: 'o4',
          merchantId: 'm_fish',
          merchantName: 'السمك',
          total: 9000,
          status: OrderStatus.cancelled,
          cancelledBy: OrderActor.courier,
        ),
        // Customer cancellation: not a trip the rider made
        makeOrder(
          id: 'o5',
          merchantId: 'm_fish',
          merchantName: 'السمك',
          total: 7000,
          status: OrderStatus.cancelled,
          cancelledBy: OrderActor.customer,
        ),
        // Unfinished orders: preparing / outForDelivery not counted
        makeOrder(
          id: 'o6',
          merchantId: 'm_fish',
          merchantName: 'السمك',
          total: 4000,
          status: OrderStatus.outForDelivery,
        ),
      ];

      final summary = CourierDaySummary.of(orders);

      expect(summary.delivered, 3);
      expect(summary.returned, 1);
      expect(summary.cash, 25000);
      expect(summary.shops.length, 2);

      // Sorted biggest cash first
      expect(summary.shops[0].merchantId, 'm_fish');
      expect(summary.shops[0].delivered, 2);
      expect(summary.shops[0].returned, 1);
      expect(summary.shops[0].cash, 20000);

      expect(summary.shops[1].merchantId, 'm_koshari');
      expect(summary.shops[1].delivered, 1);
      expect(summary.shops[1].returned, 0);
      expect(summary.shops[1].cash, 5000);
    });

    test('sorts shops by cash descending then merchantName ascending', () {
      final orders = [
        makeOrder(
          id: 'o1',
          merchantId: 'm_b',
          merchantName: 'ب',
          total: 5000,
        ),
        makeOrder(
          id: 'o2',
          merchantId: 'm_a',
          merchantName: 'أ',
          total: 5000,
        ),
        makeOrder(
          id: 'o3',
          merchantId: 'm_c',
          merchantName: 'ج',
          total: 10000,
        ),
      ];

      final summary = CourierDaySummary.of(orders);

      expect(summary.shops.map((s) => s.merchantName).toList(), ['ج', 'أ', 'ب']);
    });

    test('marks platform true if any order for the shop was platform delivery', () {
      final orders = [
        makeOrder(
          id: 'o1',
          merchantId: 'm1',
          merchantName: 'مطبخ أم أحمد',
          total: 5000,
          deliveryBy: DeliveryBy.merchant,
        ),
        makeOrder(
          id: 'o2',
          merchantId: 'm1',
          merchantName: 'مطبخ أم أحمد',
          total: 3000,
          deliveryBy: DeliveryBy.platform,
        ),
      ];

      final summary = CourierDaySummary.of(orders);

      expect(summary.shops.single.platform, isTrue);
    });

    test('empty orders produces empty summary', () {
      final summary = CourierDaySummary.of(const []);
      expect(summary.isEmpty, isTrue);
      expect(summary.delivered, 0);
      expect(summary.returned, 0);
      expect(summary.cash, 0);
      expect(summary.shops, isEmpty);
    });
  });
}
