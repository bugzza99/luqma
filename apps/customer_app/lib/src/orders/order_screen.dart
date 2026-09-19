import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'order_help_sheet.dart';
import 'order_time.dart';

/// One order, followed live.
///
/// The whole screen is a document listener: the merchant accepting, the courier setting
/// off, and the food arriving all reach the customer as changes to one document, with no
/// polling and no refresh button.
class OrderScreen extends ConsumerWidget {
  const OrderScreen({super.key, required this.orderId});

  final String orderId;

  static const currentStepKey = Key('order.currentStep');
  static const cancelledKey = Key('order.cancelled');
  static const errorKey = Key('order.error');
  static const cancelKey = Key('order.cancel');
  static const confirmCancelKey = Key('order.confirmCancel');
  static const issueKey = Key('order.issue');
  static const issueTextKey = Key('order.issueText');
  static const sendIssueKey = Key('order.sendIssue');
  static const rateKey = Key('order.rate');
  static const sendRatingKey = Key('order.sendRating');
  static const heroKey = Key('order.hero');
  static const stageKey = Key('order.stage');
  static const prepQuoteKey = Key('order.prepQuote');
  static const billKey = Key('order.bill');
  static const callMerchantKey = Key('order.callMerchant');

  static Key stepKey(OrderStatus status) => Key('order.step.${status.name}');
  static Key starKey(int stars) => Key('order.star.$stars');
  static Key itemStarKey(String itemId, int stars) =>
      Key('order.itemStar.$itemId.$stars');

  /// The path an order walks, in order. `needsAttention` and `cancelled` are not steps
  /// on it — they are the two ways it stops — so they are shown as their own state
  /// rather than as a stalled track.
  static const track = [
    OrderStatus.placed,
    OrderStatus.accepted,
    OrderStatus.preparing,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(orderProvider(orderId));

    return Scaffold(
      backgroundColor: Theme.of(context).luqma.background,
      // The number, not «متابعة الطلب». It is what a phone call to the shop opens with,
      // and the bar is the one part of this screen that does not scroll away — which is
      // where it has to be, because the moment somebody needs it is the moment they have
      // scrolled to the bottom looking for how to complain.
      appBar: AppBar(
        title: Text(
          order.value == null ? 'متابعة الطلب' : 'طلب #${order.value!.orderNumber}',
        ),
      ),
      body: LuqmaAsyncView(
        value: order,
        errorKey: OrderScreen.errorKey,
        onRetry: () => ref.invalidate(orderProvider(orderId)),
        builder: (context, value) => _Loaded(order: value)
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;

    final canCancel =
        order.status.canMoveTo(OrderStatus.cancelled, by: OrderActor.customer);

    final zoneName = ref
        .watch(zonesProvider)
        .value
        ?.where((z) => z.id == order.zoneId)
        .firstOrNull
        ?.name;

    final sections = <Widget>[
      _Hero(order: order, zoneName: zoneName),
      if (order.status == OrderStatus.cancelled)
        _Cancelled(order: order)
      else
        _Track(order: order),
      _Bill(order: order),
      _Items(order: order),
      if (order.status == OrderStatus.delivered) _RatingCard(order: order),
      _Actions(order: order, onIssue: () => _reportIssue(context, ref)),
      if (canCancel)
        TextButton(
          key: OrderScreen.cancelKey,
          onPressed: () => _confirmCancel(context, ref),
          style: TextButton.styleFrom(
            foregroundColor: colors.danger,
            minimumSize: const Size.fromHeight(Sizes.minTarget),
          ),
          child: const Text('إلغاء الطلب'),
        ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.md,
        Space.gutter,
        Space.xxxl,
      ),
      children: [
        // Here as well as on طلباتي: checkout lands on this screen, and a customer who never
        // opens that tab was never asked — so Android dropped every status notification.
        const LuqmaNotificationBanner(
          reason: 'من غيرها مش هنعرف نقولك إن المطعم قبل طلبك، ولا لما الأوردر '
              'يخرج ويبقى في الطريق لك.',
        ),
        for (final (index, section) in sections.indexed)
          Padding(
            // The rating card appears when the food lands and the cancel button leaves
            // when it can no longer be pressed, so this list changes length while
            // somebody is looking at it — and Flutter matches children by position.
            key: ValueKey('slot:${section.key ?? section.runtimeType}'),
            padding: const EdgeInsets.only(bottom: Space.md),
            child: LuqmaEntrance(index: index, child: section),
          ),
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تلغي الطلب؟'),
        content: const Text(
          'لسه المطعم مردش، فالإلغاء دلوقتي مش هيضيّع على حد حاجة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('سيبه'),
          ),
          FilledButton(
            key: OrderScreen.confirmCancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ألغِ الطلب'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref
          .read(orderRepositoryProvider)
          .cancel(order.id, reason: 'ألغاه العميل');
      ref.invalidate(orderProvider(order.id));
    }
  }

  Future<void> _reportIssue(BuildContext context, WidgetRef ref) async {
    // The assistant first: most questions — "where is my food", "what do I owe" — are
    // answered by the order itself, and a ticket for each of them is a person's evening
    // spent reading what the screen already knew (the owner's decision, 2026-09-19).
    final outcome = await showModalBottomSheet<HelpOutcome>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OrderHelpSheet(
        order: order,
        shopPhone: ref.read(merchantProvider(order.merchantId)).value?.phone,
      ),
    );
    if (outcome == null || !context.mounted) return;

    switch (outcome) {
      case CancelRequested():
        await _confirmCancel(context, ref);
      case ComplaintWritten(:final text):
        final customerUid = order.customerUid;
        // A retained order can outlive its account. It is unreachable from that deleted
        // customer's signed-out app, but keeping the guard here means a historic row can
        // never turn a nullable database reference into a crash.
        if (customerUid == null) return;

        final result = await ref.read(orderRepositoryProvider).raiseIssue(
              orderId: order.id,
              customerUid: customerUid,
              merchantId: order.merchantId,
              reason: text,
            );

        if (!context.mounted) return;
        // It used to say «وصلتنا» whatever happened — a complaint lost to a dead
        // connection was thanked for.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.isOk
                  ? 'وصلتنا شكواك، هنراجعها ونرد عليك.'
                  : 'الشكوى موصلتش — اتأكد من النت وجرّب تاني.',
            ),
          ),
        );
    }
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow:
            theme.brightness == Brightness.light ? Elevations.card : Elevations.none,
      ),
      child: child,
    );
  }
}

/// The burgundy panel a customer opens the app to look at.
///
/// The artboard puts a clock time in the largest type on the screen — «هيوصلك 8:45 م».
/// Nothing can produce that number. `prepMinutes` is what the merchant quoted **when they
/// accepted**, and the order carries no `acceptedAt` to anchor it to, so an arrival time
/// computed here would be a guess printed in the boldest thing on the page, on the one
/// screen somebody checks precisely because they want to know.
///
/// So the biggest line is the stage, which is known for certain, and the quote is offered
/// underneath as what it actually is: a duration the kitchen said, not a time we promise.
class _Hero extends StatelessWidget {
  const _Hero({required this.order, required this.zoneName});

  /// The stages where a kitchen's estimate is still a statement about the future.
  static const _quotable = {
    OrderStatus.placed,
    OrderStatus.accepted,
    OrderStatus.preparing,
  };

  final Order order;
  final String? zoneName;

  static const _stage = {
    OrderStatus.placed: 'مستنيين المطعم يرد',
    OrderStatus.accepted: 'المطعم قبل الطلب',
    OrderStatus.preparing: 'الطلب بيتجهز',
    OrderStatus.outForDelivery: 'الطلب في الطريق ليك',
    OrderStatus.delivered: 'الطلب اتسلّم',
    OrderStatus.cancelled: 'الطلب اتلغى',
    OrderStatus.needsAttention: 'مستنيين المطعم يرد',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = LuqmaStrings.of(context);

    // The burgundy stays on a delivered order as well as a live one. It was briefly a
    // pale card there, on the reasoning that a finished order has nothing left to
    // announce — the owner's call is that the colour is the product's, and a receipt in
    // the brand reads better than a receipt in grey. What the state changes is the
    // *words*, not the ground.
    final settled = order.status == OrderStatus.delivered;

    // Fixed in both themes, not `colors.brand`. The dark theme swaps the brand to a
    // lighter burgundy, and the eyebrow below is small orange text: 4.79:1 on this
    // ground and 3.83:1 on that one, which fails the 4.5:1 small text needs.
    const ink = LuqmaPalette.cream;

    final where = [
      order.merchantName,
      if (zoneName != null && zoneName!.isNotEmpty) zoneName!,
    ].join(' · ');

    return Container(
      key: OrderScreen.heroKey,
      width: double.infinity,
      padding: const EdgeInsets.all(Space.lg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [LuqmaPalette.bannerTop, LuqmaPalette.bannerBottom],
        ),
        borderRadius: Radii.cardAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            where,
            style: LuqmaType.caption.copyWith(color: LuqmaPalette.orangeLight),
          ),
          const SizedBox(height: Space.xs),
          Text(
            // On a delivered order the loudest line is the hour it arrived, because that
            // is the fact somebody comes back for and it is genuinely stamped on the
            // order. Every other stage has no time behind it — see `_stampFor` — so the
            // stage's own words stay the headline there.
            switch (order.deliveredAt) {
              final DateTime at when settled =>
                'اتسلّم ${formatClockTime(at, strings)}',
              _ => _stage[order.status] ?? _stage[OrderStatus.placed]!,
            },
            key: OrderScreen.stageKey,
            style: LuqmaType.display.copyWith(color: LuqmaPalette.white),
          ),
          // Only while it can still be true. The quote is about food becoming ready, so
          // once the courier has it the readiness has happened and the sentence is about
          // a moment that has passed — which is how a delivered order came to say
          // «هيجهز خلال ١٥ دقيقة» under «الطلب اتسلّم» on a real handset.
          if (order.prepMinutes != null && _quotable.contains(order.status)) ...[
            const SizedBox(height: Space.xs),
            Text(
              // Attributed on purpose. «المطعم قال» is a quote with an author; «هيوصلك»
              // would be the app promising a time it cannot know.
              'المطعم قال هيجهز خلال ${strings.minutes(order.prepMinutes!)}',
              key: OrderScreen.prepQuoteKey,
              style: theme.textTheme.bodySmall?.copyWith(color: ink),
            ),
          ],
        ],
      ),
    );
  }
}

class _Track extends StatelessWidget {
  const _Track({required this.order});

  final Order order;

  static const _labels = {
    OrderStatus.placed: 'وصل الطلب للمطعم',
    OrderStatus.accepted: 'المطعم قبل الطلب',
    OrderStatus.preparing: 'بيتجهّز',
    OrderStatus.outForDelivery: 'في الطريق ليك',
    OrderStatus.delivered: 'اتسلّم',
  };

  /// The clock beside a step, or null when nothing on the order can say.
  ///
  /// The artboard prints a time against every line. The order carries exactly two:
  /// `placedAt` and `deliveredAt`. Acceptance, cooking and setting off are not stamped
  /// anywhere, so those steps are marked reached and left without an hour rather than
  /// given one derived from something else — a made-up 8:14 beside «المطعم قبل الطلب» is
  /// worse than a dash, because it is the kind of detail somebody repeats on the phone.
  DateTime? _stampFor(OrderStatus status) => switch (status) {
        OrderStatus.placed => order.placedAt,
        OrderStatus.delivered => order.deliveredAt,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final reached = OrderScreen.track.indexOf(order.status);
    // needsAttention is not on the track. It means nobody answered, which the customer
    // reads as "still waiting" — and somebody is already phoning the restaurant.
    final current = reached < 0 ? 0 : reached;

    // «اتسلّم» is where the track ends, and an order sitting on it is not *at* that step,
    // it is finished with it. Marking it the way every in-progress step is marked left
    // the one stage that genuinely completed as the only one without a tick — a filled
    // ring reading "happening now" under a card that says the food arrived.
    final settled = order.status == OrderStatus.delivered;

    return _Card(
      child: Column(
        children: [
          for (var i = 0; i < OrderScreen.track.length; i++)
            Padding(
              key: OrderScreen.stepKey(OrderScreen.track[i]),
              padding: EdgeInsets.only(
                bottom: i == OrderScreen.track.length - 1 ? 0 : Space.lg,
              ),
              child: Row(
                children: [
                  _StepMark(
                    key: i == current ? OrderScreen.currentStepKey : null,
                    done: i < current || (settled && i == current),
                    current: i == current && !settled,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      _labels[OrderScreen.track[i]]!,
                      style: i == current
                          ? LuqmaType.bodyStrong.copyWith(
                              color: theme.brightness == Brightness.dark
                                  ? colors.textPrimary
                                  : colors.brand,
                            )
                          : theme.textTheme.bodyMedium?.copyWith(
                              color: i < current
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                            ),
                    ),
                  ),
                  // Nothing at all where there is no time, rather than a dash. Only two
                  // of the five stages are stamped, so a placeholder on the other three
                  // stacked into a column of dashes down the side of the card — which
                  // reads as a screen that failed to load its data, not as three things
                  // that have not happened yet. The mark on the left already says which
                  // stages are done; the absence of an hour says the rest on its own.
                  if (switch (_stampFor(OrderScreen.track[i])) {
                    final DateTime at when i <= current =>
                      formatClockTime(at, strings),
                    _ when i == current => 'دلوقتي',
                    _ => null,
                  } case final String label) ...[
                    const SizedBox(width: Space.sm),
                    Text(
                      label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StepMark extends StatelessWidget {
  const _StepMark({super.key, required this.done, required this.current});

  final bool done;
  final bool current;

  static const size = 26.0;
  static const _pip = 9.0;
  static const _ringWidth = 2.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return AnimatedContainer(
      // A running implicit animation retains its old duration until it restarts.
      key: ValueKey(MediaQuery.disableAnimationsOf(context)),
      duration: Motion.of(context, Motion.quick),
      curve: Motion.enter,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? colors.success
            : current
                ? colors.brand
                : Colors.transparent,
        border: done || current
            ? null
            : Border.all(color: colors.hairline, width: _ringWidth),
      ),
      alignment: Alignment.center,
      child: done
          ? Icon(
              Icons.check_rounded,
              size: Sizes.iconSm,
              // The dark theme's success green is too light for a white tick.
              color: Theme.of(context).brightness == Brightness.dark
                  ? LuqmaPalette.ink
                  : colors.onBrand,
            )
          : current
              ? Container(
                  width: _pip,
                  height: _pip,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: LuqmaPalette.orangeLight,
                  ),
                )
              : null,
    );
  }
}

/// What the order cost, as it was frozen when it was placed.
class _Bill extends StatelessWidget {
  const _Bill({required this.order});

  final Order order;
  static const _dividerHeight = 1.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final pricing = order.pricing;

    return _Card(
      key: OrderScreen.billKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BillLine(label: 'الأصناف', value: strings.price(pricing.subtotal)),
          if (pricing.subtotalDiscount > 0) ...[
            const SizedBox(height: Space.sm),
            _BillLine(
              label: order.couponCode == null
                  ? 'خصم الكود'
                  : 'خصم ${order.couponCode}',
              value: '− ${strings.price(pricing.subtotalDiscount)}',
              emphasis: true,
            ),
          ],
          if (pricing.deliveryDiscount > 0) ...[
            const SizedBox(height: Space.sm),
            _BillLine(
              label: 'خصم التوصيل',
              value: '− ${strings.price(pricing.deliveryDiscount)}',
              emphasis: true,
            ),
          ],
          const SizedBox(height: Space.sm),
          _BillLine(
            label: 'التوصيل',
            value: strings.price(pricing.deliveryFee),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.md),
            child: Divider(height: _dividerHeight),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text('المطلوب كاش', style: LuqmaType.bodyStrong),
              ),
              Text(
                strings.price(pricing.total),
                style: LuqmaType.price.copyWith(color: colors.price),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BillLine extends StatelessWidget {
  const _BillLine({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        const SizedBox(width: Space.sm),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: emphasis ? colors.success : colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Items extends StatelessWidget {
  const _Items({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الطلب', style: LuqmaType.bodyStrong),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: Row(
                children: [
                  Text(
                    '${item.quantity}×',
                    style:
                        LuqmaType.bodyStrong.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(item.name, style: theme.textTheme.bodyMedium)),
                  Text(
                    strings.price(item.lineTotal),
                    style:
                        LuqmaType.priceSmall.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The two things a customer reaches for when something is wrong.
///
/// «كلّم المطعم» is drawn only when a number is actually known — the order carries the
/// *customer's* phone, not the shop's, so the shop has to be fetched. A button that
/// cannot dial is worse than no button on the screen somebody opens because their food
/// is late.
class _Actions extends ConsumerWidget {
  const _Actions({required this.order, required this.onIssue});

  final Order order;
  final VoidCallback onIssue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;
    final phone = ref.watch(merchantProvider(order.merchantId)).value?.phone;

    return Row(
      children: [
        if (phone != null && phone.trim().isNotEmpty) ...[
          Expanded(
            child: OutlinedButton.icon(
              key: OrderScreen.callMerchantKey,
              onPressed: () async {
                final opened = await ref
                    .read(externalLinksProvider)
                    .open(Uri(scheme: 'tel', path: phone));
                if (!opened && context.mounted) {
                  // The dialer refusing is silent otherwise, and the person is holding a
                  // phone waiting for something to happen.
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('مش قادرين نفتح الاتصال. الرقم: $phone')),
                  );
                }
              },
              icon: const Icon(Icons.call_outlined, size: Sizes.iconSm),
              label: const Text('كلّم المطعم'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(Sizes.minTarget),
                // Burgundy is a button ground in the dark theme, not readable ink.
                foregroundColor: Theme.of(context).brightness == Brightness.dark
                    ? colors.textPrimary
                    : colors.brand,
                side: BorderSide(color: colors.border),
              ),
            ),
          ),
          const SizedBox(width: Sizes.targetGap),
        ],
        Expanded(
          // Always reachable, whatever state the order is in. A customer who cannot
          // complain phones the merchant instead, and the platform never hears about it.
          child: OutlinedButton.icon(
            key: OrderScreen.issueKey,
            onPressed: onIssue,
            icon: const Icon(Icons.error_outline_rounded, size: Sizes.iconSm),
            label: Text(LuqmaStrings.of(context).orderProblem),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(Sizes.minTarget),
              foregroundColor: colors.danger,
              side: BorderSide(color: colors.danger),
            ),
          ),
        ),
      ],
    );
  }
}

class _Cancelled extends StatelessWidget {
  const _Cancelled({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      key: OrderScreen.cancelledKey,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.08),
        borderRadius: Radii.cardAll,
      ),
      child: Row(
        children: [
          Icon(Icons.cancel_outlined, color: colors.danger, size: Sizes.iconMd),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الطلب اتلغى', style: theme.textTheme.titleMedium),
                if (order.cancelReason != null)
                  Text(
                    order.cancelReason!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Asked for only once the food actually arrived.
///
/// Rating an order that has not been delivered rates a guess, and the merchant carries
/// the average for it.
class _RatingCard extends ConsumerStatefulWidget {
  const _RatingCard({required this.order});

  final Order order;

  @override
  ConsumerState<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends ConsumerState<_RatingCard> {
  final _comment = TextEditingController();
  int _stars = 0;
  bool _sent = false;

  /// Stars per dish, by `menu_items.id`. Absent means not rated.
  ///
  /// A dish left out is silence rather than a zero: writing a zero for food somebody
  /// simply did not comment on would drag its average down for not being mentioned.
  final _itemStars = <String, int>{};

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final customerUid = widget.order.customerUid;
    // Only an extant customer may create a rating; deleted-account orders remain
    // readable to the financial and fulfilment sides without making this action crash.
    if (customerUid == null) return;

    await ref.read(orderRepositoryProvider).rate(
          orderId: widget.order.id,
          customerUid: customerUid,
          merchantId: widget.order.merchantId,
          stars: _stars,
          comment: _comment.text.trim(),
          items: _itemStars,
        );
    if (mounted) setState(() => _sent = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      key: OrderScreen.rateKey,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      // `_sent` alone was this card's whole memory, and it lived in the widget — so
      // leaving the screen and coming back reset it and the card asked again for a
      // rating the customer had already given. `rate` upserts, so answering twice
      // replaced the first verdict silently, from a form that starts empty: five stars
      // could become three for no reason but being asked twice. The order is the memory
      // now; `_sent` only covers the instant between the write and the stream catching up.
      child: _sent || ref.watch(hasRatedProvider(widget.order.id)).value == true
          ? Row(
              children: [
                Icon(Icons.favorite_rounded, color: colors.brand),
                const SizedBox(width: Space.md),
                Expanded(child: Text('شكراً — وصلنا تقييمك.')),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('الأكل عجبك؟', style: theme.textTheme.titleMedium),
                const SizedBox(height: Space.sm),
                Row(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        key: OrderScreen.starKey(i),
                        // Five identical stars are five identical buttons to a
                        // screen reader unless each says which one it is.
                        tooltip: '$i من 5',
                        onPressed: () => setState(() => _stars = i),
                        icon: Icon(
                          i <= _stars ? Icons.star_rounded : Icons.star_border_rounded,
                          color: i <= _stars ? colors.accent : colors.border,
                          size: Sizes.iconLg,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: Sizes.minTarget,
                          minHeight: Sizes.minTarget,
                        ),
                      ),
                  ],
                ),
                // And the food itself, dish by dish.
                //
                // One number for a whole order cannot say that the grill was good and the
                // rice was cold — and "the rice was cold" is the thing another customer
                // scrolling the menu actually needs. Optional throughout: somebody who
                // rates the shop and stops has rated the shop.
                if (widget.order.items.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  Text(
                    'وكل صنف؟ (اختياري)',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                  for (final line in widget.order.items)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              line.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          for (var i = 1; i <= 5; i++)
                            IconButton(
                              key: OrderScreen.itemStarKey(line.itemId, i),
                              tooltip: '${line.name}: $i من 5',
                              onPressed: () => setState(() {
                                // Tapping the star already chosen clears it: a customer
                                // who pressed one by accident otherwise has no way back
                                // to having said nothing.
                                if (_itemStars[line.itemId] == i) {
                                  _itemStars.remove(line.itemId);
                                } else {
                                  _itemStars[line.itemId] = i;
                                }
                              }),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: Sizes.minTarget - 12,
                                minHeight: Sizes.minTarget - 12,
                              ),
                              icon: Icon(
                                i <= (_itemStars[line.itemId] ?? 0)
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: i <= (_itemStars[line.itemId] ?? 0)
                                    ? colors.accent
                                    : colors.border,
                                size: Sizes.iconSm,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: Space.sm),
                TextField(
                  controller: _comment,
                  maxLines: 2,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    hintText: 'تحب تزوّد حاجة؟ (اختياري)',
                  ),
                ),
                const SizedBox(height: Space.sm),
                FilledButton(
                  key: OrderScreen.sendRatingKey,
                  // A rating with no stars is not a rating.
                  onPressed: _stars == 0 ? null : _send,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(Sizes.minTarget),
                  ),
                  child: const Text('ابعت التقييم'),
                ),
              ],
            ),
    );
  }
}
