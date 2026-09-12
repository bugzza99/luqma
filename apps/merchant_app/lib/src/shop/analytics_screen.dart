import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// The analytics screen (M09): what this shop sold across a window of time.
///
/// Reached from the shop tab beside the statement. Ungated by design: even though the
/// original design sprint marked analytics as plan-gated, hiding a shop's own numbers
/// at launch behind a paid tier costs merchant trust and buys nothing.
///
/// Follows the numbers from `public.merchant_sales`: food sales only («مبيعات الأكل»,
/// not «الإيرادات», because the delivery fee was never the merchant's), average order,
/// and unfulfilled orders split by who cancelled.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key, required this.merchantId});

  final String merchantId;

  static const screenKey = Key('analytics.screen');
  static const rangeTodayKey = Key('analytics.range.today');
  static const rangeWeekKey = Key('analytics.range.week');
  static const rangeMonthKey = Key('analytics.range.month');

  static const statOrdersKey = Key('analytics.stat.orders');
  static const statSalesKey = Key('analytics.stat.sales');
  static const statAverageKey = Key('analytics.stat.average');
  static const statUnfulfilledKey = Key('analytics.stat.unfulfilled');

  static const chartKey = Key('analytics.chart');
  static const topItemsKey = Key('analytics.topItems');
  static const emptyTopItemsKey = Key('analytics.topItems.empty');

  static Key barKey(String day) => Key('analytics.chart.bar.$day');
  static Key itemKey(String itemId) => Key('analytics.topItem.$itemId');

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

/// Alias for compatibility with code expecting SalesScreen.
typedef SalesScreen = AnalyticsScreen;

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  /// The selected window in days: 1 (today), 7 (week - default), or 30 (month).
  int _selectedDays = 7;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final salesAsync = ref.watch(
      merchantSalesProvider(widget.merchantId, days: _selectedDays),
    );

    return Scaffold(
      key: AnalyticsScreen.screenKey,
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('الإحصائيات'),
      ),
      body: LuqmaAsyncView<MerchantSales>(
        value: salesAsync,
        onRetry: () => ref.invalidate(
          merchantSalesProvider(widget.merchantId, days: _selectedDays),
        ),
        builder: (context, sales) => ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.md,
            Space.gutter,
            Space.xxxl,
          ),
          children: [
            // Time range selector: اليوم / الأسبوع / الشهر
            _RangeChips(
              selectedDays: _selectedDays,
              onChanged: (days) => setState(() => _selectedDays = days),
            ),
            const SizedBox(height: Space.lg),

            // The four figures in a 2x2 grid
            _FourFigures(sales: sales),
            const SizedBox(height: Space.lg),

            // Bar chart of the days in the window
            _BarChart(sales: sales),
            const SizedBox(height: Space.lg),

            // The dishes that sold, most first, with quantities
            _TopDishes(sales: sales),
          ],
        ),
      ),
    );
  }
}

/// Time range selector chips.
class _RangeChips extends StatelessWidget {
  const _RangeChips({
    required this.selectedDays,
    required this.onChanged,
  });

  final int selectedDays;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          LuqmaChip(
            key: AnalyticsScreen.rangeTodayKey,
            label: 'اليوم',
            selected: selectedDays == 1,
            onTap: () => onChanged(1),
          ),
          const SizedBox(width: Space.sm),
          LuqmaChip(
            key: AnalyticsScreen.rangeWeekKey,
            label: 'الأسبوع',
            selected: selectedDays == 7,
            onTap: () => onChanged(7),
          ),
          const SizedBox(width: Space.sm),
          LuqmaChip(
            key: AnalyticsScreen.rangeMonthKey,
            label: 'الشهر',
            selected: selectedDays == 30,
            onTap: () => onChanged(30),
          ),
        ],
      ),
    );
  }
}

/// The four core figures.
///
/// 1. Orders count.
/// 2. Food sales («مبيعات الأكل», never «الإيرادات» because delivery fee is excluded).
/// 3. Average order food value.
/// 4. Unfulfilled orders (one card, showing total cancelled/returned with breakdown).
class _FourFigures extends StatelessWidget {
  const _FourFigures({required this.sales});

  final MerchantSales sales;

  @override
  Widget build(BuildContext context) {
    final strings = LuqmaStrings.of(context);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                cardKey: AnalyticsScreen.statOrdersKey,
                label: 'الطلبات',
                value: '${sales.orders}',
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: _StatCard(
                cardKey: AnalyticsScreen.statSalesKey,
                label: 'مبيعات الأكل',
                value: strings.price(sales.sales),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StatCard(
                cardKey: AnalyticsScreen.statAverageKey,
                label: 'متوسط الطلب',
                value: strings.price(sales.average),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: _UnfulfilledCard(sales: sales),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.cardKey,
    required this.label,
    required this.value,
  });

  final Key cardKey;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      key: cardKey,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            value,
            style: LuqmaType.price.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// What did not happen — cancellations and returns in one card.
///
/// A shop wants to know the number and then why:
/// - Customer cancellation (changed mind or refused before dispatch)
/// - Merchant cancellation (refused or unavailable)
/// - Courier return (nobody at the door or unreachable)
class _UnfulfilledCard extends StatelessWidget {
  const _UnfulfilledCard({required this.sales});

  final MerchantSales sales;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final count = sales.unfulfilled;

    return Container(
      key: AnalyticsScreen.statUnfulfilledKey,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'لم يكتمل',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            '$count',
            style: LuqmaType.price.copyWith(
              color: count > 0 ? colors.danger : colors.textPrimary,
            ),
          ),
          const SizedBox(height: Space.xs),
          if (count == 0)
            Text(
              'كل الطلبات اكتملت',
              style: LuqmaType.caption.copyWith(color: colors.success),
            )
          else ...[
            if (sales.cancelledByCustomer > 0)
              Text(
                '${sales.cancelledByCustomer} من العميل',
                style: LuqmaType.bodySmall.copyWith(color: colors.textSecondary),
              ),
            if (sales.cancelledByMerchant > 0)
              Text(
                '${sales.cancelledByMerchant} من المحل',
                style: LuqmaType.bodySmall.copyWith(color: colors.textSecondary),
              ),
            if (sales.returned > 0)
              Text(
                '${sales.returned} رجع مع الطيار',
                style: LuqmaType.bodySmall.copyWith(color: colors.textSecondary),
              ),
          ],
        ],
      ),
    );
  }
}

/// Bar chart of the days in the window.
///
/// Implemented as a row of sized `Container`s rather than `CustomPaint` because:
/// 1. Direct widget composition integrates naturally with Flutter's RTL layout direction,
///    accessibility semantics, and standard widget testing.
/// 2. Labels use standard Cairo typography and theme colors with no manual TextPainter metrics.
/// 3. Safely guards against zero-sales weeks: when all days have 0 sales, `maxSales` is 0,
///    the height ratio becomes 0.0, and baseline pins are drawn without any zero division.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.sales});

  final MerchantSales sales;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final byDay = sales.byDay;
    if (byDay.isEmpty) return const SizedBox.shrink();

    // Guard against zero division when every day is zero:
    final maxSales =
        byDay.fold<int>(0, (max, d) => d.sales > max ? d.sales : max);
    const chartHeight = 120.0;
    const barAreaHeight = 80.0;

    return Container(
      key: AnalyticsScreen.chartKey,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sales.days == 1
                ? 'مبيعات اليوم'
                : sales.days == 7
                    ? 'الطلبات خلال الأسبوع'
                    : 'الطلبات خلال الشهر',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Space.lg),
          SizedBox(
            height: chartHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < byDay.length; i++) ...[
                  if (i > 0)
                    SizedBox(width: byDay.length > 15 ? 2 : Space.xs),
                  Expanded(
                    child: _BarColumn(
                      day: byDay[i],
                      // Division by zero guard:
                      ratio: maxSales > 0
                          ? (byDay[i].sales / maxSales).clamp(0.0, 1.0)
                          : 0.0,
                      isLast: i == byDay.length - 1,
                      barAreaHeight: barAreaHeight,
                      compact: byDay.length > 15,
                    ),
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

class _BarColumn extends StatelessWidget {
  const _BarColumn({
    required this.day,
    required this.ratio,
    required this.isLast,
    required this.barAreaHeight,
    this.compact = false,
  });

  final MerchantSalesDay day;
  final double ratio;
  final bool isLast;
  final double barAreaHeight;
  final bool compact;

  static const _dayLetters = {
    1: 'ن', // الاثنين
    2: 'ث', // الثلاثاء
    3: 'ر', // الأربعاء
    4: 'خ', // الخميس
    5: 'ج', // الجمعة
    6: 'س', // السبت
    7: 'ح', // الأحد
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final parsed = DateTime.tryParse(day.day);
    final dayLetter = parsed != null ? (_dayLetters[parsed.weekday] ?? '') : '';
    final dayNum = parsed != null ? '${parsed.day}' : '';

    // If day has 0 sales, anchor with a 3dp baseline pin so the day is visible.
    final barHeight =
        ratio > 0 ? (ratio * barAreaHeight).clamp(6.0, barAreaHeight) : 3.0;
    final barColor = ratio > 0
        ? (isLast ? colors.accent : colors.brand)
        : colors.border.withValues(alpha: 0.5);

    return Column(
      key: AnalyticsScreen.barKey(day.day),
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          height: barAreaHeight,
          alignment: Alignment.bottomCenter,
          child: Container(
            height: barHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
        ),
        const SizedBox(height: Space.xs),
        if (!compact) ...[
          Text(
            dayLetter,
            style: LuqmaType.caption.copyWith(
              fontWeight: isLast ? FontWeight.w700 : FontWeight.w600,
              color: isLast ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ],
        Text(
          dayNum,
          style: LuqmaType.caption.copyWith(
            color: colors.textSecondary,
            fontSize: compact ? 9 : null,
          ),
        ),
      ],
    );
  }
}

/// The dishes that sold across the window, most first, with quantities.
class _TopDishes extends StatelessWidget {
  const _TopDishes({required this.sales});

  final MerchantSales sales;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final topItems = sales.topItems;

    return Container(
      key: AnalyticsScreen.topItemsKey,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الأصناف الأكثر طلباً',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Space.md),
          if (topItems.isEmpty)
            Container(
              key: AnalyticsScreen.emptyTopItemsKey,
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              alignment: Alignment.center,
              child: Text(
                'لسه مفيش أطباق اتباعت في الفترة دي.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            )
          else ...[
            for (var i = 0; i < topItems.length; i++) ...[
              if (i > 0) const SizedBox(height: Space.md),
              _DishRow(
                item: topItems[i],
                maxQty: topItems.first.quantity,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DishRow extends StatelessWidget {
  const _DishRow({
    required this.item,
    required this.maxQty,
  });

  final MerchantSalesTopItem item;
  final int maxQty;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final ratio = maxQty > 0 ? (item.quantity / maxQty).clamp(0.0, 1.0) : 0.0;

    return Column(
      key: AnalyticsScreen.itemKey(item.itemId),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LuqmaBillLine(
          label: item.name,
          value: '${item.quantity} طلب',
        ),
        const SizedBox(height: Space.xs),
        Container(
          height: 6,
          width: double.infinity,
          decoration: BoxDecoration(
            color: colors.border.withValues(alpha: 0.3),
            borderRadius: Radii.pillAll,
          ),
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: ratio,
            child: Container(
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: Radii.pillAll,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
