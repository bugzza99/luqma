import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../billing/merchant_billing_screen.dart';
import '../shell/layout.dart';

/// الاشتراكات — the shops asking for a plan, and where every shop's plan stands.
///
/// The owner's decisions of 2026-09-17: a plan is a monthly amount instead of commission; a
/// shop asks from MerchantApp and says whether it pays cash or by transfer; the admin
/// confirms the money and activates — with a different amount when there was a discount — or
/// rejects with a reason the shop sees.
class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  static Key activateKey(String id) => Key('subscriptions.activate.$id');
  static Key rejectKey(String id) => Key('subscriptions.reject.$id');
  static Key filterKey(PlanStanding? standing) =>
      Key('subscriptions.filter.${standing?.name ?? 'all'}');
  static const amountKey = Key('subscriptions.amount');
  static const reasonKey = Key('subscriptions.reason');
  static const confirmKey = Key('subscriptions.confirm');
  static const requestsTabKey = Key('subscriptions.tab.requests');
  static const shopsTabKey = Key('subscriptions.tab.shops');

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  Future<(Result<List<SubscriptionRequest>>, Result<List<SubscriptionOverviewRow>>)>? _load;
  (Result<List<SubscriptionRequest>>, Result<List<SubscriptionOverviewRow>>)? _last;
  PlanStanding? _filter;

  /// Requests with an answer on its way. A second tap on «فعّل» while the first is still
  /// going would send a second request — the server's lock refuses it, but the admin would
  /// read the refusal as a failure of the first.
  final Set<String> _answering = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final repo = ref.read(subscriptionRequestRepositoryProvider);
    Future<(Result<List<SubscriptionRequest>>, Result<List<SubscriptionOverviewRow>>)>
        both() async => (await repo.pending(), await repo.overview());
    final load = both();
    setState(() {
      _load = load;
    });
  }

  static String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

  static String _pounds(int piastres) =>
      piastres % 100 == 0 ? '${piastres ~/ 100}' : (piastres / 100).toStringAsFixed(2);

  /// A typed amount in pounds into piastres. Not `Money.parse`: that caps at a meal's price,
  /// and a year of a plan is legitimately more than any meal.
  static int? _amount(String raw) {
    final text = ArabicDigits.fold(raw)
        .replaceAll(ArabicDigits.decimalSeparator, '.')
        .replaceAll('ج', '')
        .trim();
    if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(text)) return null;
    final parts = text.split('.');
    final fraction = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
    return int.parse(parts[0]) * 100 + int.parse(fraction);
  }

  Future<void> _activate(SubscriptionRequest request) async {
    final strings = LuqmaStrings.of(context);
    final amount = TextEditingController(text: _pounds(request.quotedAmount));
    String? error;
    final piastres = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('فعّل الاشتراك'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('المطلوب ${strings.price(request.quotedAmount)}. لو عملت خصم اكتب المبلغ اللي اتدفع.'),
              const SizedBox(height: Space.md),
              TextField(
                key: SubscriptionsScreen.amountKey,
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: 'المبلغ اللي اتدفع بالجنيه', errorText: error),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: SubscriptionsScreen.confirmKey,
              onPressed: () {
                final value = _amount(amount.text);
                if (value == null) {
                  setDialogState(() => error = 'اكتب مبلغ صحيح');
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('فعّل'),
            ),
          ],
        ),
      ),
    );
    // Not disposed here: the dialog's closing animation still builds the field for a few
    // frames, and a disposed controller throws. It goes with the closure.
    if (piastres == null || !mounted || !_answering.add(request.id)) return;
    setState(() {});
    final result = await ref.read(subscriptionRequestRepositoryProvider).activate(
          request.id,
          amount: piastres == request.quotedAmount ? null : piastres,
        );
    _answering.remove(request.id);
    _answered(result, 'الاشتراك اتفعّل');
  }

  Future<void> _reject(SubscriptionRequest request) async {
    final reason = TextEditingController();
    String? error;
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('ارفض الطلب'),
          content: TextField(
            key: SubscriptionsScreen.reasonKey,
            controller: reason,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'السبب — المحل هيشوفه',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              key: SubscriptionsScreen.confirmKey,
              onPressed: () {
                if (reason.text.trim().isEmpty) {
                  setDialogState(() => error = 'اكتب السبب');
                  return;
                }
                Navigator.of(dialogContext).pop(reason.text.trim());
              },
              child: const Text('ارفض'),
            ),
          ],
        ),
      ),
    );
    if (text == null || !mounted || !_answering.add(request.id)) return;
    setState(() {});
    final result = await ref.read(subscriptionRequestRepositoryProvider).reject(request.id, text);
    _answering.remove(request.id);
    _answered(result, 'الطلب اترفض');
  }

  void _answered(Result<void> result, String done) {
    if (!mounted) return;
    final message = switch (result) {
      Ok() => done,
      Err(failure: ConflictFailure()) => 'الطلب ده اتردّ عليه قبل كده.',
      Err(failure: OfflineFailure()) => 'مفيش نت. جرّب تاني.',
      Err() => 'مقدرناش نحفظ. جرّب تاني.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final now = ref.watch(clockProvider)();
    final plans = ref.watch(plansProvider).value ?? const <Plan>[];
    String planName(String id) => plans.where((p) => p.id == id).firstOrNull?.name ?? id;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الاشتراكات'),
          bottom: const TabBar(
            tabs: [
              Tab(key: SubscriptionsScreen.requestsTabKey, text: 'الطلبات'),
              Tab(key: SubscriptionsScreen.shopsTabKey, text: 'المحلات'),
            ],
          ),
        ),
        body: AdminContent(
          child: FutureBuilder(
            future: _load,
            builder: (context, snapshot) {
              if (snapshot.data != null) _last = snapshot.data;
              final data = snapshot.data ?? _last;
              if (data == null) return const Center(child: CircularProgressIndicator());
              final (requestsResult, rowsResult) = data;
              if (requestsResult case Err(:final failure)) {
                return LuqmaErrorView(failure: failure, onRetry: _reload);
              }
              if (rowsResult case Err(:final failure)) {
                return LuqmaErrorView(failure: failure, onRetry: _reload);
              }
              final pending = requestsResult.valueOrNull!;
              final rows = rowsResult.valueOrNull!;
              String shopName(String id) =>
                  rows.where((r) => r.merchantId == id).firstOrNull?.merchantName ?? 'محل';

              final filtered = _filter == null
                  ? rows
                  : rows.where((r) => r.standingAt(now) == _filter).toList();

              Widget card(Widget child) => Container(
                    padding: const EdgeInsets.all(Space.md),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: Radii.cardAll,
                      border: Border.all(color: colors.hairline),
                    ),
                    child: child,
                  );

              return TabBarView(
                children: [
                  // Requests.
                  pending.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(Space.xl),
                            child: Text(
                              'مفيش طلبات اشتراك مستنية. المحلات بتطلب من «الاشتراك» في لقمة شريك.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: colors.textSecondary),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(Space.gutter),
                          itemCount: pending.length,
                          separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                          itemBuilder: (context, i) {
                            final r = pending[i];
                            return card(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(shopName(r.merchantId), style: theme.textTheme.titleMedium),
                                  Text(
                                    'باقة ${planName(r.planId)} · '
                                    '${r.months == 1 ? 'شهر' : '${r.months} شهور'} · '
                                    '${strings.price(r.quotedAmount)}',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  Text(
                                    r.paymentMethod == SubscriptionPaymentMethod.cash
                                        ? 'كاش — لسه هتحصّل'
                                        : 'تحويل${r.transferReference == null ? ' — من غير رقم عملية' : ' — رقم العملية ${r.transferReference}'}',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: colors.textSecondary),
                                  ),
                                  const SizedBox(height: Space.sm),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton(
                                          key: SubscriptionsScreen.activateKey(r.id),
                                          onPressed:
                                              _answering.contains(r.id) ? null : () => _activate(r),
                                          style: FilledButton.styleFrom(
                                            minimumSize: const Size.fromHeight(Sizes.minTarget),
                                          ),
                                          child: const Text('فعّل'),
                                        ),
                                      ),
                                      const SizedBox(width: Space.sm),
                                      Expanded(
                                        child: OutlinedButton(
                                          key: SubscriptionsScreen.rejectKey(r.id),
                                          onPressed:
                                              _answering.contains(r.id) ? null : () => _reject(r),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: colors.danger,
                                            minimumSize: const Size.fromHeight(Sizes.minTarget),
                                          ),
                                          child: const Text('ارفض'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                  // Shops.
                  ListView(
                    padding: const EdgeInsets.all(Space.gutter),
                    children: [
                      Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final (standing, label) in const [
                            (null, 'الكل'),
                            (PlanStanding.active, 'شغالة'),
                            (PlanStanding.endingSoon, 'بتخلص قريب'),
                            (PlanStanding.expired, 'خلصت'),
                            (PlanStanding.none, 'من غير باقة'),
                          ])
                            ChoiceChip(
                              key: SubscriptionsScreen.filterKey(standing),
                              label: Text(label),
                              selected: _filter == standing,
                              onSelected: (_) => setState(() => _filter = standing),
                            ),
                        ],
                      ),
                      const SizedBox(height: Space.md),
                      for (final row in filtered) ...[
                        InkWell(
                          borderRadius: Radii.cardAll,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => MerchantBillingScreen(merchantId: row.merchantId),
                            ),
                          ),
                          child: card(
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(row.merchantName, style: theme.textTheme.titleMedium),
                                      Text(
                                        switch (row.standingAt(now)) {
                                          PlanStanding.none => 'من غير باقة',
                                          _ => 'باقة ${row.planName ?? row.planId} · لحد ${_date(row.planExpiresAt!)}',
                                        },
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: colors.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                _StandingChip(standing: row.standingAt(now)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StandingChip extends StatelessWidget {
  const _StandingChip({required this.standing});

  final PlanStanding standing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final (label, color) = switch (standing) {
      PlanStanding.active => ('شغالة', colors.success),
      PlanStanding.endingSoon => ('بتخلص قريب', colors.accent),
      PlanStanding.expired => ('خلصت', colors.danger),
      PlanStanding.none => ('من غير باقة', colors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(label, style: LuqmaType.caption.copyWith(color: color)),
    );
  }
}
