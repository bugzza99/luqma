import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  OrderLine line({int unitPrice = 5000, int quantity = 1, int options = 0}) => OrderLine(
        itemId: 'i1',
        name: 'كشري',
        unitPrice: unitPrice,
        quantity: quantity,
        optionsTotal: options,
      );

  group('what the courier collects', () {
    test('items plus delivery, with nothing else added', () {
      final pricing = OrderPricing.compute(
        items: [line(unitPrice: 5000, quantity: 2)],
        deliveryFee: 1000,
      );
      expect(pricing.subtotal, 10000);
      expect(pricing.total, 11000);
    });

    test('a line carries its options into the subtotal', () {
      final pricing = OrderPricing.compute(
        items: [line(unitPrice: 5000, quantity: 2, options: 500)],
        deliveryFee: 0,
      );
      expect(pricing.subtotal, 11000, reason: '(5000 + 500) × 2');
    });

    test('an empty basket costs nothing, not just the delivery fee', () {
      final pricing = OrderPricing.compute(items: [], deliveryFee: 1000);
      expect(pricing.total, 0);
    });

    test('a discount comes off the total', () {
      final pricing = OrderPricing.compute(
        items: [line(unitPrice: 10000)],
        deliveryFee: 1000,
        coupon: const CouponAccepted(
          subtotalDiscount: 1500,
          deliveryDiscount: 0,
          platformOwesMerchant: 0,
        ),
      );
      expect(pricing.total, 9500);
    });

    test('free delivery removes the fee from the total', () {
      final pricing = OrderPricing.compute(
        items: [line(unitPrice: 10000)],
        deliveryFee: 1200,
        coupon: const CouponAccepted(
          subtotalDiscount: 0,
          deliveryDiscount: 1200,
          platformOwesMerchant: 0,
        ),
      );
      expect(pricing.total, 10000);
    });

    // A courier cannot hand money back at the door.
    test('the total can never fall below zero', () {
      final pricing = OrderPricing.compute(
        items: [line(unitPrice: 1000)],
        deliveryFee: 500,
        coupon: const CouponAccepted(
          subtotalDiscount: 5000,
          deliveryDiscount: 5000,
          platformOwesMerchant: 0,
        ),
      );
      expect(pricing.total, 0);
    });

    test('what the platform owes the merchant rides along on the order', () {
      final pricing = OrderPricing.compute(
        items: [line(unitPrice: 10000)],
        deliveryFee: 1000,
        coupon: const CouponAccepted(
          subtotalDiscount: 1500,
          deliveryDiscount: 0,
          platformOwesMerchant: 1500,
        ),
      );
      expect(pricing.platformOwesMerchant, 1500);
    });
  });

  group('who may move an order where', () {
    test('a merchant accepts a new order', () {
      expect(
        OrderStatus.placed.canMoveTo(OrderStatus.accepted, by: OrderActor.merchant),
        isTrue,
      );
    });

    test('a customer cannot accept their own order', () {
      expect(
        OrderStatus.placed.canMoveTo(OrderStatus.accepted, by: OrderActor.customer),
        isFalse,
      );
    });

    test('a customer may cancel while the merchant has not answered', () {
      expect(
        OrderStatus.placed.canMoveTo(OrderStatus.cancelled, by: OrderActor.customer),
        isTrue,
      );
    });

    // The rule the whole cancellation policy rests on: once the kitchen has started,
    // cancelling is a phone call, not a button.
    test('a customer may not cancel once the merchant has accepted', () {
      expect(
        OrderStatus.accepted.canMoveTo(OrderStatus.cancelled, by: OrderActor.customer),
        isFalse,
      );
    });

    test('a courier marks an order delivered', () {
      expect(
        OrderStatus.outForDelivery
            .canMoveTo(OrderStatus.delivered, by: OrderActor.courier),
        isTrue,
      );
    });

    test('a courier cannot skip straight to delivered from preparing', () {
      expect(
        OrderStatus.preparing.canMoveTo(OrderStatus.delivered, by: OrderActor.courier),
        isFalse,
      );
    });

    test('the system flags an unanswered order for the admin', () {
      expect(
        OrderStatus.placed
            .canMoveTo(OrderStatus.needsAttention, by: OrderActor.system),
        isTrue,
      );
    });

    test('the system cannot flag an order the merchant already accepted', () {
      expect(
        OrderStatus.accepted
            .canMoveTo(OrderStatus.needsAttention, by: OrderActor.system),
        isFalse,
      );
    });

    test('a delivered order is finished, even for the admin', () {
      expect(
        OrderStatus.delivered.canMoveTo(OrderStatus.cancelled, by: OrderActor.admin),
        isFalse,
      );
    });

    test('a cancelled order cannot be revived', () {
      expect(
        OrderStatus.cancelled.canMoveTo(OrderStatus.accepted, by: OrderActor.merchant),
        isFalse,
      );
    });

    test('an order needing attention can still be rescued by the admin', () {
      expect(
        OrderStatus.needsAttention
            .canMoveTo(OrderStatus.accepted, by: OrderActor.admin),
        isTrue,
      );
    });
  });

  group('the accept deadline', () {
    test('an instant order gets one', () {
      final deadline = Order.deadlineFor(
        type: OrderType.instant,
        placedAt: DateTime(2026, 8, 20, 13, 0),
        timeoutMinutes: 5,
      );
      expect(deadline, DateTime(2026, 8, 20, 13, 5));
    });

    // A pre-order was accepted the moment the cook published the meal, so a countdown
    // on it would flag every pre-order to the admin five minutes after it was placed.
    test('a pre-order does not', () {
      final deadline = Order.deadlineFor(
        type: OrderType.preorder,
        placedAt: DateTime(2026, 8, 20, 13, 0),
        timeoutMinutes: 5,
      );
      expect(deadline, isNull);
    });
  });
}
