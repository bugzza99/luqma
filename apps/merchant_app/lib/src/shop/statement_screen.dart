import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// كشف الحساب — what the platform took, and what has been paid against it.
///
/// The whole reason it exists in this app rather than only in AdminApp: the merchant is
/// the person whose money this is, and a figure they cannot check is a figure they will
/// eventually dispute over a phone. The rows are the answer to "why is it this much",
/// and they are the same rows the platform reads.
///
/// A subscription merchant is not sent here at all — nothing is taken per order, and a
/// statement of zeroes is a screen that teaches somebody to distrust it.
class StatementScreen extends ConsumerWidget {
  const StatementScreen({super.key, required this.merchantId});

  final String merchantId;

  static const summaryKey = Key('statement.summary');
  static const emptyKey = Key('statement.empty');
  static const owedKey = Key('statement.owed');
  static const creditKey = Key('statement.credit');
  static const platformOwesKey = Key('statement.platformOwes');
  static const paidKey = Key('statement.paid');
  static const tabsKey = Key('statement.tabs');
  static const chargesTabKey = Key('statement.tab.charges');
  static const paymentsTabKey = Key('statement.tab.payments');
  static const noPaymentsKey = Key('statement.noPayments');

  static Key rowKey(String orderId) => Key('statement.row.$orderId');
  static Key reversedKey(String orderId) => Key('statement.reversed.$orderId');
  static Key paymentRowKey(String paymentId) => Key('statement.payment.$paymentId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;
    final merchant = ref.watch(merchantProvider(merchantId)).value;
    final payments = ref.watch(commissionPaymentsProvider(merchantId)).value;

    // Two sides only where there can be two. A prepaid merchant pays by topping up a
    // wallet, which is not a commission receipt and never lands in that table — so the
    // tab would be permanently empty, and a tab that is always empty teaches somebody
    // that the screen has nothing to say.
    final collectable = merchant != null &&
        (merchant.revenueModel == RevenueModel.commission ||
            merchant.commissionOwed != 0 ||
            (payments != null && payments.isNotEmpty));

    if (!collectable) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(title: const Text('كشف الحساب')),
        body: _Charges(merchantId: merchantId),
      );
    }

    return DefaultTabController(
      key: tabsKey,
      length: 2,
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: const Text('كشف الحساب'),
          bottom: const TabBar(
            tabs: [
              // What was taken, then what was handed over. In that order because the
              // first is the question a merchant opens this screen with, and the second
              // is what they check afterwards.
              Tab(key: chargesTabKey, text: 'الشحنات'),
              Tab(key: paymentsTabKey, text: 'المدفوعات'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Above the tabs rather than inside one, because it is the answer and they
            // are the working. A total that scrolled away with one of two lists would
            // read as a figure about that list alone.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.lg,
                Space.gutter,
                Space.md,
              ),
              child: _Summary(merchantId: merchantId),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _Charges(merchantId: merchantId, withSummary: false),
                  _Payments(merchantId: merchantId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the platform took, order by order.
class _Charges extends ConsumerWidget {
  const _Charges({required this.merchantId, this.withSummary = true});

  final String merchantId;

  /// False when the tabs are showing, where the summary sits above both lists instead.
  final bool withSummary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlements = ref.watch(merchantSettlementsProvider(merchantId));

    return LuqmaAsyncView(
      value: settlements,
      onRetry: () => ref.invalidate(merchantSettlementsProvider(merchantId)),
      empty: const LuqmaEmptyView(
        key: StatementScreen.emptyKey,
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
        // One extra for the summary when it is not already pinned above: it is the total
        // of this list, and a header that stays while the list moves reads as a figure
        // about something else.
        itemCount: rows.length + (withSummary ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
        itemBuilder: (context, index) => withSummary && index == 0
            ? _Summary(merchantId: merchantId)
            : _Row(settlement: rows[index - (withSummary ? 1 : 0)]),
      ),
    );
  }
}

/// The receipts: what was handed over, when, and what was said at the counter.
class _Payments extends ConsumerWidget {
  const _Payments({required this.merchantId});

  final String merchantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(commissionPaymentsProvider(merchantId));

    return LuqmaAsyncView(
      value: payments,
      onRetry: () => ref.invalidate(commissionPaymentsProvider(merchantId)),
      empty: const LuqmaEmptyView(
        key: StatementScreen.noPaymentsKey,
        icon: Icons.payments_outlined,
        title: 'مفيش مدفوعات مسجّلة.',
        // Not "you have not paid anything": a merchant who owes nothing has nothing to
        // pay, and a screen that reads as a reminder to somebody with no debt is one
        // they resent.
        message: 'أول ما تتحصّل عمولة، الإيصال هيظهر هنا.',
      ),
      isEmpty: (rows) => rows.isEmpty,
      builder: (context, rows) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.lg,
          Space.gutter,
          Space.xxxl,
        ),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
        itemBuilder: (context, index) => _PaymentRow(payment: rows[index]),
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
    final payments = ref.watch(commissionPaymentsProvider(merchantId)).value;

    if (summary == null || merchant == null) return const SizedBox.shrink();

    final paid = (payments ?? const <CommissionPayment>[])
        .fold(0, (total, payment) => total + payment.amount);

    return Container(
      key: StatementScreen.summaryKey,
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
          if (paid > 0) ...[
            const SizedBox(height: Space.sm),
            _Line(
              lineKey: StatementScreen.paidKey,
              // Beside the charge rather than only inside the other tab: the two
              // together are the arithmetic behind the balance below, and a merchant
              // reading one figure without the other cannot check the third.
              label: 'اتدفع',
              value: strings.price(paid),
              emphasis: colors.success,
            ),
          ],
          if (merchant.revenueModel == RevenueModel.commission ||
              merchant.commissionOwed != 0) ...[
            const SizedBox(height: Space.sm),
            _Line(
              lineKey: merchant.commissionOwed < 0
                  ? StatementScreen.creditKey
                  : StatementScreen.owedKey,
              // The running total on the merchant, not a sum of this page: the page is a
              // hundred rows at most and the debt is everything since the last payment.
              //
              // Negative is credit — an admin in a shop takes what is on the counter
              // rather than arguing about five pounds — and it is said in words rather
              // than shown as a minus sign, which on a screen about money reads as a
              // fault rather than a fact.
              label: merchant.commissionOwed < 0
                  ? 'ليك عندنا'
                  : 'المستحق حتى دلوقتي',
              value: strings.price(merchant.commissionOwed.abs()),
              emphasis:
                  merchant.commissionOwed < 0 ? colors.success : colors.price,
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

/// One receipt.
class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final CommissionPayment payment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      key: StatementScreen.paymentRowKey(payment.id),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        children: [
          Icon(Icons.payments_outlined, color: colors.success, size: Sizes.iconMd),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تحصيل', style: theme.textTheme.bodyMedium),
                if (payment.recordedAt != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    _day(payment.recordedAt!),
                    style: LuqmaType.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
                if (payment.note != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    // The only free text in the money path, and the reason it is shown
                    // here rather than kept on the admin's side: a merchant should read
                    // the same note the admin wrote rather than remember it.
                    payment.note!,
                    style: LuqmaType.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Text(
            // Money coming off the debt, so it reads in the other direction from a
            // charge. The sign is the whole point of putting the two in one statement.
            '- ${strings.price(payment.amount)}',
            style: LuqmaType.priceSmall.copyWith(color: colors.success),
          ),
        ],
      ),
    );
  }
}
