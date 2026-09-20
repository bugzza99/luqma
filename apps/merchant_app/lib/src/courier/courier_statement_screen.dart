import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// كشف حساب المندوب — every delivery that was charged, every pound handed over, and
/// what is left between the rider and the platform.
///
/// Courier mode was one screen on purpose: the delivery page is sized for somebody
/// reading it one-handed at a junction, and eleven screens of queue, availability and
/// earnings were declined for that reason. What that left, and what the owner called out
/// on 2026-09-21, is a rider who cannot see what they delivered, what was charged on it,
/// or whether last week's cash was ever credited. A person who cannot check a number they
/// are asked to pay will eventually dispute it over the telephone.
///
/// So the *delivery* screen stays exactly as it was, and this is a page of its own
/// reached from the summary card. It is deliberately the same shape as the merchant's
/// `StatementScreen`: a summary, then the charges, then the payments. One ledger read
/// through one set of policies, so the rider and the owner are looking at the same rows
/// when the week is settled.
class CourierStatementScreen extends ConsumerWidget {
  const CourierStatementScreen({super.key, this.courierUid});

  /// Null for the signed-in rider, which is what their own screen passes. The policy
  /// answers it, so nobody has to name themselves and nobody can name anybody else.
  final String? courierUid;

  static const owedKey = Key('courierStatement.owed');
  static const creditKey = Key('courierStatement.credit');
  static const squareKey = Key('courierStatement.square');
  static const owedFailedKey = Key('courierStatement.owedFailed');
  static const paidKey = Key('courierStatement.paid');
  static const chargesTabKey = Key('courierStatement.tab.charges');
  static const paymentsTabKey = Key('courierStatement.tab.payments');
  static const noChargesKey = Key('courierStatement.noCharges');
  static const noPaymentsKey = Key('courierStatement.noPayments');

  static Key chargeKey(String orderId) => Key('courierStatement.charge.$orderId');
  static Key reversedKey(String orderId) => Key('courierStatement.reversed.$orderId');
  static Key paymentKey(String id) => Key('courierStatement.payment.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: const Text('كشف الحساب'),
          bottom: const TabBar(
            tabs: [
              Tab(key: chargesTabKey, text: 'اللي اتحسب عليك'),
              Tab(key: paymentsTabKey, text: 'اللي سددته'),
            ],
          ),
        ),
        body: Column(
          children: [
            _Summary(courierUid: courierUid),
            Expanded(
              child: TabBarView(
                children: [
                  _Charges(courierUid: courierUid),
                  _Payments(courierUid: courierUid),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one figure the whole page is about, and the one the rider came to check.
class _Summary extends ConsumerWidget {
  const _Summary({required this.courierUid});

  final String? courierUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    // No identity lookup: the policy answers "whose balance" the same way it answers
    // whose charges and whose payments. Waiting for the identity first meant drawing a
    // spinner the page could get stuck behind, for a uid the server never needed.
    final owedAsync = ref.watch(courierOwedProvider(courierUid: courierUid));
    final payments = ref.watch(courierPaymentsProvider(courierUid: courierUid)).value;

    final paid = payments?.fold<int>(0, (sum, p) => sum + p.amount) ?? 0;

    // hasError first, and not only for the usual reason. A read that failed leaves
    // `value` null, which is the same thing "still loading" leaves — so a summary that
    // branches on the value alone spins for ever on a dropped connection, with the one
    // figure the rider came to check never arriving and nothing saying why.
    final owed = owedAsync.hasError ? null : owedAsync.value;
    final owedFailed = owedAsync.hasError;

    return Container(
      margin: const EdgeInsets.all(Space.gutter),
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
          if (owedFailed)
            LuqmaErrorView(
              key: CourierStatementScreen.owedFailedKey,
              compact: true,
              failure: owedAsync.error,
              onRetry: () => ref.invalidate(courierOwedProvider(courierUid: courierUid)),
            )
          else if (owed == null)
            const Center(child: CircularProgressIndicator())
          else if (owed > 0)
            LuqmaBillLine(
              key: CourierStatementScreen.owedKey,
              label: 'عليك للمنصة',
              value: strings.price(owed),
              emphasis: true,
            )
          else if (owed < 0)
            // Said in words. A minus sign in front of a figure somebody is owed is the
            // kind of thing that gets read as a debt at the wrong moment.
            LuqmaBillLine(
              key: CourierStatementScreen.creditKey,
              label: 'رصيد ليك عندنا',
              value: strings.price(-owed),
              emphasis: true,
            )
          else
            Row(
              key: CourierStatementScreen.squareKey,
              children: [
                Icon(Icons.check_circle_outline, color: colors.success, size: Sizes.iconSm),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text('حسابك مظبوط، مفيش عليك حاجة',
                      style: theme.textTheme.bodyMedium),
                ),
              ],
            ),
          if (paid > 0) ...[
            const SizedBox(height: Space.xs),
            LuqmaBillLine(
              key: CourierStatementScreen.paidKey,
              label: 'اللي سددته',
              value: strings.price(paid),
            ),
          ],
          const SizedBox(height: Space.sm),
          Text(
            'العمولة بتتحسب على التوصيل اللي بتاخده، وبتتحصّل كاش آخر الأسبوع.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Charges extends ConsumerWidget {
  const _Charges({required this.courierUid});

  final String? courierUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final charges = ref.watch(courierChargesProvider(courierUid: courierUid));

    return switch (charges) {
      // hasError first: a provider that fails before it has ever emitted stays
      // AsyncLoading with the error hanging off it, and the error arm never fires.
      AsyncValue(hasError: true, :final error) => LuqmaErrorView(
          failure: error,
          onRetry: () =>
              ref.invalidate(courierChargesProvider(courierUid: courierUid)),
        ),
      AsyncValue(value: null) => const Center(child: CircularProgressIndicator()),
      AsyncValue(value: final rows!) when rows.isEmpty => _Empty(
          key: CourierStatementScreen.noChargesKey,
          message: 'لسه مفيش توصيلات اتحسب عليها حاجة.',
        ),
      AsyncValue(value: final rows!) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              Space.gutter, 0, Space.gutter, Space.xxxl),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
          itemBuilder: (context, i) => _ChargeRow(charge: rows[i]),
        ),
    };
  }
}

class _ChargeRow extends StatelessWidget {
  const _ChargeRow({required this.charge});

  final CourierCharge charge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    // What a rider recognises a delivery by: the shop and the order number, not a uuid.
    // Either can be missing — the embed comes back null where the policy cannot reach
    // the order — and the row still belongs here, because the money moved.
    final title = [
      if (charge.merchantName case final name? when name.isNotEmpty) name,
      if (charge.orderNumber case final number?) 'أوردر #$number',
    ].join(' · ');

    return Container(
      key: CourierStatementScreen.chargeKey(charge.orderId),
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
                  title.isEmpty ? 'توصيلة' : title,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                strings.price(charge.amount),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: charge.isReversed ? colors.textSecondary : colors.price,
                  decoration: charge.isReversed ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            switch (charge.ground) {
              // The sum in words, so «ليه الرقم ده» is answered on the line itself rather
              // than in somebody's head.
              CourierGround.platform =>
                'توصيل ${strings.price(charge.basis)} · عمولة ${_percent(charge.percent)}٪',
              CourierGround.merchantDelivery => 'توصيل المحل — مفيش عمولة',
              CourierGround.notPlatformCourier => 'مش توصيل منصة — مفيش عمولة',
            },
            style: LuqmaType.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${charge.settledAt.day}/${charge.settledAt.month}',
            style: LuqmaType.caption.copyWith(color: colors.textSecondary),
          ),
          if (charge.isReversed) ...[
            const SizedBox(height: Space.xs),
            Text(
              key: CourierStatementScreen.reversedKey(charge.orderId),
              'اترجعت — الطلب ما تمّش',
              style: LuqmaType.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  /// `10` rather than `10.0`, and `7.5` kept, because a rate is read aloud.
  static String _percent(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toString();
}

class _Payments extends ConsumerWidget {
  const _Payments({required this.courierUid});

  final String? courierUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(courierPaymentsProvider(courierUid: courierUid));
    final strings = LuqmaStrings.of(context);
    final colors = Theme.of(context).luqma;
    final theme = Theme.of(context);

    return switch (payments) {
      AsyncValue(hasError: true, :final error) => LuqmaErrorView(
          failure: error,
          onRetry: () =>
              ref.invalidate(courierPaymentsProvider(courierUid: courierUid)),
        ),
      AsyncValue(value: null) => const Center(child: CircularProgressIndicator()),
      AsyncValue(value: final rows!) when rows.isEmpty => _Empty(
          key: CourierStatementScreen.noPaymentsKey,
          message: 'لسه مسددتش حاجة.',
        ),
      AsyncValue(value: final rows!) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(
              Space.gutter, 0, Space.gutter, Space.xxxl),
          itemCount: rows.length,
          separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
          itemBuilder: (context, i) {
            final payment = rows[i];
            return Container(
              key: CourierStatementScreen.paymentKey(payment.id),
              padding: const EdgeInsets.all(Space.md),
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
                        Text('تحصيل', style: theme.textTheme.bodyMedium),
                        const SizedBox(height: Space.xs),
                        Text(
                          '${payment.createdAt.day}/${payment.createdAt.month}',
                          style: LuqmaType.caption.copyWith(color: colors.textSecondary),
                        ),
                        if (payment.note case final note? when note.isNotEmpty) ...[
                          const SizedBox(height: Space.xs),
                          Text(note,
                              style: LuqmaType.caption
                                  .copyWith(color: colors.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    strings.price(payment.amount),
                    style: theme.textTheme.titleSmall?.copyWith(color: colors.success),
                  ),
                ],
              ),
            );
          },
        ),
    };
  }
}

class _Empty extends StatelessWidget {
  const _Empty({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
      ),
    );
  }
}
