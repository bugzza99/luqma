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
  static const collectKey = Key('billing.collect');
  static const collectAmountKey = Key('billing.collectAmount');
  static const confirmCollectKey = Key('billing.confirmCollect');
  static const collectedKey = Key('billing.collected');
  static const creditKey = Key('billing.credit');
  static const confirmModelKey = Key('billing.confirmModel');
  static const customRateKey = Key('billing.customRate');
  static const toppedUpKey = Key('billing.toppedUp');
  static const recordedKey = Key('billing.recorded');
  static const paymentSummaryKey = Key('billing.paymentSummary');

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
    RevenueModel.commission: 'نسبة من أكل كل أوردر يتسلّم — مش من التوصيل.',
    RevenueModel.prepaid:
        'مبلغ ثابت بيتخصم من الرصيد على كل أوردر. لما الرصيد يخلص، '
        'المطعم بيوقف استقبال طلبات.',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantAsync = ref.watch(merchantProvider(merchantId));
    final merchant = merchantAsync.value;
    final colors = Theme.of(context).luqma;
    // Watched, not merely read when a payment is recorded: every entry on this screen
    // is stamped with who wrote it down, so the session has to be live and resolved
    // before any of it runs — otherwise the record silently does nothing.
    ref.watch(currentIdentityProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: Text(merchant?.name ?? 'الحساب')),
      // Failing is not loading: a shop that could not be read used to spin here for ever,
      // on the one screen where the owner is standing with cash in his hand.
      body: merchant == null
          ? (merchantAsync.hasError
              ? LuqmaErrorView(
                  failure: merchantAsync.error,
                  onRetry: () => ref.invalidate(merchantProvider(merchantId)),
                )
              : const Center(child: CircularProgressIndicator()))
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
                  // Shown whenever there is an account to read. Not only under
                  // commission: a merchant moved to a subscription with a debt still
                  // outstanding is exactly the case where somebody has to be able to
                  // collect it, and hiding the card would strand the money.
                  if (merchant.revenueModel != RevenueModel.subscription ||
                    merchant.commissionOwed != 0) ...[
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
  // A shop that still says 'subscription' is on commission underneath its plan: a plan is
  // what means a monthly amount now (20261010000000), and the model is what applies once it
  // lapses. So the choice here is commission or prepaid, never subscription.
  late RevenueModel _chosen = widget.merchant.revenueModel == RevenueModel.subscription
      ? RevenueModel.commission
      : widget.merchant.revenueModel;
  late bool _custom = widget.merchant.commissionCustom;
  late final _rate = TextEditingController(text: _initialRate());
  String? _rateError;
  bool _saving = false;

  /// Switching between a percentage and a fee in pounds must not carry the number across:
  /// «10» means ten percent under one and ten pounds under the other.
  void _choose(RevenueModel model) {
    if (model == _chosen) return;
    setState(() {
      _chosen = model;
      _rateError = null;
      _rate.text = model == widget.merchant.revenueModel ? _initialRate() : '';
    });
  }

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
  bool get _needsRate =>
      _chosen == RevenueModel.prepaid || (_chosen == RevenueModel.commission && _custom);

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
        if (percent == null || percent < 0 || percent > 100) {
          // Said beside the field. The button used to do nothing at all, which reads as a
          // broken screen rather than as a wrong number.
          setState(() => _rateError = 'اكتب نسبة من 0 لـ 100');
          return;
        }
        value = (percent * 100).round();
      } else {
        final fee = Money.parse(_rate.text);
        if (fee == null || fee <= 0) {
          setState(() => _rateError = 'اكتب مبلغ صحيح بالجنيه');
          return;
        }
        value = fee;
      }
    }
    setState(() => _rateError = null);

    // What is about to change, in one sentence, before it changes: this is how the shop is
    // charged from the next order on.
    final rate = ref.read(appConfigProvider).defaultCommissionPercent;
    final summary = switch (_chosen) {
      RevenueModel.commission when !_custom =>
        '${MerchantBillingScreen._modelNames[_chosen]} — النسبة الموحّدة ${_percent(rate)}%',
      RevenueModel.commission =>
        '${MerchantBillingScreen._modelNames[_chosen]} — نسبة خاصة ${value / 100}%',
      RevenueModel.prepaid =>
        '${MerchantBillingScreen._modelNames[_chosen]} — ${Money.format(value)} ج على كل أوردر',
      RevenueModel.subscription => MerchantBillingScreen._modelNames[_chosen]!,
    };
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تغيير طريقة الحساب'),
        content: Text('من الأوردر الجاي، ${widget.merchant.name} هيتحاسب بـ: $summary'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            key: MerchantBillingScreen.confirmModelKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('غيّر'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() => _saving = true);
    // Only the two columns this card is about: a full save from the copy this screen loaded
    // would put back whatever else the shop looked like then.
    final repo = ref.read(merchantRepositoryProvider);
    final result = _chosen == RevenueModel.commission
        ? await repo.setShopCommission(widget.merchant.id, customBps: _custom ? value : null)
        : await repo.setRevenueModel(widget.merchant.id, _chosen, value);
    if (!mounted) return;
    setState(() => _saving = false);
    ref.invalidate(merchantProvider(widget.merchant.id));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(result is Ok
            ? 'اتحفظت طريقة الحساب'
            : 'مااتحفظتش. اتأكد من النت وجرّب تاني.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return _Card(
      title: 'طريقة الحساب',
      child: RadioGroup<RevenueModel>(
        groupValue: _chosen,
        onChanged: (v) => _choose(v ?? _chosen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final model in const [RevenueModel.commission, RevenueModel.prepaid])
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
                          color: colors.brand,
                          borderRadius: Radii.pillAll,
                        ),
                        child: Text(
                          'الحالي',
                          style: LuqmaType.caption.copyWith(
                            color: colors.onBrand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                subtitle: Text(
                  MerchantBillingScreen._modelNotes[model]!,
                  style: LuqmaType.bodySmall.copyWith(color: colors.textSecondary),
                ),
              ),
            if (_chosen == RevenueModel.commission) ...[
              const SizedBox(height: Space.sm),
              SwitchListTile(
                key: MerchantBillingScreen.customRateKey,
                contentPadding: EdgeInsets.zero,
                value: _custom,
                onChanged: (v) => setState(() {
                  _custom = v;
                  _rateError = null;
                  if (!v) _rate.text = '';
                }),
                title: const Text('نسبة خاصة للمحل ده'),
                subtitle: Text(
                  _custom
                      ? 'النسبة دي للمحل ده بس، ومش هتتغير لما تغيّر النسبة الموحّدة.'
                      : 'بيتبع النسبة الموحّدة: '
                          '${_percent(ref.watch(appConfigProvider).defaultCommissionPercent)}%'
                          ' — بتتغير من «الإعدادات».',
                  style: LuqmaType.bodySmall.copyWith(color: colors.textSecondary),
                ),
              ),
            ],
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
                  errorText: _rateError,
                ),
              ),
            ],
            const SizedBox(height: Space.md),
            FilledButton(
              key: MerchantBillingScreen.saveModelKey,
              onPressed: _saving ? null : _save,
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

    // One id for this top-up, made before the first attempt and reused by every retry: the
    // server credits a receipt once. Without it a reply lost on the shop's wifi, then «جرّب
    // تاني», credited the same cash twice.
    final receipt = newClientOrderId();
    Future<void> attempt() async {
      final result = await ref.read(billingRepositoryProvider).topUpWallet(
            merchantId: merchant.id,
            amount: amount,
            recordedBy: by,
            receiptId: receipt,
          );
      ref.invalidate(merchantProvider(merchant.id));
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        result is Ok
            ? SnackBar(
                key: MerchantBillingScreen.toppedUpKey,
                content: Text('اتسجّل شحن ${LuqmaStrings.of(context).price(amount)}'),
              )
            : SnackBar(
                content: const Text('الشحن مااتسجّلش. جرّب تاني — مش هيتسجّل مرتين.'),
                action: SnackBarAction(label: 'جرّب تاني', onPressed: attempt),
              ),
      );
    }

    await attempt();
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

    final subscriptionAsync = ref.watch(subscriptionProvider(merchantId));
    final plansAsync = ref.watch(plansProvider);
    final subscription = subscriptionAsync.value;
    final plans = plansAsync.value ?? const <Plan>[];

    // A term that could not be read must not be shown as «لسه مدفعش اشتراك»: that is a
    // sentence the owner might repeat to the shop.
    if (subscriptionAsync.hasError && !subscriptionAsync.hasValue ||
        plansAsync.hasError && !plansAsync.hasValue) {
      return _Card(
        title: 'الاشتراك',
        child: LuqmaErrorView(
          failure: subscriptionAsync.error ?? plansAsync.error,
          compact: true,
          onRetry: () {
            ref.invalidate(subscriptionProvider(merchantId));
            ref.invalidate(plansProvider);
          },
        ),
      );
    }
    if (!subscriptionAsync.hasValue) {
      return const _Card(
        title: 'الاشتراك',
        child: Center(child: CircularProgressIndicator()),
      );
    }
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
                'فاضل ${_days(subscription.daysLeftAt(now))}',
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
    final now = ref.read(clockProvider)();
    final current = ref.read(subscriptionProvider(merchantId)).value;
    final payment = await showDialog<({String planId, int amount, int months})>(
      context: context,
      builder: (_) => _PaymentDialog(
        plans: plans,
        // Where the new term starts: after the current one if it is still running, which is
        // what the server does, so the date the dialog promises is the date that happens.
        startsAt: current != null && current.isActiveAt(now) ? current.expiresAt : now,
      ),
    );

    if (payment == null || !context.mounted) return;

    final by = ref.read(currentIdentityProvider).value?.uid;
    if (by == null) return;

    // One receipt for this payment, reused by every retry: the server records it once.
    final receipt = newClientOrderId();
    Future<void> attempt() async {
      final result = await ref.read(billingRepositoryProvider).recordPayment(
            merchantId: merchantId,
            planId: payment.planId,
            amount: payment.amount,
            months: payment.months,
            recordedBy: by,
            receiptId: receipt,
          );
      ref.invalidate(merchantProvider(merchantId));
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        result is Ok
            ? SnackBar(
                key: MerchantBillingScreen.recordedKey,
                content: Text(
                  'اتسجّلت الدفعة — الاشتراك لحد ${_date((result as Ok<Subscription>).value.expiresAt)}',
                ),
              )
            : SnackBar(
                content: const Text('الدفعة مااتسجّلتش. جرّب تاني — مش هتتسجّل مرتين.'),
                action: SnackBarAction(label: 'جرّب تاني', onPressed: attempt),
              ),
      );
    }

    await attempt();
  }
}

String _percent(double p) =>
    p == p.roundToDouble() ? p.toInt().toString() : p.toString();

/// «يوم واحد», «يومين», «3 أيام», «11 يوم» — Arabic counts days differently at each size,
/// and the old string-replace on an order count could produce «يومات».
String _days(int n) => switch (n) {
      <= 0 => 'أقل من يوم',
      1 => 'يوم واحد',
      2 => 'يومين',
      >= 3 && <= 10 => '$n أيام',
      _ => '$n يوم',
    };

String _date(DateTime at) {
  const months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  final local = at.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.plans, required this.startsAt});

  final List<Plan> plans;
  final DateTime startsAt;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _months = TextEditingController(text: '1');
  String? _planId;
  String? _error;

  int? get _monthsValue {
    final months = int.tryParse(ArabicDigits.fold(_months.text).trim());
    return months == null || months < 1 ? null : months;
  }

  @override
  void dispose() {
    _months.dispose();
    super.dispose();
  }

  void _confirm() {
    final planId = _planId;
    final months = _monthsValue;
    if (planId == null || months == null) {
      setState(() => _error = planId == null ? 'اختار الخطة' : 'اكتب عدد شهور صحيح');
      return;
    }

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
              onChanged: (_) => setState(() => _error = null),
              decoration: const InputDecoration(labelText: 'كام شهر'),
            ),
            // The money and the dates, together, before anything is recorded: what the shop
            // hands over and until when it is paid.
            if (_planId != null && _monthsValue != null) ...[
              const SizedBox(height: Space.md),
              Text(
                key: MerchantBillingScreen.paymentSummaryKey,
                () {
                  final plan = widget.plans.firstWhere((p) => p.id == _planId);
                  final months = _monthsValue!;
                  final ends = widget.startsAt.add(Duration(days: 30 * months));
                  return 'المبلغ: ${Money.format(plan.priceMonthly * months)} ج\n'
                      'الاشتراك هيبقى لحد ${_date(ends)}';
                }(),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).luqma.danger),
              ),
            ],
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
  String? _error;

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
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(
          labelText: widget.label,
          suffixText: 'ج',
          errorText: _error,
        ),
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
            if (amount == null || amount <= 0) {
              setState(() => _error = 'اكتب مبلغ صحيح بالجنيه');
              return;
            }
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
      title: 'إجمالي الحساب من البداية',
      child: LuqmaAsyncView(
        value: summary,
        onRetry: () => ref.invalidate(settlementSummaryProvider(merchant.id)),
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
              LuqmaBillLine(
                label: strings.orderCount(s.orders),
                value: strings.price(s.taken),
              ),
              if (s.platformOwes > 0) ...[
                const SizedBox(height: Space.sm),
                LuqmaBillLine(
                  key: MerchantBillingScreen.platformOwesKey,
                  // Netted against the commission by a person, not by this screen: what
                  // the platform owes for its own discounts is a different conversation
                  // from what the merchant owes, and collapsing them into one number is
                  // how a merchant stops being able to check either.
                  label: 'لقمة عليها للمطعم',
                  value: strings.price(s.platformOwes),
                  emphasis: true,
                ),
              ],
            ],
            // Outside the branch above, deliberately: this is the running total on the
            // merchant, not a sum of the page. It was inside, and a merchant carrying a
            // debt with nothing on this page — a debt from before, or a page that has
            // scrolled past its charges — read as "لسه مفيش أوردرات اتسلّمت" with the
            // money nowhere on the screen at all.
            if (merchant.revenueModel == RevenueModel.commission ||
                  merchant.commissionOwed != 0) ...[
              const SizedBox(height: Space.sm),
              LuqmaBillLine(
                key: merchant.commissionOwed < 0
                    ? MerchantBillingScreen.creditKey
                    : MerchantBillingScreen.owedKey,
                // Negative means the merchant handed over more than they owed — an
                // admin in a shop takes what is on the counter rather than arguing
                // about five pounds — and it is credit the next delivery eats into.
                // Said in those words rather than shown as a minus sign, which reads
                // as an error on a screen about money.
                label: merchant.commissionOwed < 0
                    ? 'رصيد للمطعم عندنا'
                    : 'المستحق على المطعم',
                value: strings.price(merchant.commissionOwed.abs()),
                emphasis: merchant.commissionOwed < 0,
              ),
            ],
            // Only where there is something to take. A merchant who owes nothing and a
            // merchant who is owed credit both get no button: the first has nothing to
            // pay, and handing money *back* is a different act that this screen must not
            // be able to perform by accident.
            if (merchant.commissionOwed > 0) ...[
              const SizedBox(height: Space.md),
              FilledButton.icon(
                key: MerchantBillingScreen.collectKey,
                onPressed: () => _collect(context, ref),
                icon: const Icon(Icons.payments_outlined, size: Sizes.iconSm),
                label: const Text('سجّل تحصيل'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _collect(BuildContext context, WidgetRef ref) async {
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => const _AmountDialog(
        title: 'تحصيل عمولة',
        fieldKey: MerchantBillingScreen.collectAmountKey,
        confirmKey: MerchantBillingScreen.confirmCollectKey,
        label: 'المبلغ المستلم',
      ),
    );

    if (amount == null || !context.mounted) return;

    // One id for this collection, made before the first attempt and reused by every
    // retry. Without it a reply lost on a shop's wifi turned into a second subtraction:
    // the function took the money again and wrote a second receipt, and a 100 debt became
    // 100 of credit — money the platform now owes for cash it collected once.
    final attempt = newClientOrderId();

    final result = await ref
        .read(settlementRepositoryProvider)
        .recordPayment(
          merchantId: merchant.id,
          amount: amount,
          clientPaymentId: attempt,
        );
    if (!context.mounted) return;

    // The result is read rather than discarded. A collection that failed and a
    // collection that worked look identical if the only feedback is the screen
    // refreshing — and the admin is standing in a shop holding the cash.
    switch (result) {
      case Ok(:final value):
        ref.invalidate(merchantProvider(merchant.id));
        ref.invalidate(commissionPaymentsProvider(merchant.id));
        ref.invalidate(settlementSummaryProvider(merchant.id));
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            key: MerchantBillingScreen.collectedKey,
            content: Text(
              value > 0
                  ? 'اتسجّل. الباقي ${LuqmaStrings.of(context).price(value)}'
                  : 'اتسجّل. الحساب مقفول.',
            ),
          ),
        );
      case Err():
        // «جرّب تاني» is now safe advice rather than a guess. A failure here can mean the
        // request never landed *or* that it landed and the reply did not, and the two are
        // indistinguishable from this side — so the sentence used to invite the admin to
        // collect the same cash twice. Retrying carries the same id, which the server
        // answers with the original receipt.
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: const Text('التحصيل مااتسجّلش. جرّب تاني.'),
            action: SnackBarAction(
              label: 'جرّب تاني',
              onPressed: () async {
                final retry = await ref
                    .read(settlementRepositoryProvider)
                    .recordPayment(
                      merchantId: merchant.id,
                      amount: amount,
                      clientPaymentId: attempt,
                    );
                if (retry is Ok) {
                  ref.invalidate(merchantProvider(merchant.id));
                  ref.invalidate(commissionPaymentsProvider(merchant.id));
                  ref.invalidate(settlementSummaryProvider(merchant.id));
                }
              },
            ),
          ),
        );
    }
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
          boxShadow: Elevations.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.md),
            child,
          ],
        ),
      ),
    );
  }
}
