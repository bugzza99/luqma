import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';

/// Customer detail screen showing account facts, verification before password reset,
/// recent orders, block/unblock, and direct phone call.
class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.customer,
    this.onBack,
    this.onCustomerUpdated,
  });

  final CustomerSummary customer;
  final VoidCallback? onBack;
  final VoidCallback? onCustomerUpdated;

  static const detailKey = Key('customer_detail');
  static const generatePasswordKey = Key('customer_detail.generate_password');
  static const blockKey = Key('customer_detail.block');
  static const callKey = Key('customer_detail.call');
  static const backKey = Key('customer_detail.back');
  static const resetBlockKey = Key('customer_detail.reset_block');
  static const verificationFactsKey = Key('customer_detail.verification_facts');
  static const showAllOrdersKey = Key('customer_detail.show_all_orders');
  static const noVerificationFactsKey = Key('customer_detail.no_verification_facts');

  @override
  ConsumerState<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  List<Order>? _orders;
  List<Address>? _addresses;
  Failure? _failure;
  bool _loading = true;
  bool _generating = false;
  late CustomerSummary _customer;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _load();
  }

  @override
  void didUpdateWidget(covariant CustomerDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.customer.id != widget.customer.id) {
      _customer = widget.customer;
      _load();
    } else if (oldWidget.customer != widget.customer) {
      _customer = widget.customer;
    }
  }

  /// Which load is the current one.
  ///
  /// On a wide screen this widget stays mounted while the admin selects one customer after
  /// another, so a load that started for Ahmed can finish after Salma is selected — and it
  /// used to write Ahmed's last order and address into the reset block under Salma's name,
  /// with the generate button live and aimed at Salma. The admin asks the caller about one
  /// account and hands a password to another. Found by the review pass.
  ///
  /// Two defences, both needed. The customer is captured before the first `await`, so the
  /// second read cannot pick up a different customer halfway through. And every completion
  /// checks it is still the newest load before it touches state.
  int _loadGeneration = 0;

  bool _showAllOrders = false;

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final uid = _customer.id;
    setState(() {
      _loading = true;
      _failure = null;
      _orders = null;
      _addresses = null;
    });

    final historyResult = await ref.read(customerRepositoryProvider).history(uid);
    if (!mounted || generation != _loadGeneration) return;
    final addressesResult = await ref.read(addressRepositoryProvider).addresses(uid);

    if (!mounted || generation != _loadGeneration) return;

    if (historyResult is Err) {
      setState(() {
        _failure = (historyResult as Err).failure;
        _loading = false;
      });
      return;
    }

    if (addressesResult is Err) {
      setState(() {
        _failure = (addressesResult as Err).failure;
        _loading = false;
      });
      return;
    }

    setState(() {
      _orders = (historyResult as Ok<List<Order>>).value;
      _addresses = (addressesResult as Ok<List<Address>>).value;
      _loading = false;
    });
  }

  Future<void> _toggleBlock() async {
    final newBlocked = !_customer.isBlocked;
    final result = await ref.read(customerRepositoryProvider).setBlocked(
          _customer.id,
          blocked: newBlocked,
        );
    if (!mounted) return;

    if (result is Ok) {
      setState(() {
        _customer = CustomerSummary(
          id: _customer.id,
          name: _customer.name,
          phone: _customer.phone,
          isBlocked: newBlocked,
          rejectedOrdersCount: _customer.rejectedOrdersCount,
          createdAt: _customer.createdAt,
        );
      });
      widget.onCustomerUpdated?.call();
    }
  }

  Future<void> _resetPassword() async {
    setState(() => _generating = true);
    final result = await ref.read(customerRepositoryProvider).resetPassword(_customer.id);
    if (!mounted) return;
    setState(() => _generating = false);

    final strings = LuqmaStrings.of(context);
    final isOk = result is Ok;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isOk ? strings.customerResetDialogTitle : strings.customerResetFailedTitle),
        content: switch (result) {
          // Selectable, and in one big line: this is read down a phone line, and it is
          // the only time anybody can see it.
          Ok(:final value) => SelectableText(
              value,
              textDirection: TextDirection.ltr,
              style: Theme.of(dialogContext).textTheme.headlineSmall,
            ),
          Err(failure: ConflictFailure()) =>
            Text(strings.customerResetStaffConflict),
          Err() => Text(strings.customerResetGenericError),
        },
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(strings.customerResetDone),
          ),
        ],
      ),
    );
  }

  Future<void> _callCustomer() async {
    final phone = _customer.phone.trim();
    if (phone.isEmpty) return;
    final strings = LuqmaStrings.of(context);
    await openExternalLink(
      context,
      ref,
      Uri.parse('tel:$phone'),
      whenUnavailable: strings.customerCallUnavailable,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final zones = ref.watch(zonesProvider).value ?? const <Zone>[];
    final now = ref.watch(clockProvider)();

    final title = _customer.name.isEmpty ? 'عميل' : _customer.name;

    return Scaffold(
      key: CustomerDetailScreen.detailKey,
      appBar: AppBar(
        title: Text(title),
        leading: widget.onBack != null
            ? IconButton(
                key: CustomerDetailScreen.backKey,
                icon: const Icon(Icons.arrow_forward),
                tooltip: strings.customerBackTooltip,
                onPressed: widget.onBack,
              )
            : null,
      ),
      body: AdminContent(
        child: _buildBody(theme, colors, strings, zones, now),
      ),
      bottomNavigationBar: _buildBottomBar(theme, colors, strings),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    LuqmaColors colors,
    LuqmaStrings strings,
    List<Zone> zones,
    DateTime now,
  ) {
    if (_failure != null) {
      return LuqmaErrorView(
        failure: _failure!,
        onRetry: _load,
      );
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final orders = _orders ?? const <Order>[];
    final addresses = _addresses ?? const <Address>[];

    // Compute total spend from delivered orders
    final totalSpent = orders
        .where((o) => o.status == OrderStatus.delivered)
        .fold<int>(0, (sum, o) => sum + o.pricing.total);

    final lastOrder = orders.firstOrNull;
    final savedAddress = addresses.firstOrNull;
    final hasNoFacts = lastOrder == null && savedAddress == null;

    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        // ─── Header Card ───────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: Radii.cardAll,
            border: Border.all(color: colors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: colors.brand,
                    foregroundColor: colors.onBrand,
                    child: Text(
                      _customer.name.isNotEmpty ? _customer.name[0] : 'ع',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _customer.name.isEmpty ? 'عميل' : _customer.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: Space.xs / 2),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            _customer.phone.isEmpty ? 'من غير رقم' : _customer.phone,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.xs / 2),
                        Text(
                          _customer.createdAt != null
                              ? strings.customerDetailMemberSince(
                                  luqmaMonthName(_customer.createdAt!.month),
                                  _customer.createdAt!.year.toString(),
                                )
                              : strings.customerDetailMemberNew,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.price,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: orders.length >= 50
                          ? '${strings.customerStatOrders} (آخر 50)'
                          : strings.customerStatOrders,
                      value: '${orders.length}',
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: _MiniStat(
                      // The history is the newest fifty orders, so a customer with more has
                      // totals over that window, not over their account. Said on the label
                      // rather than implied by a number that silently stops growing.
                      label: orders.length >= 50
                          ? '${strings.customerStatTotal} (آخر 50)'
                          : strings.customerStatTotal,
                      value: strings.price(totalSpent),
                    ),
                  ),
                  const SizedBox(width: Space.xs),
                  Expanded(
                    child: _MiniStat(
                      label: strings.customerStatRejects,
                      value: '${_customer.rejectedOrdersCount}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: Space.md),

        // ─── Reset Password Block ─────────────────────────────
        Container(
          key: CustomerDetailScreen.resetBlockKey,
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: Radii.cardAll,
            border: Border.all(color: colors.border),
            boxShadow: Elevations.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.customerResetBlockTitle,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                strings.customerResetBlockPrompt,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textPrimary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: Space.sm),
              if (hasNoFacts) ...[
                Container(
                  key: CustomerDetailScreen.noVerificationFactsKey,
                  width: double.infinity,
                  padding: const EdgeInsets.all(Space.sm),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: Radii.cardAll,
                  ),
                  child: Text(
                    strings.customerResetNoHistoryOrAddress,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ] else ...[
                Column(
                  key: CustomerDetailScreen.verificationFactsKey,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${strings.customerResetLastOrderLabel} ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: lastOrder != null
                                ? '#${lastOrder.orderNumber} · ${lastOrder.placedAt != null ? luqmaOrderDay(lastOrder.placedAt!, now, strings) : ""} · ${strings.price(lastOrder.pricing.total)}'
                                : strings.customerResetNoOrders,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${strings.customerResetAddressLabel} ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          TextSpan(
                            text: savedAddress != null
                                ? savedAddress.format(
                                    zoneName: zones
                                            .where((z) => z.id == savedAddress.zoneId)
                                            .firstOrNull
                                            ?.name ??
                                        '',
                                  )
                                : strings.customerResetNoAddresses,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: Space.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: CustomerDetailScreen.generatePasswordKey,
                  onPressed: _generating ? null : _resetPassword,
                  child: _generating
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(strings.customerResetGenerateButton),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: Space.lg),

        // ─── Recent Orders ────────────────────────────────────
        Text(
          strings.customerRecentOrdersTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: Space.sm),
        if (orders.isEmpty)
          Container(
            padding: const EdgeInsets.all(Space.lg),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: Radii.cardAll,
              border: Border.all(color: colors.hairline),
            ),
            child: Text(
              strings.customerRecentOrdersEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          )
        else
          // Every order fetched, not the first five. The restyle cut the list at five with no
          // way to see the rest, and the older orders are exactly what a support call about
          // a disputed delivery from last month needs.
          for (final order in (_showAllOrders ? orders : orders.take(5))) ...[
            Container(
              margin: const EdgeInsets.only(bottom: Space.xs),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
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
                          '#${order.orderNumber}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: Space.xs / 2),
                        Text(
                          '${order.merchantName.isNotEmpty ? "${order.merchantName} · " : ""}${order.placedAt != null ? luqmaOrderDay(order.placedAt!, now, strings) : ""}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        strings.price(order.pricing.total),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.price,
                        ),
                      ),
                      const SizedBox(height: Space.xs / 2),
                      Text(
                        // Words, not the enum's name: «delivered» is a Dart identifier, and
                        // the admin reading it is on a telephone call in Arabic. From the
                        // admin's side — «needsAttention» is the one they act on, so it is
                        // named for what it is rather than softened as the customer sees it.
                        switch (order.status) {
                          OrderStatus.placed => 'مستني رد المطعم',
                          OrderStatus.accepted => 'المطعم قبل',
                          OrderStatus.preparing => 'بيتجهّز',
                          OrderStatus.outForDelivery => 'مع المندوب',
                          OrderStatus.delivered => 'اتسلّم',
                          OrderStatus.cancelled => 'اتلغى',
                          OrderStatus.needsAttention => 'محتاج تدخّل',
                        },
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        // The list shows five until asked; the history fetched is up to fifty.
        if (orders.length > 5)
          TextButton(
            key: CustomerDetailScreen.showAllOrdersKey,
            onPressed: () => setState(() => _showAllOrders = !_showAllOrders),
            child: Text(_showAllOrders ? 'عرض أقل' : 'عرض الكل (${orders.length})'),
          ),
      ],
    );
  }

  Widget _buildBottomBar(
    ThemeData theme,
    LuqmaColors colors,
    LuqmaStrings strings,
  ) {
    return Container(
      padding: const EdgeInsets.all(Space.gutter),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: CustomerDetailScreen.blockKey,
                onPressed: _toggleBlock,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _customer.isBlocked ? colors.brand : colors.danger,
                  side: BorderSide(
                    color: _customer.isBlocked ? colors.brand : colors.danger,
                  ),
                  minimumSize: const Size.fromHeight(Sizes.minTarget),
                ),
                child: Text(
                  _customer.isBlocked ? strings.customerUnblockAction : strings.customerBlockAction,
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: FilledButton.icon(
                key: CustomerDetailScreen.callKey,
                onPressed: _customer.phone.trim().isEmpty ? null : _callCustomer,
                icon: const Icon(Icons.phone, size: 18),
                label: Text(strings.customerCallAction),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(Sizes.minTarget),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.sm, horizontal: Space.xs),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: Radii.cardAll,
      ),
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: Space.xs / 2),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
