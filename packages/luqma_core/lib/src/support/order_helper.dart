import '../models/order.dart';

/// What a customer can ask the complaints assistant about. Five, because five buttons fit a
/// phone without scrolling and cover what customers actually write: every ticket in the
/// queue so far is one of these or «حاجة تانية».
enum HelpTopic { late, wrongItems, cancel, money, other }

/// What the assistant can offer after it answers. The screen draws one button per action;
/// the assistant never does anything on its own.
enum HelpAction {
  /// Cancel the order — offered only while the customer is allowed to.
  cancelOrder,

  /// Telephone the shop.
  callShop,

  /// Send the question to a person on the Luqma team, as a ticket.
  complain,

  /// The answer was enough.
  done,
}

/// One answer: a sentence built from the order, and what can be done next.
class HelpReply {
  const HelpReply(this.text, this.actions);

  final String text;
  final List<HelpAction> actions;
}

/// The complaints assistant, as rules rather than a model.
///
/// Free, instant, and it cannot invent anything: every sentence is read off the order the
/// customer is looking at — its status, its deadline, its bill. What it cannot settle it
/// hands to a person as an ordinary ticket, so nothing a customer types is ever answered
/// by the assistant alone (the owner's decision, 2026-09-19: «ردود جاهزة ببلاش»).
abstract final class OrderHelper {
  static String label(HelpTopic topic) => switch (topic) {
        HelpTopic.late => 'الأوردر اتأخر',
        HelpTopic.wrongItems => 'ناقص صنف أو غلط في الطلب',
        HelpTopic.cancel => 'عاوز ألغي الطلب',
        HelpTopic.money => 'الحساب والفلوس',
        HelpTopic.other => 'حاجة تانية',
      };

  /// The ticket text: the topic first, so the admin's queue reads at a glance, then
  /// whatever the customer typed.
  static String complaintText(HelpTopic topic, String typed) {
    final text = typed.trim();
    return text.isEmpty ? label(topic) : '${label(topic)}: $text';
  }

  static HelpReply answer(
    HelpTopic topic,
    Order order,
    DateTime now, {
    String Function(int piastres)? money,
  }) {
    final pounds = money ?? _pounds;
    final shop = order.merchantName;
    final canCancel =
        order.status.canMoveTo(OrderStatus.cancelled, by: OrderActor.customer);

    if (order.status == OrderStatus.cancelled && topic != HelpTopic.money) {
      final why = order.cancelReason?.trim();
      return HelpReply(
        'الطلب ده اتلغى${why == null || why.isEmpty ? '' : ' — السبب: $why'}. '
        'مفيش فلوس اتدفعت عليه، لأن الدفع كاش عند الاستلام.',
        const [HelpAction.complain, HelpAction.done],
      );
    }

    switch (topic) {
      case HelpTopic.late:
        switch (order.status) {
          case OrderStatus.placed:
          case OrderStatus.needsAttention:
            final deadline = order.acceptDeadlineAt;
            if (deadline != null && deadline.isAfter(now)) {
              // Rounded up: «0 دقيقة» with thirty seconds left reads as already late.
              final left = (deadline.difference(now).inSeconds + 59) ~/ 60;
              return HelpReply(
                '$shop لسه مشافش طلبك. قدامه $left دقيقة يرد، ولو مردش فريق لقمة '
                'هيتبلّغ ويكلّمه. تقدر تستنى أو تلغي من غير ما تخسر حاجة.',
                [if (canCancel) HelpAction.cancelOrder, HelpAction.done],
              );
            }
            return HelpReply(
              '$shop اتأخر في الرد على طلبك، وفريق لقمة اتبلّغ وهيكلّمه. '
              'لو مش عاوز تستنى تقدر تلغي دلوقتي من غير ما تخسر حاجة.',
              [
                if (canCancel) HelpAction.cancelOrder,
                HelpAction.callShop,
                HelpAction.complain,
              ],
            );
          case OrderStatus.accepted:
          case OrderStatus.preparing:
            return HelpReply(
              '$shop قبل طلبك وبيجهّزه دلوقتي. أول ما يخرج مع المندوب هيوصلك إشعار. '
              'لو عاوز تعرف فاضل قد إيه، كلّم المطعم على طول.',
              const [HelpAction.callShop, HelpAction.complain, HelpAction.done],
            );
          case OrderStatus.outForDelivery:
            return const HelpReply(
              'الأوردر خرج وهو في الطريق لك مع المندوب. لو اتأخر أكتر من اللازم كلّم '
              'المطعم، أو ابعت لفريق لقمة.',
              [HelpAction.callShop, HelpAction.complain, HelpAction.done],
            );
          case OrderStatus.delivered:
            final at = order.deliveredAt;
            return HelpReply(
              'الطلب متسجّل إنه اتسلّم${at == null ? '' : ' الساعة ${_clock(at)}'}. '
              'لو موصلكش، ابعت لفريق لقمة دلوقتي وهنراجعه مع المطعم.',
              const [HelpAction.complain, HelpAction.callShop],
            );
          case OrderStatus.cancelled:
            return const HelpReply('', [HelpAction.done]); // handled above
        }
      case HelpTopic.wrongItems:
        if (order.status == OrderStatus.delivered) {
          return const HelpReply(
            'آسفين على كده. اكتب الصنف الناقص أو الغلط وهنراجعه مع المطعم.',
            [HelpAction.complain, HelpAction.callShop],
          );
        }
        return const HelpReply(
          'الأوردر لسه موصلش. أول ما يوصل راجعه قدام المندوب، ولو عاوز تعدّل حاجة '
          'دلوقتي كلّم المطعم قبل ما يخرج.',
          [HelpAction.callShop, HelpAction.done],
        );
      case HelpTopic.cancel:
        if (canCancel) {
          return const HelpReply(
            'المطعم لسه مردش، فتقدر تلغي دلوقتي ومحدش هيخسر حاجة.',
            [HelpAction.cancelOrder, HelpAction.done],
          );
        }
        if (order.status == OrderStatus.delivered) {
          return const HelpReply(
            'الطلب اتسلّم خلاص فمينفعش يتلغي. لو فيه مشكلة فيه ابعتها لفريق لقمة.',
            [HelpAction.complain, HelpAction.done],
          );
        }
        return HelpReply(
          '$shop بدأ يجهّز الأكل، فالإلغاء من التطبيق اتقفل عشان محدش يخسر أكل اتعمل. '
          'كلّم المطعم وهو يقرر معاك.',
          const [HelpAction.callShop, HelpAction.complain],
        );
      case HelpTopic.money:
        final p = order.pricing;
        final discount = p.subtotalDiscount + p.deliveryDiscount;
        return HelpReply(
          [
            'حساب طلبك:',
            'الأكل: ${pounds(p.subtotal)}',
            'التوصيل: ${pounds(p.deliveryFee)}',
            if (discount > 0) 'الخصم: ${pounds(discount)}',
            'المطلوب كاش للمندوب: ${pounds(p.total)}',
            'لو اندفع أكتر من كده أو الباقي مرجعش، ابعت لفريق لقمة.',
          ].join('\n'),
          const [HelpAction.complain, HelpAction.done],
        );
      case HelpTopic.other:
        return const HelpReply(
          'اكتب اللي حصل وفريق لقمة هيراجعه ويرد عليك.',
          [HelpAction.complain],
        );
    }
  }

  /// The same shape as `LuqmaMoney.amount`, for callers without localizations at hand.
  static String _pounds(int piastres) {
    final whole = piastres ~/ 100;
    final rest = piastres % 100;
    final figure = rest == 0 ? '$whole' : '$whole.${rest.toString().padLeft(2, '0')}';
    return '$figure ج';
  }

  static String _clock(DateTime at) {
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    return '$hour:${at.minute.toString().padLeft(2, '0')}';
  }
}
