import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';

/// How one merchant pays, and recording that they did.
///
/// Every number here is cash somebody handed over in a shop. Nothing is inferred and
/// nothing is undoable from the app: a mistake is corrected by recording the opposite,
/// the way a ledger works, and every entry carries the name of whoever wrote it down.
class MerchantBillingScreen extends ConsumerWidget {
  const MerchantBillingScreen({super.key, required this.merchantId});

  final String merchantId;

  static const saveModelKey = Key('billing.saveModel');
  static const rateKey = Key('billing.rate');
  static const termKey = Key('billing.term');
  static const expiredKey = Key('billing.expired');
  static const noTermKey = Key('billing.noTerm');
  static const recordKey = Key('billing.record');
  static const monthsKey = Key('billing.months');
  static const confirmPaymentKey = Key('billing.confirmPayment');
  static const walletKey = Key('billing.wallet');
  static const topUpKey = Key('billing.topUp');
  static const amountKey = Key('billing.amount');
  static const confirmTopUpKey = Key('billing.confirmTopUp');
  static const exhaustedKey = Key('billing.exhausted');
  static const listKey = Key('billing.list');
  static const settlementsKey = Key('billing.settlements');
  static const owedKey = Key('billing.owed');
  static const platformOwesKey = Key('billing.platformOwes');
  static const noSettlementsKey = Key('billing.noSettlements');

  static Key modelKey(RevenueModel model) => Key('billing.model.${model.name}');
  static Key currentModelKey(RevenueModel model) => Key('billing.current.${model.name}');
  static Key planChoiceKey(String planId) => Key('billing.plan.$planId');

  static const _modelNames = {
    RevenueModel.subscription: 'اشتراك شهري',
    RevenueModel.commission: 'عمولة على كل أوردر',
    RevenueModel.prepaid: 'رصيد مدفوع مقدماً',
  };

  static const _modelNotes = {
    RevenueModel.subscription: 'مبلغ ثابت في الشهر. مفيش حساب على الأوردرات.',
    RevenueModel.commission: 'نسبة من كل أوردر يتسلّم.',
    RevenueModel.prepaid:
        'مبلغ ثابت بيتخصم من الرصيد على كل أوردر. لما الرصيد يخلص، '
        'المطعم بيوقف استقبال طلبات.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchant = ref.watch(merchantProvider(merchantId)).value;
    final colors = Theme.of(context).luqma;
    // Watched, not merely read when a payment is recorded: every entry on this screen
    // is stamped with who wrote it down, so the session has to be live and resolved
    // before any of it runs — otherwise the record silently does nothing.
    ref.watch(currentIdentityProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: Text(merchant?.name ?? 'الحساب')),
      body: merchant == null
          ? const Center(child: CircularProgressIndicator())
          : AdminContent(
              child: ListView(
                // Keyed so a test can scroll *this* list. The screen has several nested
                // scrollables, and a finder that picks by type throws on the ambiguity
                // rather than choosing.
                key: listKey,
                padding: const EdgeInsets.all(Space.gutter),
                children: [
                  _Model(merchant: merchant),
                  const SizedBox(height: Space.xl),
                  if (merchant.revenueModel == RevenueModel.prepaid) ...[
                    _Wallet(merchant: merchant),
                    const SizedBox(height: Space.xl),
                  ],
                  _Term(merchantId: merchantId),
                  // Under a subscription nothing is taken per order, so there is no
                  // account to read — the term above is the whole arrangement.
                  if (merchant.revenueModel != RevenueModel.subscription) ...[
                    const SizedBox(height: Space.xl),
                    _Settlements(merchant: merchant),
                  ],
                ],
              ),
            ),
    );
  }
}

class _Model extends ConsumerStatefulWidget {
  const _Model({required this.merchant});

  final Merchant merchant;

  @override
  ConsumerState<_Model> createState() => _ModelState();
}

class _ModelState extends ConsumerState<_Model> {
  late RevenueModel _chosen = widget.merchant.revenueModel;
  late final _rate = TextEditingController(text: _initialRate());

  String _initialRate() {
    final merchant = widget.merchant;
    return switch (merchant.revenueModel) {
      // Basis points are what the engine works in; percent is what a person says.
      RevenueModel.commission => (merchant.revenueValue / 100).toStringAsFixed(
        merchant.revenueValue % 100 == 0 ? 0 : 2,
      ),
      RevenueModel.prepaid => Money.format(merchant.revenueValue),
      RevenueModel.subscription => '',
    };
  }

  /// Whether this model needs a number alongside it.
  ///
  /// A subscription has no rate. Asking for one would be asking a question with no right
  /// answer, and storing whatever came back would be worse.
  bool get _needsRate => _chosen != RevenueModel.subscription;

  @override
  void dispose() {
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    var value = 0;

    if (_needsRate) {
      final typed = ArabicDigits.fold(_rate.text).trim();
      if (_chosen == RevenueModel.commission) {
        final percent = double.tryParse(typed);
        if (percent == null || percent < 0 || percent > 100) return;
        value = (percent * 100).round();
      } else {
        final fee = Money.parse(_rate.text);
        if (fee == null || fee <= 0) return;
        value = fee;
      }
    }

    await ref
        .read(merchantRepositoryProvider)
        .saveMerchant(
          widget.merchant.copyWith(revenueModel: _chosen, revenueValue: value),
        );
    ref.invalidate(merchantProvider(widget.merchant.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return _Card(
      title: 'طريقة الحساب',
      child: RadioGroup<RevenueModel>(
        groupValue: _chosen,
        onChanged: (v) => setState(() => _chosen = v ?? _chosen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final model in RevenueModel.values)
              RadioListTile<RevenueModel>(
                key: MerchantBillingScreen.modelKey(model),
                value: model,
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Expanded(child: Text(MerchantBillingScreen._modelNames[model]!)),
                    if (widget.merchant.revenueModel == model)
                      Container(
                        key: MerchantBillingScreen.currentModelKey(model),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.success,
                          borderRadius: Radii.pillAll,
                        ),
                        child: Text(
                          'الحالي',
                          style: LuqmaType.caption.copyWith(color: colors.onBrand),
                        ),
                      ),
                  ],
                ),
                subtitle: Text(
                  MerchantBillingScreen._modelNotes[model]!,
                  style: LuqmaType.bodySmall.copyWith(color: colors.textSecondary),
                ),
              ),
            if (_needsRate) ...[
              const SizedBox(height: Space.md),
              TextField(
                key: MerchantBillingScreen.rateKey,
                controller: _rate,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩.,]')),
                ],
                decoration: InputDecoration(
                  labelText: _chosen == RevenueModel.commission
                      ? 'النسبة'
                      : 'الخصم على كل أوردر',
                  suffixText: _chosen == RevenueModel.commission ? '%' : 'ج',
                ),
              ),
            ],
            const SizedBox(height: Space.md),
            FilledButton(
              key: MerchantBillingScreen.saveModelKey,
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(Sizes.minTarget),
              ),
              child: const Text('احفظ طريقة الحساب'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Wallet extends ConsumerWidget {
  const _Wallet({required this.merchant});

  final Merchant merchant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final canAfford = Revenue.canAffordAnOrder(merchant);

    return _Card(
      cardKey: MerchantBillingScreen.walletKey,
      title: 'الرصيد',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'الرصيد الحالي',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              Text(
                strings.price(merchant.walletBalance),
                style: LuqmaType.price.copyWith(
                  color: canAfford ? colors.price : colors.danger,
                ),
              ),
            ],
          ),
          if (!canAfford) ...[
            const SizedBox(height: Space.sm),
            Row(
              key: MerchantBillingScreen.exhaustedKey,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: Sizes.iconSm,
                  color: colors.danger,
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    // An empty wallet stops the merchant taking orders at all, so it
                    // cannot be a number sitting quietly in a corner.
                    'الرصيد مش مكفّي أوردر تاني — المطعم واقف عن استقبال الطلبات.',
                    style: LuqmaType.bodySmall.copyWith(color: colors.danger),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Space.md),
          OutlinedButton(
            key: MerchantBillingScreen.topUpKey,
            onPressed: () => _topUp(context, ref),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(Sizes.minTarget),
            ),
            child: const Text('اشحن الرصيد'),
          ),
        ],
      ),
    );
  }

  Future<void> _topUp(BuildContext context, WidgetRef ref) async {
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => const _AmountDialog(
        title: 'شحن رصيد',
        fieldKey: MerchantBillingScreen.amountKey,
        confirmKey: MerchantBillingScreen.confirmTopUpKey,
        label: 'المبلغ المستلم',
      ),
    );

    if (amount == null || !context.mounted) return;

    final by = ref.read(currentIdentityProvider).value?.uid;
    if (by == null) return;

    await ref
        .read(billingRepositoryProvider)
        .topUpWallet(merchantId: merchant.id, amount: amount, recordedBy: by);
    ref.invalidate(merchantProvider(merchant.id));
  }
}

class _Term extends ConsumerWidget {
  const _Term({required this.merchantId});

  final String merchantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final subscription = ref.watch(subscriptionProvider(merchantId)).value;
    final plans = ref.watch(plansProvider).value ?? const <Plan>[];
    // The same rule as the merchant's own view of this: an expiry is judged against the
    // injected clock, so both screens can be tested at the day the term lapses.
    final now = ref.watch(clockProvider)();

    return _Card(
      title: 'الاشتراك',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subscription == null)
            Text(
              // Never having paid is not the same as having lapsed. One is a merchant
              // who has been on Free all along; the other is a conversation to have.
              'المطعم ده لسه مدفعش اشتراك.',
              key: MerchantBillingScreen.noTermKey,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            )
          else ...[
            Row(
              key: MerchantBillingScreen.termKey,
              children: [
                Expanded(
                  child: Text(
                    plans.where((p) => p.id == subscription.planId).firstOrNull?.name ??
                        subscription.planId,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  strings.price(subscription.amount),
                  style: LuqmaType.priceSmall.copyWith(color: colors.price),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            if (subscription.isActiveAt(now))
              Text(
                'فاضل ${strings.orderCount(subscription.daysLeftAt(now)).replaceAll('طلب', 'يوم').replaceAll('طلبات', 'أيام').replaceAll('طلبًا', 'يومًا')}',
                style: LuqmaType.bodySmall.copyWith(color: colors.textSecondary),
              )
            else
              Row(
                key: MerchantBillingScreen.expiredKey,
                children: [
                  Icon(
                    Icons.event_busy_rounded,
                    size: Sizes.iconSm,
                    color: colors.danger,
                  ),
                  const SizedBox(width: Space.sm),
                  Text(
                    'الاشتراك خلص',
                    style: LuqmaType.bodySmall.copyWith(color: colors.danger),
                  ),
                ],
              ),
          ],
          const SizedBox(height: Space.md),
          FilledButton(
            key: MerchantBillingScreen.recordKey,
            onPressed: () => _record(context, ref, plans),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(Sizes.minTarget),
            ),
            child: const Text('سجّل دفعة'),
          ),
        ],
      ),
    );
  }

  Future<void> _record(BuildContext context, WidgetRef ref, List<Plan> plans) async {
    final payment = await showDialog<({String planId, int amount, int months})>(
      context: context,
      builder: (_) => _PaymentDialog(plans: plans),
    );

    if (payment == null || !context.mounted) return;

    final by = ref.read(currentIdentityProvider).value?.uid;
    if (by == null) return;

    await ref
        .read(billingRepositoryProvider)
        .recordPayment(
          merchantId: merchantId,
          planId: payment.planId,
          amount: payment.amount,
          months: payment.months,
          recordedBy: by,
        );
    ref.invalidate(merchantProvider(merchantId));
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.plans});

  final List<Plan> plans;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _months = TextEditingController(text: '1');
  String? _planId;

  @override
  void dispose() {
    _months.dispose();
    super.dispose();
  }

  void _confirm() {
    final planId = _planId;
    final months = int.tryParse(ArabicDigits.fold(_months.text).trim());
    if (planId == null || months == null || months < 1) return;

    final plan = widget.plans.firstWhere((p) => p.id == planId);
    Navigator.of(context).pop((
      planId: planId,
      // The amount follows the plan and the months rather than being typed. A figure
      // typed by hand is a figure that will one day not match what the merchant paid.
      amount: plan.priceMonthly * months,
      months: months,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('سجّل دفعة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadioGroup<String>(
              groupValue: _planId,
              onChanged: (v) => setState(() => _planId = v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final plan in widget.plans)
                    RadioListTile<String>(
                      key: MerchantBillingScreen.planChoiceKey(plan.id),
                      value: plan.id,
                      contentPadding: EdgeInsets.zero,
                      title: Text(plan.name),
                      subtitle: Text(
                        plan.isFree
                            ? 'مجانية'
                            : '${Money.format(plan.priceMonthly)} ج/شهر',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Space.md),
            TextField(
              key: MerchantBillingScreen.monthsKey,
              controller: _months,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'كام شهر'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: MerchantBillingScreen.confirmPaymentKey,
          onPressed: _confirm,
          child: const Text('سجّل'),
        ),
      ],
    );
  }
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.fieldKey,
    required this.confirmKey,
    required this.label,
  });

  final String title;
  final Key fieldKey;
  final Key confirmKey;
  final String label;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: widget.fieldKey,
        controller: _amount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩.,]'))],
        decoration: InputDecoration(labelText: widget.label, suffixText: 'ج'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: widget.confirmKey,
          onPressed: () {
            final amount = Money.parse(_amount.text);
            if (amount == null || amount <= 0) return;
            Navigator.of(context).pop(amount);
          },
          child: const Text('سجّل'),
        ),
      ],
    );
  }
}

/// What has actually been taken, and what is outstanding.
///
/// The admin's half of the same rows the merchant reads in MerchantApp, and the reason it
/// is here at all: collecting `commission_owed` is a person with a receipt, and the
/// person needs a number to ask for. Before this it was a column nothing displayed.
class _Settlements extends ConsumerWidget {
  const _Settlements({required this.merchant});

  final Merchant merchant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final summary = ref.watch(settlementSummaryProvider(merchant.id));

    return _Card(
      cardKey: MerchantBillingScreen.settlementsKey,
      title: 'الحساب على الأوردرات',
      child: LuqmaAsyncView(
        value: summary,
        onRetry: () => ref.invalidate(merchantSettlementsProvider(merchant.id)),
        builder: (context, s) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (s.orders == 0)
              Text(
                // Not an empty card. "Nothing has been delivered yet" and "the figures
                // failed to load" look identical as a blank space, and one of them is a
                // reason to phone somebody.
                'لسه مفيش أوردرات اتسلّمت.',
                key: MerchantBillingScreen.noSettlementsKey,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              )
            else ...[
              _Figure(label: strings.orderCount(s.orders), value: strings.price(s.taken)),
              if (merchant.revenueModel == RevenueModel.commission) ...[
                const SizedBox(height: Space.sm),
                _Figure(
                  figureKey: MerchantBillingScreen.owedKey,
                  // The running total, which is what somebody actually collects — the
                  // page above is the last hundred orders, the debt is since the last
                  // payment.
                  label: 'المستحق على المطعم',
                  value: strings.price(merchant.commissionOwed),
                  emphasis: colors.price,
                ),
              ],
              if (s.platformOwes > 0) ...[
                const SizedBox(height: Space.sm),
                _Figure(
                  figureKey: MerchantBillingScreen.platformOwesKey,
                  // Netted against the above by a person, not by this screen: what the
                  // platform owes for its own discounts is a different conversation from
                  // what the merchant owes in commission, and collapsing them into one
                  // number is how a merchant stops being able to check either.
                  label: 'لقمة عليها للمطعم',
                  value: strings.price(s.platformOwes),
                  emphasis: colors.success,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.emphasis,
    this.figureKey,
  });

  final String label;
  final String value;
  final Color? emphasis;
  final Key? figureKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Row(
      key: figureKey,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: colors.textSecondary),
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

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.cardKey});

  final String title;
  final Widget child;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    // A Material rather than a plain Container: the list tiles inside paint their
    // background and ink on the nearest Material ancestor, and a coloured box between
    // them and one hides every tap.
    return Material(
      key: cardKey,
      color: colors.card,
      borderRadius: Radii.cardAll,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: Space.md),
            child,
          ],
        ),
      ),
    );
  }
}
