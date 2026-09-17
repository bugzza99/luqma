import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// الاشتراك — where a shop stands, and how it asks for a plan.
///
/// The owner's decisions of 2026-09-17: a plan is a monthly amount **instead of commission**;
/// the shop picks a plan and 1, 3, 6 or 12 months and says whether it pays cash or by
/// transfer; the admin confirms the money and activates. When a plan ends the shop goes back
/// to commission and keeps trading. Nothing on this screen activates anything — the request
/// is a request.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key, required this.merchantId});

  final String merchantId;

  static Key planKey(String id) => Key('subscription.plan.$id');
  static Key monthsKey(int months) => Key('subscription.months.$months');
  static const cashKey = Key('subscription.cash');
  static const transferKey = Key('subscription.transfer');
  static const referenceKey = Key('subscription.reference');
  static const sendKey = Key('subscription.send');
  static const cancelKey = Key('subscription.cancel');

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  Future<Result<List<SubscriptionRequest>>>? _requests;
  Result<List<SubscriptionRequest>>? _lastRequests;

  String? _planId;
  int _months = 1;
  SubscriptionPaymentMethod _method = SubscriptionPaymentMethod.cash;
  final _reference = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  void _reload() {
    final load = ref
        .read(subscriptionRequestRepositoryProvider)
        .forMerchant(widget.merchantId);
    setState(() {
      _requests = load;
    });
  }

  static String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';

  static String _percent(int basisPoints) {
    final whole = basisPoints ~/ 100;
    final rest = basisPoints % 100;
    if (rest == 0) return '$whole';
    return '$whole.${rest.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}';
  }

  Future<void> _send() async {
    final planId = _planId;
    if (planId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(subscriptionRequestRepositoryProvider)
        .request(
          planId: planId,
          months: _months,
          paymentMethod: _method,
          transferReference: _method == SubscriptionPaymentMethod.transfer
              ? _reference.text
              : null,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = switch (result) {
        Ok() => null,
        Err(failure: ConflictFailure()) => 'عندك طلب مستني بالفعل.',
        Err(failure: OfflineFailure()) => 'مفيش نت. جرّب تاني.',
        Err() => 'مقدرناش نبعت الطلب. جرّب تاني.',
      };
      if (result is Ok) {
        _planId = null;
        _reference.clear();
      }
    });
    if (result is Ok) _reload();
  }

  Future<void> _cancel(SubscriptionRequest request) async {
    setState(() => _busy = true);
    final result = await ref
        .read(subscriptionRequestRepositoryProvider)
        .cancel(request.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result is Err) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('مقدرناش نلغي الطلب. جرّب تاني.')),
      );
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final now = ref.watch(clockProvider)();

    final merchant = ref.watch(merchantProvider(widget.merchantId)).value;
    final term = ref.watch(subscriptionProvider(widget.merchantId)).value;
    final plans = [...?ref.watch(plansProvider).value]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Entitled while the latest term runs — independent of which plans are still on
    // offer: a plan withdrawn after a shop paid for it is still the plan it paid for.
    final hasActivePlan =
        merchant?.planId != null && term != null && term.expiresAt.isAfter(now);
    final activePlanName = !hasActivePlan
        ? null
        : plans.where((p) => p.id == merchant!.planId).firstOrNull?.name ??
              merchant!.planId!;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('الاشتراك')),
      body: FutureBuilder<Result<List<SubscriptionRequest>>>(
        future: _requests,
        builder: (context, snapshot) {
          if (snapshot.data != null) _lastRequests = snapshot.data;
          final requests =
              (snapshot.data ?? _lastRequests)?.valueOrNull ?? const [];
          final pending = requests.where((r) => r.isPending).firstOrNull;
          final latest = requests.firstOrNull;
          final rejected = latest?.status == SubscriptionRequestStatus.rejected
              ? latest
              : null;

          Plan? planOf(String id) => plans.where((p) => p.id == id).firstOrNull;

          // Not lazy: a short page, and the form below the plans must exist to be filled in.
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.gutter,
              Space.gutter,
              Space.xxxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Where the shop stands.
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (activePlanName != null) ...[
                        Text(
                          'باقة $activePlanName شغالة',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          'مفيش عمولة على طلباتك لحد ${_date(term!.expiresAt)}.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          'لما تخلص بترجع للعمولة والمحل بيفضل شغال. تقدر تجدد من تحت.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ] else ...[
                        Text(
                          'مش مشترك في باقة',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          merchant?.revenueModel == RevenueModel.commission
                              ? 'بتدفع عمولة ${_percent(merchant!.revenueValue)}% على الأكل بس. '
                                    'الاشتراك مبلغ ثابت كل شهر ومفيش عمولة على الطلبات.'
                              : 'الاشتراك مبلغ ثابت كل شهر ومفيش عمولة على الطلبات.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),

                if (pending != null) ...[
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'طلبك مستني تأكيد الإدارة',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          'باقة ${planOf(pending.planId)?.name ?? ''} · ${pending.months} شهر · '
                          '${strings.price(pending.quotedAmount)}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          pending.paymentMethod ==
                                  SubscriptionPaymentMethod.cash
                              ? 'الدفع كاش — الإدارة هتكلمك.'
                              : 'تحويل${pending.transferReference == null ? '' : ' — رقم العملية ${pending.transferReference}'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: Space.md),
                        OutlinedButton(
                          key: SubscriptionScreen.cancelKey,
                          onPressed: _busy ? null : () => _cancel(pending),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.danger,
                            minimumSize: const Size.fromHeight(Sizes.minTarget),
                          ),
                          child: const Text('إلغاء الطلب'),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  if (rejected != null) ...[
                    _Card(
                      child: Text(
                        'طلبك الأخير اترفض: ${rejected.rejectReason ?? ''}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.danger,
                        ),
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                  ],
                  Text(
                    activePlanName != null ? 'جدّد أو غيّر الباقة' : 'اختار باقة',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: Space.sm),
                  for (final plan in plans) ...[
                    _PlanOption(
                      key: SubscriptionScreen.planKey(plan.id),
                      plan: plan,
                      selected: _planId == plan.id,
                      price: strings.price(plan.priceMonthly),
                      onTap: () => setState(() => _planId = plan.id),
                    ),
                    const SizedBox(height: Space.sm),
                  ],
                  if (_planId != null) ...[
                    const SizedBox(height: Space.md),
                    Text('المدة', style: theme.textTheme.titleSmall),
                    const SizedBox(height: Space.sm),
                    Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: [
                        for (final m in subscriptionMonths)
                          ChoiceChip(
                            key: SubscriptionScreen.monthsKey(m),
                            label: Text(m == 1 ? 'شهر' : '$m شهور'),
                            selected: _months == m,
                            onSelected: (_) => setState(() => _months = m),
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.sm),
                    Text(
                      'الإجمالي ${strings.price((planOf(_planId!)?.priceMonthly ?? 0) * _months)}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: Space.md),
                    Text('هتدفع إزاي؟', style: theme.textTheme.titleSmall),
                    const SizedBox(height: Space.sm),
                    Wrap(
                      spacing: Space.sm,
                      children: [
                        ChoiceChip(
                          key: SubscriptionScreen.cashKey,
                          label: const Text('كاش'),
                          selected: _method == SubscriptionPaymentMethod.cash,
                          onSelected: (_) => setState(
                            () => _method = SubscriptionPaymentMethod.cash,
                          ),
                        ),
                        ChoiceChip(
                          key: SubscriptionScreen.transferKey,
                          label: const Text('تحويل (فودافون كاش / إنستاباي)'),
                          selected:
                              _method == SubscriptionPaymentMethod.transfer,
                          onSelected: (_) => setState(
                            () => _method = SubscriptionPaymentMethod.transfer,
                          ),
                        ),
                      ],
                    ),
                    if (_method == SubscriptionPaymentMethod.transfer) ...[
                      const SizedBox(height: Space.sm),
                      TextField(
                        key: SubscriptionScreen.referenceKey,
                        controller: _reference,
                        maxLength: 80,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                          labelText: 'رقم العملية (اختياري)',
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.sm),
                    Text(
                      'الاشتراك بيتفعّل أول ما الإدارة تتأكد إن الفلوس وصلت.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: Space.sm),
                      Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.md),
                    FilledButton(
                      key: SubscriptionScreen.sendKey,
                      onPressed: _busy ? null : _send,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(Sizes.minTarget),
                      ),
                      child: const Text('ابعت طلب الاشتراك'),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: Elevations.card,
      ),
      child: child,
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({
    super.key,
    required this.plan,
    required this.selected,
    required this.price,
    required this.onTap,
  });

  final Plan plan;
  final bool selected;
  final String price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    return Material(
      color: colors.card,
      borderRadius: Radii.cardAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.cardAll,
        child: Container(
          constraints: const BoxConstraints(minHeight: Sizes.minTarget),
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            borderRadius: Radii.cardAll,
            border: Border.all(
              color: selected ? colors.brand : colors.hairline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.name, style: theme.textTheme.titleMedium),
                    Text(
                      'مفيش عمولة على الطلبات',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Text('$price / شهر', style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
