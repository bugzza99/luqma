import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// كشف الحساب — what the platform took, order by order.
///
/// The whole reason it exists in this app rather than only in AdminApp: the merchant is
/// the person whose money this is, and a figure they cannot check is a figure they will
/// eventually dispute over a phone. The rows are the answer to "why is it this much",
/// and they are the same rows the platform reads.
///
/// A subscription merchant is not sent here — nothing is taken per order, and a
/// statement of zeroes is a screen that teaches somebody to distrust it.
class StatementScreen extends ConsumerWidget {
  const StatementScreen({super.key, required this.merchantId});

  final String merchantId;

  static const summaryKey = Key('statement.summary');
  static const emptyKey = Key('statement.empty');
  static const owedKey = Key('statement.owed');
  static const platformOwesKey = Key('statement.platformOwes');

  static Key rowKey(String orderId) => Key('statement.row.$orderId');
  static Key reversedKey(String orderId) => Key('statement.reversed.$orderId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;
    final settlements = ref.watch(merchantSettlementsProvider(merchantId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('كشف الحساب')),
      body: LuqmaAsyncView(
        value: settlements,
        onRetry: () => ref.invalidate(merchantSettlementsProvider(merchantId)),
        empty: const LuqmaEmptyView(
          key: emptyKey,
          icon: Icons.receipt_long_outlined,
          title: 'لسه مفيش حسابات.',
          message: 'أول ما أوردر يتسلّم، هيظهر هنا بالتفصيل.',
        ),
        isEmpty: (rows) => rows.isEmpty,
        builder: (context, rows) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.lg,
            Space.gutter,
            Space.xxxl,
          ),
          // One extra for the summary, which scrolls with the rows rather than sitting
          // pinned above them: it is the total *of* this list, and a header that stays
          // while the list moves reads as a figure about something else.
          itemCount: rows.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
          itemBuilder: (context, index) => index == 0
              ? _Summary(merchantId: merchantId)
              : _Row(settlement: rows[index - 1]),
        ),
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.merchantId});

  final String merchantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final summary = ref.watch(settlementSummaryProvider(merchantId)).value;
    final merchant = ref.watch(merchantProvider(merchantId)).value;

    if (summary == null || merchant == null) return const SizedBox.shrink();

    return Container(
      key: StatementScreen.summaryKey,
      margin: const EdgeInsets.only(bottom: Space.sm),
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
            strings.orderCount(summary.orders),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Space.md),
          _Line(
            label: merchant.revenueModel == RevenueModel.prepaid
                ? 'اتخصم من الرصيد'
                : 'العمولة على الفترة دي',
            value: strings.price(summary.taken),
          ),
          // Only when there is one. A row reading "لينا عندك ٠" on every merchant's
          // screen is a question nobody asked, and it invites the answer "why is that
          // there at all".
          if (summary.platformOwes > 0) ...[
            const SizedBox(height: Space.sm),
            _Line(
              lineKey: StatementScreen.platformOwesKey,
              // The other direction, and the one a merchant will ask about first: a
              // discount the platform funded is cash that never reached their till.
              label: 'لقمة عليها لك',
              value: strings.price(summary.platformOwes),
              emphasis: colors.success,
            ),
          ],
          if (merchant.revenueModel == RevenueModel.commission) ...[
            const SizedBox(height: Space.sm),
            _Line(
              lineKey: StatementScreen.owedKey,
              // The running total on the merchant, not a sum of this page: the page is a
              // hundred rows at most and the debt is everything since the last payment.
              label: 'المستحق حتى دلوقتي',
              value: strings.price(merchant.commissionOwed),
              emphasis: colors.price,
            ),
          ],
        ],
      ),
    );
  }
}

/// `24/8`, the same shape the promotions screens use.
///
/// Not a locale-aware formatter: `intl` is not a dependency of these apps, every date in
/// this product is inside one city's current month or two, and a merchant reading a
/// statement wants to recognise a day rather than parse a date.
String _day(DateTime date) => '${date.day}/${date.month}';

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.emphasis,
    this.lineKey,
  });

  final String label;
  final String value;
  final Color? emphasis;
  final Key? lineKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Row(
      key: lineKey,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: LuqmaType.priceSmall.copyWith(color: emphasis ?? colors.textPrimary),
        ),
      ],
    );
  }
}

/// One charge.
class _Row extends StatelessWidget {
  const _Row({required this.settlement});

  final OrderSettlement settlement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final charged = settlement.isCharged;

    return Container(
      key: StatementScreen.rowKey(settlement.orderId),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // The order's own money, which is what a merchant recognises a row by
                  // — they remember the sale, not the id of it.
                  'أوردر بـ ${strings.price(settlement.basis)}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (settlement.settledAt != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    _day(settlement.settledAt!),
                    style: LuqmaType.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
                if (!charged) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    // Kept rather than hidden. A merchant who saw a charge and then finds
                    // it gone has no way to tell whether it was returned or whether the
                    // screen is wrong.
                    'اترجع',
                    key: StatementScreen.reversedKey(settlement.orderId),
                    style: LuqmaType.caption.copyWith(color: colors.success),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Text(
            strings.price(settlement.amount),
            style: LuqmaType.priceSmall.copyWith(
              color: charged ? colors.textPrimary : colors.textSecondary,
              decoration: charged ? null : TextDecoration.lineThrough,
            ),
          ),
        ],
      ),
    );
  }
}
