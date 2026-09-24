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
    int? prepMinutes,
    List<Map<String, dynamic>> history = const [],
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
        prepMinutes: prepMinutes,
        statusHistory: history,
      );

  /// A history entry moving the order to [to], [ago] before [now].
  Map<String, dynamic> moved(String to, Duration ago) => {
        'from': 'placed',
        'to': to,
        'by': 'merchant',
        'at': now.subtract(ago).toIso8601String(),
      };

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

    // The owner, 2026-09-24: زعتر sent everybody to the team. An order that left twenty
    // minutes ago is on time, and the answer is the time — not a complaint form.
    test('an order just on the road says when it left, and asks nobody to complain', () {
      final reply = OrderHelper.answer(
        HelpTopic.late,
        order(
          status: OrderStatus.outForDelivery,
          history: [moved('outForDelivery', const Duration(minutes: 20))],
        ),
        now,
      );
      expect(reply.text, contains('في الطريق'));
      expect(reply.text, contains('1:40'), reason: 'when it left');
      expect(reply.actions, contains(HelpAction.callShop));
      expect(reply.actions, isNot(contains(HelpAction.complain)));
      expect(reply.actions, isNot(contains(HelpAction.cancelOrder)));
    });

    test('an order on the road for a long time is worth the team', () {
      final reply = OrderHelper.answer(
        HelpTopic.late,
        order(
          status: OrderStatus.outForDelivery,
          history: [moved('outForDelivery', const Duration(minutes: 50))],
        ),
        now,
      );
      expect(reply.actions, contains(HelpAction.complain));
    });

    test('an order being cooked says when it should be ready', () {
      final reply = OrderHelper.answer(
        HelpTopic.late,
        order(
          status: OrderStatus.preparing,
          prepMinutes: 30,
          history: [moved('accepted', const Duration(minutes: 10))],
        ),
        now,
      );
      expect(reply.text, contains('2:20'), reason: 'accepted 1:50 plus thirty minutes');
      expect(reply.actions, isNot(contains(HelpAction.complain)));
    });

    test('an order well past the time the shop gave is worth the team', () {
      final reply = OrderHelper.answer(
        HelpTopic.late,
        order(
          status: OrderStatus.preparing,
          prepMinutes: 20,
          history: [moved('accepted', const Duration(minutes: 45))],
        ),
        now,
      );
      expect(reply.actions, contains(HelpAction.complain));
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
    // The bill is the answer; before the food arrives there is nothing to dispute yet.
    expect(reply.actions, isNot(contains(HelpAction.complain)));
  });

  test('money after delivery can still go to the team — the change may not have come back', () {
    final reply = OrderHelper.answer(
      HelpTopic.money,
      order(status: OrderStatus.delivered),
      now,
    );
    expect(reply.actions, contains(HelpAction.complain));
  });

  // What زعتر answers by itself since 2026-09-24, without sending anybody to a person.
  group('answered without the team', () {
    test('thanks is thanked', () {
      final reply = OrderHelper.answer(HelpTopic.thanks, order(), now);
      expect(reply.text, contains('العفو'));
      expect(reply.actions, [HelpAction.done]);
    });

    test('a greeting is greeted, with the order it is about', () {
      final reply = OrderHelper.answer(HelpTopic.hello, order(), now);
      expect(reply.text, contains('#42'));
      expect(reply.actions, [HelpAction.done]);
    });

    test('how to pay, the coupon and the fee are explained', () {
      final reply = OrderHelper.answer(HelpTopic.howTo, order(), now);
      expect(reply.text, contains('كاش'));
      expect(reply.text, contains('كوبون'));
      expect(reply.actions, [HelpAction.done]);
    });

    test('a change before the shop answers is: cancel and order again', () {
      final reply = OrderHelper.answer(HelpTopic.change, order(), now);
      expect(reply.actions, contains(HelpAction.cancelOrder));
      expect(reply.actions, isNot(contains(HelpAction.complain)));
    });

    test('a change once the kitchen has it is the shop to call', () {
      final reply = OrderHelper.answer(
        HelpTopic.change,
        order(status: OrderStatus.preparing),
        now,
      );
      expect(reply.actions, contains(HelpAction.callShop));
      expect(reply.actions, isNot(contains(HelpAction.complain)));
    });

    test('food not right before it has arrived waits for it', () {
      final reply = OrderHelper.answer(
        HelpTopic.quality,
        order(status: OrderStatus.preparing),
        now,
      );
      expect(reply.actions, isNot(contains(HelpAction.complain)));
    });
  });

  // The one that is a person's to settle: food that arrived wrong.
  test('food that arrived not right can go to the team', () {
    final reply = OrderHelper.answer(
      HelpTopic.quality,
      order(status: OrderStatus.delivered),
      now,
    );
    expect(reply.text, contains('آسفين'));
    expect(reply.actions, contains(HelpAction.complain));
  });

  test('a message nobody understood asks again before it asks the team', () {
    final reply = OrderHelper.answer(HelpTopic.other, order(), now);
    expect(reply.text, contains('بكلام تاني'));
    expect(reply.actions, contains(HelpAction.complain),
        reason: 'the team stays a way out, just not the first answer');
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
