import '../models/order.dart';

/// What a customer can ask the complaints assistant about. Five, because five buttons fit a
/// phone without scrolling and cover what customers actually write: every ticket in the
/// queue so far is one of these or «حاجة تانية».
enum HelpTopic {
  late,
  wrongItems,
  cancel,
  money,
  other,

  /// The food arrived and is not right: cold, burnt, off.
  quality,

  /// The customer wants something on the order changed: an item, the address.
  change,

  /// How the product works: paying, a coupon, the delivery fee.
  howTo,

  /// «شكرا». Answered as thanks, never sent to a person.
  thanks,

  /// «السلام عليكم». Answered as a greeting.
  hello,
}

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
        HelpTopic.quality => 'الأكل مش كويس',
        HelpTopic.change => 'عاوز أعدّل الطلب',
        HelpTopic.howTo => 'الدفع والكوبون',
        HelpTopic.thanks => 'شكراً',
        HelpTopic.hello => 'سلام',
      };

  /// The topics offered as buttons. The rest are reached by typing — nine buttons do not
  /// fit a phone, and «شكراً» is not something anybody needs a button to say.
  static const menu = [
    HelpTopic.late,
    HelpTopic.wrongItems,
    HelpTopic.quality,
    HelpTopic.cancel,
    HelpTopic.money,
    HelpTopic.other,
  ];

  /// How long past what the shop promised before the team is worth offering. Until then
  /// the answer is the time itself, which is what the customer asked for (the owner,
  /// 2026-09-24: «زعتر» sent everybody to the team).
  static const _grace = Duration(minutes: 15);

  /// How long an order may be on the road before the team is worth offering.
  static const _onTheRoad = Duration(minutes: 40);

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
    // The rule the server enforces, time included: an escalated order is the admin's for
    // fifteen minutes before it is the customer's to cancel.
    final canCancel = order.customerMayCancelAt(now);

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
            final acceptedAt = _enteredAt(order, OrderStatus.accepted);
            final minutes = order.prepMinutes;
            if (acceptedAt != null && minutes != null && minutes > 0) {
              final ready = acceptedAt.add(Duration(minutes: minutes));
              if (now.isBefore(ready.add(_grace))) {
                return HelpReply(
                  '$shop قبل طلبك الساعة ${_clock(acceptedAt)} وقال هيجهّزه في $minutes '
                  'دقيقة، يعني المتوقع يخرج حوالي ${_clock(ready)}. أول ما يخرج مع '
                  'المندوب هيوصلك إشعار.',
                  const [HelpAction.done, HelpAction.callShop],
                );
              }
              return HelpReply(
                '$shop كان قايل الطلب هيجهز حوالي ${_clock(ready)}، ولسه مخرجش. كلّم '
                'المطعم يطمّنك، ولو مش بيرد ابعت لفريق لقمة.',
                const [HelpAction.callShop, HelpAction.complain],
              );
            }
            return HelpReply(
              '$shop قبل طلبك وبيجهّزه دلوقتي. أول ما يخرج مع المندوب هيوصلك إشعار. '
              'لو عاوز تعرف فاضل قد إيه، كلّم المطعم على طول.',
              const [HelpAction.done, HelpAction.callShop],
            );
          case OrderStatus.outForDelivery:
            final outAt = _enteredAt(order, OrderStatus.outForDelivery);
            if (outAt != null && now.difference(outAt) >= _onTheRoad) {
              return HelpReply(
                'الأوردر خرج مع المندوب الساعة ${_clock(outAt)}، وده وقت أطول من المعتاد. '
                'كلّم المطعم يوصّلك بالمندوب، ولو محدش رد ابعت لفريق لقمة.',
                const [HelpAction.callShop, HelpAction.complain],
              );
            }
            return HelpReply(
              'الأوردر في الطريق لك مع المندوب'
              '${outAt == null ? '' : '، خرج الساعة ${_clock(outAt)}'}. '
              'المندوب هيكلّمك لما يوصل، وجهّز الحساب كاش.',
              const [HelpAction.done, HelpAction.callShop],
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
        final delivered = order.status == OrderStatus.delivered;
        return HelpReply(
          [
            'حساب طلبك:',
            'الأكل: ${pounds(p.subtotal)}',
            'التوصيل: ${pounds(p.deliveryFee)}',
            if (discount > 0) 'الخصم: ${pounds(discount)}',
            'المطلوب كاش للمندوب: ${pounds(p.total)}',
            if (delivered)
              'لو اندفع أكتر من كده أو الباقي مرجعش، ابعت لفريق لقمة.'
            else
              'مفيش أي مبلغ تاني، وده اللي هتدفعه للمندوب لما يوصل.',
          ].join('\n'),
          // Before the food arrives the bill is the whole answer; there is nothing to
          // dispute yet. After it, the change may not have come back.
          delivered
              ? const [HelpAction.done, HelpAction.complain]
              : const [HelpAction.done],
        );
      case HelpTopic.quality:
        if (order.status == OrderStatus.delivered) {
          return HelpReply(
            'آسفين إن الأكل موصلكش زي ما يستاهل. قيّم الطلب علشان $shop يعرف، ولو محتاج '
            'نراجع معاه، ابعت لفريق لقمة وقول إيه اللي حصل.',
            const [HelpAction.complain, HelpAction.callShop, HelpAction.done],
          );
        }
        return const HelpReply(
          'الأكل لسه موصلكش. أول ما يوصل بصّ عليه قدام المندوب، ولو فيه حاجة مش مظبوطة '
          'قولّي ساعتها.',
          [HelpAction.done],
        );
      case HelpTopic.change:
        if (canCancel) {
          return const HelpReply(
            'المطعم لسه مبدأش في طلبك، فأسهل طريقة للتعديل إنك تلغيه وتطلب تاني باللي '
            'عاوزه — محدش هيخسر حاجة.',
            [HelpAction.cancelOrder, HelpAction.done],
          );
        }
        if (order.status == OrderStatus.delivered ||
            order.status == OrderStatus.cancelled) {
          return const HelpReply(
            'الطلب ده خلص. تقدر تعمل طلب جديد باللي عاوزه من صفحة المطعم.',
            [HelpAction.done],
          );
        }
        return HelpReply(
          '$shop بدأ في طلبك، فالتعديل بيبقى معاه على طول: كلّمه وقوله عاوز تغيّر إيه — '
          'صنف أو العنوان.',
          const [HelpAction.callShop, HelpAction.done],
        );
      case HelpTopic.howTo:
        return const HelpReply(
          'الدفع في لقمة كاش للمندوب لما الأكل يوصل. الكوبون بتكتبه في صفحة تأكيد الطلب '
          'قبل ما تطلب، والتوصيل حسابه على حسب منطقتك وبيبان قبل ما تأكد.',
          [HelpAction.done],
        );
      case HelpTopic.thanks:
        return const HelpReply(
          'العفو! لو احتجت أي حاجة تانية في طلبك أنا هنا.',
          [HelpAction.done],
        );
      case HelpTopic.hello:
        return HelpReply(
          'أهلاً بيك! اسألني عن طلب #${order.orderNumber}: هيوصل إمتى، الحساب، أو لو '
          'فيه حاجة مش مظبوطة.',
          const [HelpAction.done],
        );
      case HelpTopic.other:
        return const HelpReply(
          'مش متأكد إني فهمتك. اكتبها بكلام تاني، أو اختار من المواضيع اللي تحت. ولو '
          'محتاج حد من فريق لقمة، دوس «ابعت لفريق لقمة».',
          [HelpAction.complain],
        );
    }
  }

  /// When [order] last moved to [status], as the server recorded it; null when its history
  /// does not say. Local time, so the clock reads as the customer's.
  static DateTime? _enteredAt(Order order, OrderStatus status) {
    for (final entry in order.statusHistory.reversed) {
      if (entry['to'] == status.name && entry['at'] is String) {
        return DateTime.tryParse(entry['at'] as String)?.toLocal();
      }
    }
    return null;
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
