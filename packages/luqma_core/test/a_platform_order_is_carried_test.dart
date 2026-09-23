import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The fakes refuse what `20261101020000_a_platform_order_is_carried_by_somebody.sql`
/// refuses: a shop sending a platform order out, and anybody delivering a platform order
/// nobody is on. A fake that allowed either would let a screen pass its tests against a
/// state production can no longer reach.
void main() {
  Order order({
    required OrderStatus status,
    DeliveryBy deliveryBy = DeliveryBy.platform,
    String? courierUid,
  }) =>
      Order(
        id: 'o1',
        cityId: 'edku',
        orderNumber: 100,
        customerUid: 'u1',
        customerName: 'أحمد محمود',
        customerPhone: '01000000000',
        merchantId: 'm1',
        merchantName: 'مطعم السمك',
        zoneId: 'z1',
        type: OrderType.instant,
        items: const [
          OrderLine(itemId: 'i1', name: 'وجبة', unitPrice: 5000, quantity: 1),
        ],
        pricing: const OrderPricing(subtotal: 5000, deliveryFee: 1000, total: 6000),
        status: status,
        deliveryBy: deliveryBy,
        courierUid: courierUid,
      );

  group('FakeMerchantOrderRepository.advance', () {
    test('refuses sending out an order a platform courier has to take', () async {
      final repo = FakeMerchantOrderRepository(
        seed: [order(status: OrderStatus.preparing)],
      );

      final result = await repo.advance('o1', to: OrderStatus.outForDelivery);

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo['o1']!.status, OrderStatus.preparing);
    });

    test("still sends out an order the shop's own rider carries", () async {
      final repo = FakeMerchantOrderRepository(
        seed: [order(status: OrderStatus.preparing, deliveryBy: DeliveryBy.merchant)],
      );

      final result = await repo.advance('o1', to: OrderStatus.outForDelivery);

      expect(result.failureOrNull, isNull);
      expect(repo['o1']!.status, OrderStatus.outForDelivery);
    });
  });

  group('FakeCourierOrderRepository.markDelivered', () {
    test('refuses a platform order nobody is on', () async {
      final repo = FakeCourierOrderRepository(
        seed: [order(status: OrderStatus.outForDelivery)],
      );

      final result = await repo.markDelivered('o1');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repo['o1']!.status, OrderStatus.outForDelivery);
    });

    test('delivers one the courier took on the way out', () async {
      final repo = FakeCourierOrderRepository(
        seed: [order(status: OrderStatus.preparing)],
      );

      await repo.markOnTheWay('o1', courierUid: 'rider-1');
      final result = await repo.markDelivered('o1');

      expect(result.failureOrNull, isNull);
      expect(repo['o1']!.status, OrderStatus.delivered);
      expect(repo['o1']!.courierUid, 'rider-1');
    });
  });
}
