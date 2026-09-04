import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import 'dashboard_controller.dart';

/// What needs attention today.
///
/// The screen the owner opens to find out whether anything is wrong, so the four numbers
/// here are the four things a problem shows up in: orders, money, the escalator queue and
/// the ticket queue.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static const needsAttentionKey = Key('dashboard.needsAttention');
  static const ordersKey = Key('dashboard.orders');
  static const moneyKey = Key('dashboard.money');
  static const issuesKey = Key('dashboard.issues');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(adminTodayProvider);

    return Scaffold(
      appBar: AppBar(title: const LuqmaLockup.appBar()),
      body: AdminContent(
        child: LuqmaAsyncView(
          value: today,
          onRetry: () => ref.invalidate(adminTodayProvider),
          builder: (context, value) => _Body(today: value)
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.today});

  final AdminToday today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        const LuqmaNotificationBanner(
          reason: 'أوردر محدش ردّ عليه بيوصلك هنا — بس بتنبيه بس لو التنبيهات شغالة.',
        ),
        Text('النهارده', style: theme.textTheme.headlineMedium),
        const SizedBox(height: Space.lg),
        _Metric(
          key: DashboardScreen.ordersKey,
          label: 'طلبات النهارده',
          value: '${today.ordersToday}',
          icon: Icons.receipt_long_outlined,
        ),
        const SizedBox(height: Space.sm),
        _Metric(
          key: DashboardScreen.moneyKey,
          label: 'فلوس النهارده',
          value: LuqmaStrings.of(context).price(today.moneyToday),
          icon: Icons.payments_outlined,
        ),
        const SizedBox(height: Space.sm),
        _Metric(
          key: DashboardScreen.issuesKey,
          label: 'شكاوى مفتوحة',
          value: '${today.openIssues}',
          icon: Icons.forum_outlined,
        ),
        const SizedBox(height: Space.xl),
        Text('محتاجين اهتمام', style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.sm),
        if (today.needsAttention.isEmpty)
          Text(
            'مفيش حاجة محتاجة تدخل دلوقتي.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.luqma.textSecondary),
          )
        else
          ...today.needsAttention.map(
            (item) => Padding(
              key: DashboardScreen.needsAttentionKey,
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: _QueueRow(item: item),
            ),
          ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      constraints: const BoxConstraints(minHeight: Sizes.minTarget),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.brand, size: Sizes.iconMd),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            value,
            style: LuqmaType.price.copyWith(color: colors.price),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item});

  final NeedsAttentionItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      padding: const EdgeInsets.all(Space.md),
      constraints: const BoxConstraints(minHeight: Sizes.minTarget),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_top_rounded, color: colors.danger, size: Sizes.iconMd),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('أوردر #${item.number}', style: theme.textTheme.titleMedium),
                Text(
                  item.merchantName,
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
