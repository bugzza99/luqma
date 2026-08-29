import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'order_screen.dart';

/// طلباتي — everything this customer has ordered.
///
/// Running orders come first and finished ones after, because the reason anybody opens
/// this tab is almost always the order that is happening right now.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key, this.onSignIn});

  final VoidCallback? onSignIn;

  static const emptyKey = Key('orders.empty');
  static const errorKey = Key('orders.error');
  static const signInKey = Key('orders.signIn');

  static Key rowKey(String id) => Key('orders.row.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(currentIdentityProvider).value;

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
            empty: LuqmaEmptyView(
                key: OrdersScreen.emptyKey,
                icon: Icons.receipt_long_outlined,
                title: 'لسه مطلبتش حاجة.',
              ),
            isEmpty: (value) => value.isEmpty,
            builder: (context, value) => _List(orders: value)
          ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    // Stable within each group: the repository already sorted newest first, and this
    // only lifts the open ones above the closed ones.
    final open = orders.where((o) => o.isOpen).toList();
    final done = orders.where((o) => !o.isOpen).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.xxxl,
      ),
      children: [
        if (open.isNotEmpty) ...[
          _GroupLabel(text: 'دلوقتي'),
          for (final order in open) ...[
            _Row(order: order),
            const SizedBox(height: Space.sm),
          ],
        ],
        if (done.isNotEmpty) ...[
          if (open.isNotEmpty) const SizedBox(height: Space.lg),
          _GroupLabel(text: 'اللي فات'),
          for (final order in done) ...[
            _Row(order: order),
            const SizedBox(height: Space.sm),
          ],
        ],
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Text(
        text,
        style: LuqmaType.caption.copyWith(
          color: Theme.of(context).luqma.textSecondary,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.order});

  final Order order;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final tone = switch (order.status) {
      OrderStatus.cancelled => colors.danger,
      OrderStatus.delivered => colors.success,
      _ => colors.brand,
    };

    return InkWell(
      key: OrdersScreen.rowKey(order.id),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OrderScreen(orderId: order.id),
        ),
      ),
      borderRadius: Radii.cardAll,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        constraints: const BoxConstraints(minHeight: Sizes.minTarget),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
          boxShadow: Elevations.card,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.merchantName, style: theme.textTheme.titleMedium),
                  const SizedBox(height: Space.xs),
                  Text(
                    _labels[order.status]!,
                    style: LuqmaType.bodySmall.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    'طلب رقم ${order.orderNumber} · '
                    '${strings.orderCount(order.items.length)}',
                    style: LuqmaType.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              strings.price(order.pricing.total),
              style: LuqmaType.priceSmall.copyWith(color: colors.price),
            ),
          ],
        ),
      ),
    );
  }
}



