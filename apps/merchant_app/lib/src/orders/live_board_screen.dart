import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// What is already being cooked or carried.
///
/// The inbox answers "yes or no"; this answers "where is it now". Its only job is to
/// make the next step one tap, and to keep the customer's phone number in reach — a
/// courier at the wrong door and a customer not answering are the two things that
/// actually go wrong, and both end in a phone call.
class LiveBoardScreen extends ConsumerWidget {
  const LiveBoardScreen({super.key});

  static const emptyKey = Key('live.empty');
  static const errorKey = Key('live.error');

  static Key cardKey(String id) => Key('live.card.$id');
  static Key advanceKey(String id) => Key('live.advance.$id');
  static Key stageKey(String id, OrderStatus status) =>
      Key('live.stage.$id.${status.name}');

  /// The step a merchant may take from each state, and what to call it.
  ///
  /// `outForDelivery` is deliberately absent: delivery is marked by the courier, who is
  /// the one standing at the door with the cash. From the kitchen it would be a guess.
  static const _next = {
    OrderStatus.accepted: (OrderStatus.preparing, 'ابدأ التحضير'),
    OrderStatus.preparing: (OrderStatus.outForDelivery, 'خرج للتوصيل'),
  };

  static const _stageLabels = {
    OrderStatus.accepted: 'مقبول',
    OrderStatus.preparing: 'بيتجهّز',
    OrderStatus.outForDelivery: 'في الطريق',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantId = ref.watch(staffIdentityProvider).merchantId;
    final colors = Theme.of(context).luqma;

    if (merchantId == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('الطلبات الجارية')),
      body: switch (ref.watch(liveOrdersProvider(merchantId))) {
        // First, and on `hasError`: a stream that fails before it has ever emitted
        // stays AsyncLoading with the error hanging off it.
        AsyncValue(hasError: true, :final error?) => _Error(failure: error),
        AsyncValue(hasValue: true, :final value?) when value.isEmpty => const _Empty(),
        AsyncValue(hasValue: true, :final value?) => ListView.separated(
            padding: const EdgeInsets.all(Space.gutter),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(height: Space.md),
            itemBuilder: (context, i) => _Card(order: value[i]),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final next = LiveBoardScreen._next[order.status];

    return Container(
      key: LiveBoardScreen.cardKey(order.id),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'طلب رقم ${order.orderNumber}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              _Stage(order: order),
            ],
          ),
          const SizedBox(height: Space.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  order.customerName,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colors.textSecondary),
                ),
              ),
              if (order.prepMinutes != null)
                // Shown back to them: this is the number a customer is now waiting
                // exactly that long for.
                Text(
                  strings.minutes(order.prepMinutes!),
                  style: LuqmaType.bodySmall.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (final item in order.items)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.xs),
              child: Row(
                children: [
                  Text(
                    '${item.quantity}×',
                    style: LuqmaType.bodyStrong.copyWith(color: colors.brand),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(item.name)),
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: Space.sm),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              Icon(Icons.phone_outlined, size: Sizes.iconSm, color: colors.textSecondary),
              const SizedBox(width: Space.sm),
              Expanded(
                child: SelectableText(
                  order.customerPhone,
                  style: LuqmaType.bodyStrong.copyWith(color: colors.textPrimary),
                ),
              ),
              Text(
                strings.price(order.pricing.total),
                style: LuqmaType.priceSmall.copyWith(color: colors.price),
              ),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: Space.md),
            FilledButton(
              key: LiveBoardScreen.advanceKey(order.id),
              onPressed: () => _advance(context, ref, next.$1),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(Sizes.minTarget),
              ),
              child: Text(next.$2),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _advance(
    BuildContext context,
    WidgetRef ref,
    OrderStatus to,
  ) async {
    final result =
        await ref.read(merchantOrderRepositoryProvider).advance(order.id, to: to);
    if (!context.mounted) return;

    // A refusal means somebody else moved it first. Silence would leave a merchant
    // tapping a button that appears to do nothing.
    if (result case Err(:final failure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (failure) {
            OfflineFailure() => 'مفيش نت — جرّب تاني.',
            ConflictFailure() => 'الطلب ده اتغير. حدّث الشاشة وشوفه تاني.',
            _ => 'مقدرناش نحفظ ده. جرّب تاني.',
          }),
        ),
      );
    }
  }
}

class _Stage extends StatelessWidget {
  const _Stage({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    final tone = switch (order.status) {
      OrderStatus.outForDelivery => colors.success,
      OrderStatus.preparing => colors.accent,
      _ => colors.surface,
    };
    final onTone = order.status == OrderStatus.accepted
        ? colors.textPrimary
        : order.status == OrderStatus.preparing
            // Dark text on the orange, never white: white on it is 3.03:1.
            ? colors.onAccent
            : colors.onBrand;

    return Container(
      key: LiveBoardScreen.stageKey(order.id, order.status),
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs + 2,
      ),
      decoration: BoxDecoration(color: tone, borderRadius: Radii.pillAll),
      child: Text(
        LiveBoardScreen._stageLabels[order.status] ?? '',
        style: LuqmaType.bodySmall.copyWith(color: onTone, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      key: LiveBoardScreen.emptyKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Text(
          'مفيش طلبات تحت التحضير دلوقتي.',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.failure});

  final Object failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      key: LiveBoardScreen.errorKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 56, color: theme.luqma.danger),
            const SizedBox(height: Space.lg),
            Text(
              'مش قادرين نوصل للطلبات',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.sm),
            Text(
              switch (failure) {
                OfflineFailure() => 'شوف النت. في طلبات شغالة مش ظاهرة هنا.',
                PermissionFailure() => 'الحساب ده مالوش صلاحية على المطعم ده.',
                _ => 'حصل خطأ. جرّب تاني بعد شوية.',
              },
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.luqma.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
