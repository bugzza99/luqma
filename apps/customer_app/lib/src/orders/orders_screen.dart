import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../merchant/open_merchant.dart';
import 'order_screen.dart';
import 'order_time.dart';

/// طلباتي — everything this customer has ordered.
///
/// Two shelves. **دلوقتي** carries whatever is happening right now as a burgundy hero
/// card — the merchant in white, a bar that advances as the kitchen works, the promised
/// time and the total on one line — because that card is the reason the tab gets opened.
/// **اللي فات** is everything finished, as quiet white rows, each with a coloured pip
/// that also carries its word. A finished order dropping out of the live shelf collapses
/// it rather than blinking it away.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key, this.onSignIn});

  final VoidCallback? onSignIn;

  static const emptyKey = Key('orders.empty');
  static const errorKey = Key('orders.error');
  static const signInKey = Key('orders.signIn');
  static const repeatKey = Key('orders.repeat');
  static const repeatActionKey = Key('orders.repeat.action');

  static Key rowKey(String id) => Key('orders.row.$id');

  /// Only the live order carries this, so a test can assert a finished order is *not*
  /// drawn as the hero.
  static Key heroKey(String id) => Key('orders.hero.$id');

  /// The fill of the hero's progress bar, for the tests that check it moves.
  static Key progressKey(String id) => Key('orders.progress.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(currentIdentityProvider).value;
    // One instant, read the way the rest of the app reads it: the relative dates on
    // finished orders are computed against this, never `DateTime.now()` in a widget.
    final now = ref.watch(clockProvider)();

    return Scaffold(
      backgroundColor: Theme.of(context).luqma.background,
      appBar: AppBar(title: const Text('طلباتي')),
      body: identity == null
          ? LuqmaEmptyView(
              title: 'طلباتك محفوظة على حسابك.',
              action: FilledButton(
                key: OrdersScreen.signInKey,
                onPressed: onSignIn,
                child: const Text('سجّل دخول'),
              ),
            )
          : LuqmaAsyncView(
              value: ref.watch(ordersForProvider(identity.uid)),
              errorKey: OrdersScreen.errorKey,
              onRetry: () => ref.invalidate(ordersForProvider(identity.uid)),
              empty: const LuqmaEmptyView(
                key: OrdersScreen.emptyKey,
                icon: Icons.receipt_long_outlined,
                title: 'لسه مطلبتش حاجة.',
              ),
              isEmpty: (value) => value.isEmpty,
              builder: (context, value) => _List(orders: value, now: now),
            ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.orders, required this.now});

  final List<Order> orders;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    // The repository already sorted newest-first; this only lifts the running orders
    // above the finished ones without disturbing that order within each group.
    final live = orders.where((o) => o.isOpen).toList();
    final past = orders.where((o) => !o.isOpen).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.xxxl,
      ),
      children: [
        const LuqmaNotificationBanner(
          reason: 'من غيرها مش هنعرف نقولك إن المطعم قبل طلبك، ولا لما الأوردر '
              'يخرج ويبقى في الطريق لك.',
        ),
        _LiveSection(orders: live),
        if (past.isNotEmpty) ...[
          const _SectionCaption('اللي فات'),
          const SizedBox(height: Space.md - 2),
          for (var i = 0; i < past.length; i++) ...[
            if (i > 0) const SizedBox(height: Space.sm),
            // Keyed by id so a genuinely new row runs its entrance and a row that only
            // shifted position does not re-animate.
            LuqmaEntrance(
              key: ValueKey('orders.past.${past[i].id}'),
              index: live.length + i,
              child: _PastRow(order: past[i], now: now),
            ),
          ],
          const SizedBox(height: Space.lg),
          _RepeatCard(order: past.first),
        ],
      ],
    );
  }
}

/// The **دلوقتي** shelf. When the last live order finishes and drops to the finished
/// list, the shelf folds away rather than the card vanishing.
///
/// **`AnimatedSwitcher`, not `AnimatedSize`.** It was the latter, and that animates the
/// height of whatever child is currently there — it does not keep the outgoing one. So
/// the moment the list emptied, the card was replaced by an empty box in a single frame
/// and what actually animated was a *gap* closing: the card blinked out, then a hole
/// where it had been slowly shrank. The doc comment on this class claimed the opposite,
/// which is how it survived review until somebody read the two together.
///
/// The switcher keeps the outgoing child mounted and runs the fade and the collapse on
/// the same curve, so the card leaves rather than disappearing and the space it held goes
/// with it. [Motion.of] folds the duration to zero for anyone who asked the OS for less
/// motion, and at zero the two states swap instantly — which is the correct behaviour
/// there, not a degraded one.
class _LiveSection extends StatelessWidget {
  const _LiveSection({required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.sheet),
      switchInCurve: Motion.emphasis,
      switchOutCurve: Motion.emphasis,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        // Anchored at the top, so the shelf folds up into the app bar rather than
        // collapsing toward its own middle and dragging the list under it both ways.
        axisAlignment: -1,
        child: FadeTransition(opacity: animation, child: child),
      ),
      // Both children are laid out top-aligned while they cross over; the default centres
      // them, which makes the outgoing card drift as the incoming empty state sizes.
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [...previous, ?current],
      ),
      // Keyed on emptiness alone: the shelf should cross-fade when it appears and when it
      // goes, and not every time an order inside it changes status.
      child: orders.isEmpty
          ? const SizedBox(key: ValueKey('live.empty'), width: double.infinity)
          : Column(
              key: const ValueKey('live.present'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionCaption('دلوقتي'),
                const SizedBox(height: Space.md - 2),
                for (var i = 0; i < orders.length; i++) ...[
                  if (i > 0) const SizedBox(height: Space.sm),
                  LuqmaEntrance(
                    // A separate namespace from the card's own `heroKey`. Both were
                    // `orders.hero.<id>`, and `Key('x')` *is* `ValueKey<String>('x')` —
                    // so the wrapper and the thing it wraps carried the identical key and
                    // `find.byKey` matched two widgets. This one exists to give the
                    // entrance an identity across rebuilds, which is a different job from
                    // naming the card for a test.
                    key: ValueKey('orders.heroEntrance.${orders[i].id}'),
                    index: i,
                    child: _HeroCard(order: orders[i]),
                  ),
                ],
                const SizedBox(height: Space.lg),
              ],
            ),
    );
  }
}

class _SectionCaption extends StatelessWidget {
  const _SectionCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: LuqmaType.caption.copyWith(
        color: Theme.of(context).luqma.textSecondary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// The running order. The card a customer opens the app to look at.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.order});

  final Order order;

  /// How full the progress bar sits per status. Hand-set to the artboard, which draws
  /// `preparing` at 0.55 — not `step ÷ 5`, which would land it at 0.6.
  static const _progress = <OrderStatus, double>{
    OrderStatus.placed: 0.10,
    OrderStatus.needsAttention: 0.10,
    OrderStatus.accepted: 0.32,
    OrderStatus.preparing: 0.55,
    OrderStatus.outForDelivery: 0.82,
    OrderStatus.delivered: 1.0,
  };

  /// The bar is 5dp — thinner than any [Space] step, and a bar rather than a gap.
  static const _trackHeight = 5.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final eta = _etaText(strings);

    return LuqmaPressable(
      key: OrdersScreen.rowKey(order.id),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OrderScreen(orderId: order.id),
        ),
      ),
      child: Container(
        key: OrdersScreen.heroKey(order.id),
        padding: const EdgeInsets.all(Space.lg - 1),
        decoration: BoxDecoration(
          // Fixed, not the theme's brand: the status line on this card is small orange
          // text, and the dark theme's brand is the lighter burgundy, on which that
          // orange scores 3.83:1. See `LuqmaPalette.bannerTop`.
          color: LuqmaPalette.bannerTop,
          borderRadius: Radii.cardAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.merchantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.onBrand,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Text(
                  _Row.labelFor(order.status),
                  // `orangeLight`, not `colors.accent`: the accent follows the theme and
                  // is `#D67F2B` in light, which scores 3.70:1 on this burgundy — under
                  // the 4.5:1 small text needs. `theme_test.dart` pins the pair.
                  style: LuqmaType.caption.copyWith(
                    color: LuqmaPalette.orangeLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md - 1),
            _Progress(
              progressKey: OrdersScreen.progressKey(order.id),
              target: _progress[order.status] ?? _progress[OrderStatus.placed]!,
              track: colors.onBrand.withValues(alpha: 0.25),
              fill: LuqmaPalette.orangeLight,
              height: _trackHeight,
            ),
            const SizedBox(height: Space.md - 1),
            // The promised time and the total share one baseline. Before the merchant
            // quotes a time there is nothing to promise, so the total sits alone.
            if (eta == null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  strings.price(order.pricing.total),
                  style: LuqmaType.price.copyWith(color: colors.onBrand),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      eta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LuqmaType.bodySmall.copyWith(
                        color: colors.onBrand.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  Text(
                    strings.price(order.pricing.total),
                    style: LuqmaType.price.copyWith(color: colors.onBrand),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// `هيوصلك 8:45 م`, or null before the merchant has quoted a time. There is no stored
  /// A duration, not a clock time — and the artboard asks for a clock time.
  ///
  /// The design says «هيوصلك ٨:٤٥ م», and the only way to compute that from what the
  /// client has is `placedAt + prepMinutes`. Those two numbers do not belong to the same
  /// moment: the minutes are quoted when the *merchant accepts*, which is minutes after
  /// the order was placed, and they cover cooking rather than delivery. An order placed
  /// at 8:00, accepted at 8:05 with thirty minutes quoted, would promise 8:30 — before
  /// the food is even ready, never mind arrived. Every such promise is early, and a
  /// customer watching a time pass with no food at the door is a phone call.
  ///
  /// There is no `acceptedAt` on the order; `status_history` holds the transitions but is
  /// not mapped onto the model. Until it is, the truthful thing the app can say is what
  /// the merchant actually said: how long the food needs. With nothing quoted there is
  /// nothing honest to show, and the total sits alone on the baseline.
  String? _etaText(LuqmaStrings strings) {
    final prep = order.prepMinutes;
    if (prep == null) return null;
    return strings.orderPrepEta(prep);
  }
}

/// The hero's progress bar, which advances between states instead of jumping — an order
/// moving from accepted to preparing visibly fills further. Under reduced motion
/// [Motion.of] collapses the tween to an instant set.
class _Progress extends StatelessWidget {
  const _Progress({
    required this.progressKey,
    required this.target,
    required this.track,
    required this.fill,
    required this.height,
  });

  final Key progressKey;
  final double target;
  final Color track;
  final Color fill;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: Radii.pillAll,
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: track,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: target),
              duration: Motion.of(context, Motion.sheet),
              curve: Motion.emphasis,
              builder: (context, value, _) => FractionallySizedBox(
                key: progressKey,
                widthFactor: value.clamp(0.0, 1.0),
                heightFactor: 1.0,
                child: ColoredBox(color: fill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One finished order, as a white row with a coloured status pip.
class _PastRow extends StatelessWidget {
  const _PastRow({required this.order, required this.now});

  final Order order;
  final DateTime now;

  /// The status dot. 7dp — smaller than any [Space] step, and a mark rather than a gap.
  static const _pipSize = 7.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    // Only delivered and cancelled reach this shelf — the grouping is `!isOpen` — so the
    // pip is success or danger, never the brand.
    final tone =
        order.status == OrderStatus.cancelled ? colors.danger : colors.success;

    return LuqmaPressable(
      key: OrdersScreen.rowKey(order.id),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OrderScreen(orderId: order.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        constraints: const BoxConstraints(minHeight: Sizes.minTarget),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
          boxShadow: Elevations.card,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.merchantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LuqmaType.bodyStrong.copyWith(color: colors.textPrimary),
                  ),
                ),
                const SizedBox(width: Space.sm),
                // A dot and its word. Somebody who cannot tell the green from the red
                // still reads اتسلّم or اتلغى.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: _pipSize,
                      height: _pipSize,
                      decoration: BoxDecoration(
                        color: tone,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: Space.xs + 1),
                    Text(
                      _Row.labelFor(order.status),
                      style: LuqmaType.caption.copyWith(
                        color: tone,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _meta(strings),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LuqmaType.caption.copyWith(color: colors.textSecondary),
                  ),
                ),
                Text(
                  strings.price(order.pricing.total),
                  style: LuqmaType.priceSmall.copyWith(color: colors.price),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _meta(LuqmaStrings strings) {
    final ref = strings.orderRef(order.orderNumber);
    final placedAt = order.placedAt;
    if (placedAt == null) return ref;
    return '$ref · ${formatOrderDay(placedAt, now, strings)} '
        '${formatClockTime(placedAt, strings)}';
  }
}

/// A shortcut back to the last shop, under the finished list. Its one affordance is the
/// button, exactly as drawn — the row is not a second way into the merchant screen.
class _RepeatCard extends StatelessWidget {
  const _RepeatCard({required this.order});

  final Order order;

  /// The artboard's thumbnail — a fixed 44, sized against the row rather than off the
  /// spacing scale, the way `MealCard.imageHeight` is.
  static const thumbSize = 44.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      key: OrdersScreen.repeatKey,
      padding: const EdgeInsets.all(Space.md - 1),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: Radii.fieldAll,
            child: SizedBox(
              width: thumbSize,
              height: thumbSize,
              // No photograph rides on an order, so this is always the name tint — the
              // same mark the shop wears everywhere else until its picture is taken.
              child: LuqmaImage(url: null, name: order.merchantName),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.repeatOrderFrom(order.merchantName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LuqmaType.bodySmall.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: Space.xs / 2),
                Text(
                  '${strings.repeatOrderSame} · ${strings.price(order.pricing.total)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LuqmaType.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          OutlinedButton(
            key: OrdersScreen.repeatActionKey,
            onPressed: () => openMerchant(context, order.merchantId),
            child: Text(strings.repeatOrderAction),
          ),
        ],
      ),
    );
  }
}

/// The status vocabulary, kept in one place because every word here was argued over.
/// It no longer draws a row — [_HeroCard] and [_PastRow] do — but `_Row._labels` stays
/// its single source of truth.
abstract final class _Row {
  static const _labels = {
    OrderStatus.placed: 'مستني رد المطعم',
    OrderStatus.accepted: 'المطعم قبل الطلب',
    OrderStatus.preparing: 'بيتجهّز',
    OrderStatus.outForDelivery: 'في الطريق ليك',
    OrderStatus.delivered: 'اتسلّم',
    OrderStatus.cancelled: 'اتلغى',
    // Never shown as a fault: somebody is already phoning the restaurant.
    OrderStatus.needsAttention: 'مستني رد المطعم',
  };

  static String labelFor(OrderStatus status) => _labels[status]!;
}
