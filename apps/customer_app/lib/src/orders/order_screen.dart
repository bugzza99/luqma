import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

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
      appBar: AppBar(title: const Text('متابعة الطلب')),
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
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final canCancel =
        order.status.canMoveTo(OrderStatus.cancelled, by: OrderActor.customer);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.xxxl,
      ),
      children: [
        _Header(order: order),
        const SizedBox(height: Space.xl),
        if (order.status == OrderStatus.cancelled)
          _Cancelled(order: order)
        else
          _Track(order: order),
        const SizedBox(height: Space.xl),
        _Summary(order: order),
        const SizedBox(height: Space.xl),
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: Radii.cardAll,
            border: Border.all(color: colors.hairline),
          ),
          child: Row(
            children: [
              Icon(Icons.payments_outlined, size: Sizes.iconMd, color: colors.price),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  strings.collectFromCustomer,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                strings.price(order.pricing.total),
                style: LuqmaType.price.copyWith(color: colors.price),
              ),
            ],
          ),
        ),
        if (order.status == OrderStatus.delivered) ...[
          const SizedBox(height: Space.xl),
          _RatingCard(order: order),
        ],
        const SizedBox(height: Space.xl),
        // Always reachable, whatever state the order is in. A customer who cannot
        // complain phones the merchant instead, and the platform never hears about it.
        OutlinedButton.icon(
          key: OrderScreen.issueKey,
          onPressed: () => _reportIssue(context, ref),
          icon: const Icon(Icons.flag_outlined, size: Sizes.iconSm),
          label: Text(strings.orderProblem),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(Sizes.minTarget),
          ),
        ),
        if (canCancel) ...[
          const SizedBox(height: Space.sm),
          TextButton(
            key: OrderScreen.cancelKey,
            onPressed: () => _confirmCancel(context, ref),
            style: TextButton.styleFrom(
              foregroundColor: colors.danger,
              minimumSize: const Size.fromHeight(Sizes.minTarget),
            ),
            child: const Text('إلغاء الطلب'),
          ),
        ],
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
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _IssueSheet(),
    );

    if (reason == null || !context.mounted) return;
    final customerUid = order.customerUid;
    // A retained order can outlive its account. It is unreachable from that deleted
    // customer's signed-out app, but keeping the guard here means a historic row can
    // never turn a nullable database reference into a crash.
    if (customerUid == null) return;

    await ref.read(orderRepositoryProvider).raiseIssue(
          orderId: order.id,
          customerUid: customerUid,
          merchantId: order.merchantId,
          reason: reason,
        );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('وصلتنا شكواك، هنراجعها.')),
    );
  }
}

/// The complaint form.
///
/// A widget rather than a closure holding a controller: a sheet keeps rebuilding while
/// it animates away, so a controller disposed the moment `showModalBottomSheet` returns
/// is a controller the field is still using.
class _IssueSheet extends StatefulWidget {
  const _IssueSheet();

  @override
  State<_IssueSheet> createState() => _IssueSheetState();
}

class _IssueSheetState extends State<_IssueSheet> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('إيه اللي حصل؟', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: Space.md),
              TextField(
                key: OrderScreen.issueTextKey,
                controller: _reason,
                maxLines: 3,
                maxLength: 300,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'الأكل وصل بارد، ناقص صنف، اتأخر…',
                ),
              ),
              const SizedBox(height: Space.md),
              FilledButton(
                key: OrderScreen.sendIssueKey,
                // An empty complaint tells an admin nothing and wastes the reply.
                onPressed: () {
                  final text = _reason.text.trim();
                  if (text.isEmpty) return;
                  Navigator.of(context).pop(text);
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(Sizes.minTarget),
                ),
                child: const Text('ابعت'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(order.merchantName, style: theme.textTheme.headlineMedium),
        const SizedBox(height: Space.xs),
        // The number is what a phone call to the merchant starts with, so it is on the
        // screen rather than buried in a receipt.
        Text(
          'طلب رقم ${order.orderNumber}',
          style: LuqmaType.bodySmall.copyWith(color: colors.textSecondary),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final reached = OrderScreen.track.indexOf(order.status);
    // needsAttention is not on the track. It means nobody answered, which the customer
    // reads as "still waiting" — and somebody is already phoning the restaurant.
    final current = reached < 0 ? 0 : reached;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        children: [
          for (var i = 0; i < OrderScreen.track.length; i++)
            Padding(
              key: OrderScreen.stepKey(OrderScreen.track[i]),
              padding: EdgeInsets.only(
                bottom: i == OrderScreen.track.length - 1 ? 0 : Space.md,
              ),
              child: Row(
                children: [
                  Icon(
                    i < current
                        ? Icons.check_circle_rounded
                        : i == current
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                    key: i == current ? OrderScreen.currentStepKey : null,
                    size: Sizes.iconMd,
                    color: i <= current ? colors.success : colors.border,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Text(
                      _labels[OrderScreen.track[i]]!,
                      style: i == current
                          ? LuqmaType.bodyStrong.copyWith(color: colors.textPrimary)
                          : theme.textTheme.bodyMedium?.copyWith(
                              color: i < current
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                            ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
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

class _Summary extends StatelessWidget {
  const _Summary({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الطلب', style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.sm),
        for (final item in order.items)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xs),
            child: Row(
              children: [
                Text(
                  '${item.quantity}×',
                  style: LuqmaType.bodyStrong.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(item.name)),
                Text(
                  strings.price(item.lineTotal),
                  style: LuqmaType.priceSmall.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
          ),
      ],
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
      child: _sent
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
