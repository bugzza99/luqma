import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The complaints assistant answers from the order itself, never from a script that
/// guesses. Each case here is a real question a customer asks, and what the order it is
/// about actually says.
void main() {
  final now = DateTime(2026, 9, 19, 14, 0);

  Order order({
    OrderStatus status = OrderStatus.placed,
    DateTime? placedAt,
    DateTime? acceptDeadlineAt,
    DateTime? deliveredAt,
    String? cancelReason,
    OrderPricing pricing = const OrderPricing(
      subtotal: 15000,
      deliveryFee: 1500,
      total: 16500,
    ),
  }) =>
      Order(
        id: 'o1',
        cityId: 'edku',
        orderNumber: 42,
        customerUid: 'u1',
        customerName: 'منى',
        customerPhone: '01000000000',
        merchantId: 'm1',
        merchantName: 'مطعم البحر',
        zoneId: 'z1',
        type: OrderType.instant,
        items: const [],
        pricing: pricing,
        status: status,
        placedAt: placedAt ?? now.subtract(const Duration(minutes: 5)),
        acceptDeadlineAt: acceptDeadlineAt,
        deliveredAt: deliveredAt,
        cancelReason: cancelReason,
      );

  group('late', () {
    test('a shop that has not answered yet, with time left, says how long is left', () {
      final reply = OrderHelper.answer(
        HelpTopic.late,
        order(acceptDeadlineAt: now.add(const Duration(minutes: 3))),
        now,
      );
      expect(reply.text, contains('مطعم البحر'));
      expect(reply.text, contains('3'));
      expect(reply.actions, contains(HelpAction.cancelOrder));
    });

    test('a shop past its deadline says the team already knows, and offers cancelling', () {
      final reply = OrderHelper.answer(
        HelpTopic.late,
        order(acceptDeadlineAt: now.subtract(const Duration(minutes: 1))),
        now,
      );
      expect(reply.text, contains('فريق لقمة'));
      expect(reply.actions, contains(HelpAction.cancelOrder));
    });

    test('an order on the road offers the shop phone and a complaint, not cancelling', () {
      final reply = OrderHelper.answer(
        HelpTopic.late,
        order(status: OrderStatus.outForDelivery),
        now,
      );
      expect(reply.text, contains('في الطريق'));
      expect(reply.actions, containsAll([HelpAction.callShop, HelpAction.complain]));
      expect(reply.actions, isNot(contains(HelpAction.cancelOrder)));
    });

    test('an order marked delivered that never came is a complaint straight away', () {
      final reply = OrderHelper.answer(
        HelpTopic.late,
        order(status: OrderStatus.delivered, deliveredAt: DateTime(2026, 9, 19, 13, 40)),
        now,
      );
      expect(reply.text, contains('1:40'));
      expect(reply.actions.first, HelpAction.complain);
    });
  });

  group('cancel', () {
    test('while the shop has not answered, cancelling is offered', () {
      final reply = OrderHelper.answer(HelpTopic.cancel, order(), now);
      expect(reply.actions, contains(HelpAction.cancelOrder));
    });

    test('once the kitchen has started, it says why not and offers the shop', () {
      final reply = OrderHelper.answer(
        HelpTopic.cancel,
        order(status: OrderStatus.preparing),
        now,
      );
      expect(reply.actions, isNot(contains(HelpAction.cancelOrder)));
      expect(reply.actions, contains(HelpAction.callShop));
    });

    test('a cancelled order says so, with the reason', () {
      final reply = OrderHelper.answer(
        HelpTopic.cancel,
        order(status: OrderStatus.cancelled, cancelReason: 'المطعم قفل بدري'),
        now,
      );
      expect(reply.text, contains('المطعم قفل بدري'));
      expect(reply.actions, isNot(contains(HelpAction.cancelOrder)));
    });
  });

  test('money reads the bill back in pounds, discount included', () {
    final reply = OrderHelper.answer(
      HelpTopic.money,
      order(
        pricing: const OrderPricing(
          subtotal: 15000,
          deliveryFee: 1500,
          subtotalDiscount: 2000,
          total: 14500,
        ),
      ),
      now,
    );
    expect(reply.text, contains('150 ج'));
    expect(reply.text, contains('15 ج'));
    expect(reply.text, contains('20 ج'));
    expect(reply.text, contains('145 ج'));
    expect(reply.text, isNot(contains('14500')));
    expect(reply.actions, contains(HelpAction.complain));
  });

  test('a missing item before the food has arrived asks to wait and check', () {
    final reply = OrderHelper.answer(
      HelpTopic.wrongItems,
      order(status: OrderStatus.preparing),
      now,
    );
    expect(reply.actions, contains(HelpAction.callShop));
  });

  test('a missing item after delivery goes to a complaint with the topic on it', () {
    final reply = OrderHelper.answer(
      HelpTopic.wrongItems,
      order(status: OrderStatus.delivered),
      now,
    );
    expect(reply.actions.first, HelpAction.complain);
    expect(OrderHelper.complaintText(HelpTopic.wrongItems, 'ناقص عيش'),
        'ناقص صنف أو غلط في الطلب: ناقص عيش');
  });

  test('a complaint with nothing typed still says what it is about', () {
    expect(OrderHelper.complaintText(HelpTopic.late, '  '), 'الأوردر اتأخر');
  });
}
