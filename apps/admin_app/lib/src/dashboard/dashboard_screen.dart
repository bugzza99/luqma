import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import 'dashboard_controller.dart';

/// What needs attention today.
///
/// The screen the owner opens to find out whether anything is wrong, so the four numbers
/// here are the four things a problem shows up in: orders, money, the escalator queue and
/// the ticket queue. Restyled to match the A2_Dashboard KPI cards and attention banner
/// while preserving the exact underlying data model and keys.
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
          builder: (context, value) => _Body(today: value),
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
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final hasAttention = today.needsAttention.isNotEmpty || today.openIssues > 0;

    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        const LuqmaNotificationBanner(
          reason: 'أوردر محدش ردّ عليه بيوصلك هنا — بس بتنبيه بس لو التنبيهات شغالة.',
        ),
        if (hasAttention) ...[
          _AttentionBanner(today: today),
          const SizedBox(height: Space.md),
        ],
        Text('النهارده', style: theme.textTheme.headlineMedium),
        const SizedBox(height: Space.md),
        LayoutBuilder(
          builder: (context, constraints) {
            // A wide screen lines all three KPIs across; a phone stacks the revenue
            // card beneath the two counts so numbers have breathing room and avoid overflow.
            if (constraints.maxWidth > 500) {
              return Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      key: DashboardScreen.ordersKey,
                      label: 'طلبات النهارده',
                      value: '${today.ordersToday}',
                      icon: Icons.receipt_long_outlined,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: _KpiCard(
                      key: DashboardScreen.issuesKey,
                      label: 'شكاوى مفتوحة',
                      value: '${today.openIssues}',
                      icon: Icons.forum_outlined,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: _KpiCard(
                      key: DashboardScreen.moneyKey,
                      label: 'فلوس النهارده',
                      value: strings.price(today.moneyToday),
                      icon: Icons.payments_outlined,
                      isPrice: true,
                    ),
                  ),
                ],
              );
            }

            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _KpiCard(
                        key: DashboardScreen.ordersKey,
                        label: 'طلبات النهارده',
                        value: '${today.ordersToday}',
                        icon: Icons.receipt_long_outlined,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: _KpiCard(
                        key: DashboardScreen.issuesKey,
                        label: 'شكاوى مفتوحة',
                        value: '${today.openIssues}',
                        icon: Icons.forum_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.sm),
                _KpiCard(
                  key: DashboardScreen.moneyKey,
                  label: 'فلوس النهارده',
                  value: strings.price(today.moneyToday),
                  icon: Icons.payments_outlined,
                  isPrice: true,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: Space.xl),
        _SectionHeader(
          title: 'محتاجين اهتمام',
          count: today.needsAttention.length,
        ),
        const SizedBox(height: Space.sm),
        if (today.needsAttention.isEmpty)
          Text(
            'مفيش حاجة محتاجة تدخل دلوقتي.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
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

/// The attention banner from A2_Dashboard alerting of pending escalations or tickets.
class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({required this.today});

  final AdminToday today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final parts = <String>[];
    if (today.needsAttention.isNotEmpty) {
      parts.add(strings.dashboardAttentionOrders(today.needsAttention.length));
    }
    if (today.openIssues > 0) {
      parts.add(strings.dashboardAttentionIssues(today.openIssues));
    }
    if (parts.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm + 2,
      ),
      decoration: BoxDecoration(
        color: colors.danger.withValues(alpha: 0.1),
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colors.danger,
            size: Sizes.iconSm,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(Icons.chevron_left, color: colors.danger, size: Sizes.iconSm),
        ],
      ),
    );
  }
}

/// A single metric card on the dashboard KPI grid.
class _KpiCard extends StatelessWidget {
  const _KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.isPrice = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool isPrice;

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
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: Sizes.iconSm, color: colors.brand),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            value,
            style: isPrice
                ? LuqmaType.price.copyWith(color: colors.price)
                : LuqmaType.price.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// Section title with a pill badge showing the active item count.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count});

  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Row(
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        if (count != null && count! > 0) ...[
          const SizedBox(width: Space.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: colors.brand,
              borderRadius: Radii.pillAll,
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onBrand,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One order waiting on the escalator queue, styled with an urgent danger stripe.
class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item});

  final NeedsAttentionItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      constraints: const BoxConstraints(minHeight: Sizes.minTarget),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: colors.danger),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Row(
                  children: [
                    Icon(
                      Icons.hourglass_top_rounded,
                      color: colors.danger,
                      size: Sizes.iconMd,
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'أوردر #${item.number}',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.merchantName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
