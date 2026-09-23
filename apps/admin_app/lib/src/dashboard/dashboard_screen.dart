import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../billing/merchant_billing_screen.dart';
import '../merchants/merchants_controller.dart';
import '../shell/layout.dart';
import 'dashboard_controller.dart';

/// What needs attention today.
///
/// The screen the owner opens to find out whether anything is wrong, so the four numbers
/// here are the four things a problem shows up in: orders, money, the escalator queue and
/// the ticket queue. Restyled to match the A2_Dashboard KPI cards and attention banner
/// while preserving the exact underlying data model and keys.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  static const needsAttentionKey = Key('dashboard.needsAttention');
  static const ordersKey = Key('dashboard.orders');
  static const platformKey = Key('dashboard.platform');
  static const updatedKey = Key('dashboard.updated');
  static const moneyKey = Key('dashboard.money');
  static const issuesKey = Key('dashboard.issues');
  static const owedKey = Key('dashboard.owed');
  static Key owedRowKey(String merchantId) => Key('dashboard.owed.$merchantId');
  static Key attentionRowKey(String orderId) => Key('dashboard.attention.$orderId');

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  Timer? _tick;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    // Coming back to a screen whose figures are cached: they were read before, and when.
    if (ref.read(adminTodayProvider).hasValue) _updatedAt = ref.read(clockProvider)();
    // The numbers were read once, so an order that went unanswered while the owner watched
    // this screen never appeared on it. Asked again every minute while it is open.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) ref.invalidate(adminTodayProvider);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(adminTodayProvider);
    // When the figures on screen were read. A number that refreshes itself should say
    // how fresh it is, or a dead connection reads as a quiet day (QA review 2026-09-19).
    ref.listen(adminTodayProvider, (_, next) {
      if (next.hasValue && !next.isLoading && !next.hasError) {
        setState(() => _updatedAt = ref.read(clockProvider)());
      }
    });

    return Scaffold(
      // Named: the lockup said «لقمة» on a screen the grid calls «اليوم».
      appBar: AppBar(title: const Text('اليوم')),
      body: AdminContent(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(adminTodayProvider);
            ref.invalidate(allMerchantsProvider);
            await ref.read(adminTodayProvider.future).catchError((_) => today.value!);
          },
          child: LuqmaAsyncView(
            value: today,
            onRetry: () => ref.invalidate(adminTodayProvider),
            builder: (context, value) => _Body(today: value, updatedAt: _updatedAt),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.today, this.updatedAt});

  final AdminToday today;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    // Every shop that owes commission, most first — the weekly collection round.
    final owing = [
      ...?ref.watch(allMerchantsProvider).asData?.value.where((m) => m.commissionOwed > 0),
    ]..sort((a, b) => b.commissionOwed.compareTo(a.commissionOwed));
    final alertAt = ref.watch(appConfigProvider).commissionAlertPounds * 100;

    final hasAttention = today.needsAttention.isNotEmpty || today.openIssues > 0;

    return ListView(
      // Always scrollable, so pull-to-refresh works on a screen with little on it.
      physics: const AlwaysScrollableScrollPhysics(),
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
                      label: 'قيمة الأوردرات المتسلّمة',
                      value: strings.amount(today.moneyToday),
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
                // What was delivered today, food and delivery — not the platform's cut,
                // which the old label «فلوس النهارده» could be read as.
                _KpiCard(
                  key: DashboardScreen.moneyKey,
                  label: 'قيمة الأوردرات المتسلّمة',
                  value: strings.amount(today.moneyToday),
                  icon: Icons.payments_outlined,
                  isPrice: true,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: Space.sm),
        // The shops' takings above; this is what the platform itself took from them.
        _KpiCard(
          key: DashboardScreen.platformKey,
          label: 'عمولة لقمة النهارده',
          value: strings.amount(today.platformToday),
          icon: Icons.account_balance_wallet_outlined,
          isPrice: true,
        ),
        if (updatedAt != null) ...[
          const SizedBox(height: Space.xs),
          Text(
            'آخر تحديث ${_clock(updatedAt!)} — بيتحدّث لوحده كل دقيقة، واسحب لتحت للتحديث دلوقتي.',
            key: DashboardScreen.updatedKey,
            style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
        ],
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
        const SizedBox(height: Space.xl),
        _SectionHeader(title: 'عليهم عمولة', count: owing.length),
        const SizedBox(height: Space.sm),
        if (owing.isEmpty)
          Text(
            'مفيش محل عليه عمولة دلوقتي.',
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
          )
        else
          Column(
            key: DashboardScreen.owedKey,
            children: [
              for (final shop in owing)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: Material(
                    color: colors.card,
                    borderRadius: Radii.cardAll,
                    child: ListTile(
                      key: DashboardScreen.owedRowKey(shop.id),
                      shape: RoundedRectangleBorder(
                        borderRadius: Radii.cardAll,
                        side: BorderSide(
                          color: shop.commissionOwed >= alertAt && alertAt > 0
                              ? colors.danger
                              : colors.hairline,
                        ),
                      ),
                      title: Text(shop.name),
                      subtitle: shop.commissionOwed >= alertAt && alertAt > 0
                          ? Text(
                              'عدّى حد التنبيه',
                              style: TextStyle(color: colors.danger),
                            )
                          : null,
                      trailing: Text(
                        strings.amount(shop.commissionOwed),
                        style: LuqmaType.priceSmall.copyWith(color: colors.price),
                      ),
                      // Straight to where the cash is recorded.
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MerchantBillingScreen(merchantId: shop.id),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
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
class _QueueRow extends ConsumerWidget {
  const _QueueRow({required this.item});

  final NeedsAttentionItem item;

  /// An order nobody answered: the owner's two moves are to ring the shop, or to cancel it
  /// so the customer is not left waiting. The row used to show both facts and offer neither.
  Future<void> _act(BuildContext context, WidgetRef ref) async {
    // From the item, not from `merchantProvider`: that is an auto-dispose stream, and a
    // `read` with nobody listening returned nothing every time — so the owner's first
    // move on this sheet, ringing the shop, was never offered (D6). An older server sends
    // no phone and the tile is simply absent, as it always was.
    final phone = item.merchantPhone?.trim() ?? '';
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('أوردر #${item.number} — ${item.merchantName}'),
              subtitle: const Text('محدش ردّ عليه في الوقت.'),
            ),
            if (phone.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.call_outlined),
                title: Text('كلّم المحل ($phone)'),
                onTap: () => openExternalLink(
                  context,
                  ref,
                  Uri(scheme: 'tel', path: Phone.normalize(phone)),
                  whenUnavailable: 'الرقم $phone — التليفون ده مش بيعرف يتصل.',
                ),
              ),
            ListTile(
              key: const Key('dashboard.cancelOrder'),
              leading: Icon(Icons.cancel_outlined, color: Theme.of(context).luqma.danger),
              title: const Text('إلغي الأوردر'),
              subtitle: const Text('العميل هيوصله إن الأوردر اتلغى.'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text('إلغاء أوردر #${item.number}'),
                    content: const Text('المحل مردّش على الأوردر. هيتلغي والعميل هيتبلّغ.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('رجوع'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('إلغي'),
                      ),
                    ],
                  ),
                );
                if (sure != true) return;
                // Staff's own cancel, not the customer's: that one matches only `placed`,
                // and every order in this queue is `needsAttention`.
                final result = await ref
                    .read(adminRepositoryProvider)
                    .cancelUnansweredOrder(item.id, reason: 'المحل مردّش على الأوردر');
                ref.invalidate(adminTodayProvider);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(switch (result) {
                      Ok() => 'اتلغى أوردر #${item.number}',
                      // A shop answered between the list and the tap. Trying again cannot
                      // work, so saying «جرّب تاني» would send the owner round in a circle.
                      Err(failure: ConflictFailure()) => 'الأوردر اتحرك قبل ما تلغيه',
                      Err() => 'مقدرناش نلغيه. جرّب تاني.',
                    }),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return InkWell(
      key: DashboardScreen.attentionRowKey(item.id),
      onTap: () => _act(context, ref),
      borderRadius: Radii.cardAll,
      child: Container(
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
      ),
    );
  }
}

/// «9:05» — the hour on a twelve-hour clock, the way the owner reads one.
String _clock(DateTime at) {
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return '$hour:${at.minute.toString().padLeft(2, '0')}';
}
