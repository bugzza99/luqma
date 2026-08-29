import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';
import 'statistics_controller.dart';

/// The wider picture, read-only.
///
/// Everything here is an aggregate the server computed — the client never reads every
/// order in the city to count them. What cannot be answered cheaply is not answered at
/// all rather than guessed.
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  static const customersKey = Key('statistics.customers');
  static const merchantsKey = Key('statistics.merchants');
  static const ordersKey = Key('statistics.orders');
  static const averageKey = Key('statistics.average');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatisticsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الإحصائيات')),
      body: AdminContent(
        child: LuqmaAsyncView(
          value: stats,
          onRetry: () => ref.invalidate(adminStatisticsProvider),
          builder: (context, value) => _Body(stats: value)
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.stats});

  final AdminStatistics stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = LuqmaStrings.of(context);

    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        Text('الأرقام الكبيرة', style: theme.textTheme.headlineMedium),
        const SizedBox(height: Space.lg),
        _Stat(key: StatisticsScreen.customersKey, label: 'العملاء', value: '${stats.customers}'),
        const SizedBox(height: Space.sm),
        _Stat(key: StatisticsScreen.ordersKey, label: 'كل الطلبات', value: '${stats.ordersTotal}'),
        const SizedBox(height: Space.sm),
        _Stat(
          key: StatisticsScreen.averageKey,
          label: 'متوسط قيمة الطلب',
          value: strings.price(stats.avgOrderValue),
        ),
        const SizedBox(height: Space.xl),
        Text('المطاعم', style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.sm),
        _StatusBreakdown(
          key: StatisticsScreen.merchantsKey,
          statuses: stats.merchantsByStatus,
        ),
        const SizedBox(height: Space.xl),
        Text('النمو', style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.sm),
        _Series(title: 'آخر 8 أسابيع', points: stats.byWeek),
        const SizedBox(height: Space.lg),
        _Series(title: 'آخر 6 شهور', points: stats.byMonth),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.label, required this.value});

  final String label;
  final String value;

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
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(color: colors.price)),
        ],
      ),
    );
  }
}

class _StatusBreakdown extends StatelessWidget {
  const _StatusBreakdown({super.key, required this.statuses});

  final Map<String, int> statuses;

  static const _arabic = {
    'pending': 'مستنيين موافقة',
    'approved': 'معتمدين',
    'suspended': 'موقوفين',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (statuses.isEmpty) {
      return Text(
        'لسه مفيش مطاعم.',
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: theme.luqma.textSecondary),
      );
    }

    return Column(
      children: [
        for (final entry in statuses.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _arabic[entry.key] ?? entry.key,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text('${entry.value}', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
      ],
    );
  }
}

class _Series extends StatelessWidget {
  const _Series({required this.title, required this.points});

  final String title;
  final List<SeriesPoint> points;

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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: Space.md),
          if (points.isEmpty)
            Text(
              'مفيش بيانات لسه.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            )
          else
            for (final point in points)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatStart(point.starting),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ),
                    Text('${point.count}', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static String _formatStart(DateTime start) =>
      '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
}
