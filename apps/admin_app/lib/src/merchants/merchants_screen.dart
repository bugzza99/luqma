import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../billing/merchant_billing_screen.dart';
import '../shell/layout.dart';
import 'merchant_cuisines_sheet.dart';
import 'merchants_controller.dart';

/// The screen the owner spends the launch inside.
///
/// It carries two jobs that pull in opposite directions: deciding on merchants waiting
/// for approval, which is occasional and deliberate, and entering menus, which is six
/// hundred items of repetitive typing. The list-and-detail layout is what lets the second
/// happen without bouncing back to a list between every item.
class MerchantsScreen extends ConsumerWidget {
  const MerchantsScreen({super.key});

  static const addKey = Key('merchants.add');
  static const zoneFieldKey = Key('merchants.zoneField');
  static const noZonesKey = Key('merchants.noZones');
  static const createErrorKey = Key('merchants.createError');
  static const emptyKey = Key('merchants.empty');
  static const detailKey = Key('merchants.detail');
  static const identityKey = Key('merchants.identity');
  static const billingKey = Key('merchants.billing');
  static const approveKey = Key('merchants.approve');
  static const suspendKey = Key('merchants.suspend');
  static const deleteKey = Key('merchants.delete');
  static const confirmDeleteKey = Key('merchants.confirmDelete');
  static const nameFieldKey = Key('merchants.name');
  static const phoneFieldKey = Key('merchants.phone');
  static const saveKey = Key('merchants.save');

  static const searchKey = Key('merchants.search');
  static const filterAllKey = Key('merchants.filter.all');
  static const filterActiveKey = Key('merchants.filter.active');
  static const filterPendingKey = Key('merchants.filter.pending');
  static const filterSuspendedKey = Key('merchants.filter.suspended');
  static const delegationBannerKey = Key('merchants.delegationBanner');

  static Key pendingBadgeKey(String id) => Key('merchants.pending.$id');
  static Key rowKey(String id) => Key('merchants.row.$id');
  static const confirmSuspendKey = Key('merchants.confirmSuspend');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchants = ref.watch(allMerchantsProvider);
    final selectedId = ref.watch(selectedMerchantProvider);
    final layout = AdminLayout.of(context);
    final colors = Theme.of(context).luqma;

    final selected = merchants.value?.where((m) => m.id == selectedId).firstOrNull;

    // On a phone the detail replaces the list; there is no room to squeeze both, and a
    // half-width menu editor is worse than no second pane at all.
    if (!layout.showsTwoPanes && selected != null) {
      // The detail is a state of this screen, not a route, so the system back button used
      // to leave «المطاعم» altogether instead of stepping back to the list.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) ref.read(selectedMerchantProvider.notifier).select(null);
        },
        child: _Detail(
          merchant: selected,
          onBack: () => ref.read(selectedMerchantProvider.notifier).select(null),
        ),
      );
    }

    final list = _List(merchants: merchants, selectedId: selectedId);

    return Scaffold(
      appBar: AppBar(title: const Text('المطاعم')),
      body: layout.showsTwoPanes
          ? Row(
              children: [
                Expanded(flex: 2, child: list),
                VerticalDivider(width: 1, color: colors.hairline),
                Expanded(
                  flex: 3,
                  child: selected == null
                      ? const _NothingSelected()
                      : _Detail(merchant: selected),
                ),
              ],
            )
          : AdminContent(child: list),
      floatingActionButton: FloatingActionButton.extended(
        key: MerchantsScreen.addKey,
        onPressed: () => _addMerchant(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('مطعم'),
      ),
    );
  }
}

enum _MerchantFilter { all, active, pending, suspended }

/// The merchants list from A3_Merchants with live query search and status filtering chips.
///
/// Searching matches both store name and phone number (normalized) so the admin on a
/// support call can find a shop by either identity immediately.
class _List extends ConsumerStatefulWidget {
  const _List({required this.merchants, required this.selectedId});

  final AsyncValue<List<Merchant>> merchants;
  final String? selectedId;

  @override
  ConsumerState<_List> createState() => _ListState();
}

class _ListState extends ConsumerState<_List> {
  final _searchController = TextEditingController();
  var _filter = _MerchantFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = LuqmaStrings.of(context);

    return LuqmaAsyncView(
      value: widget.merchants,
      onRetry: () => ref.invalidate(allMerchantsProvider),
      isEmpty: (value) => value.isEmpty,
      empty: LuqmaEmptyView(
        key: MerchantsScreen.emptyKey,
        icon: Icons.storefront_outlined,
        message: 'مفيش مطاعم لسه.\nابدأ بإضافة أول مطعم.',
      ),
      builder: (context, all) {
        final totalCount = all.length;
        final activeCount =
            all.where((m) => m.status == MerchantStatus.approved).length;
        final pendingCount =
            all.where((m) => m.status == MerchantStatus.pending).length;
        final suspendedCount =
            all.where((m) => m.status == MerchantStatus.suspended).length;

        final query = _searchController.text.trim();
        final normalizedQuery = Phone.normalize(query);

        final filtered = all.where((m) {
          // Status filter
          final matchesStatus = switch (_filter) {
            _MerchantFilter.all => true,
            _MerchantFilter.active => m.status == MerchantStatus.approved,
            _MerchantFilter.pending => m.status == MerchantStatus.pending,
            _MerchantFilter.suspended => m.status == MerchantStatus.suspended,
          };
          if (!matchesStatus) return false;

          // Query filter
          if (query.isEmpty) return true;
          final q = query.toLowerCase();
          final matchesName = m.name.toLowerCase().contains(q);
          final matchesPhone = m.phone.toLowerCase().contains(q) ||
              Phone.normalize(m.phone).contains(normalizedQuery);
          return matchesName || matchesPhone;
        }).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.gutter,
                Space.gutter,
                Space.sm,
              ),
              child: TextField(
                key: MerchantsScreen.searchKey,
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: strings.merchantsSearchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: strings.merchantsClearSearchTooltip,
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.gutter,
                vertical: Space.xs,
              ),
              child: Row(
                children: [
                  LuqmaChip(
                    key: MerchantsScreen.filterAllKey,
                    label: '${strings.merchantsFilterAll} ($totalCount)',
                    selected: _filter == _MerchantFilter.all,
                    onTap: () => setState(() => _filter = _MerchantFilter.all),
                  ),
                  const SizedBox(width: Space.sm),
                  LuqmaChip(
                    key: MerchantsScreen.filterActiveKey,
                    label: '${strings.merchantsFilterActive} ($activeCount)',
                    selected: _filter == _MerchantFilter.active,
                    onTap: () => setState(() => _filter = _MerchantFilter.active),
                  ),
                  const SizedBox(width: Space.sm),
                  LuqmaChip(
                    key: MerchantsScreen.filterPendingKey,
                    label: '${strings.merchantsFilterPending} ($pendingCount)',
                    selected: _filter == _MerchantFilter.pending,
                    onTap: () => setState(() => _filter = _MerchantFilter.pending),
                  ),
                  const SizedBox(width: Space.sm),
                  LuqmaChip(
                    key: MerchantsScreen.filterSuspendedKey,
                    label: '${strings.merchantsFilterSuspended} ($suspendedCount)',
                    selected: _filter == _MerchantFilter.suspended,
                    onTap: () => setState(() => _filter = _MerchantFilter.suspended),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.xs),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: LuqmaEmptyView(
                        icon: Icons.search_off_outlined,
                        message: strings.merchantsNoSearchResults,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(Space.gutter),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                      itemBuilder: (context, i) => _Row(
                        merchant: filtered[i],
                        selected: filtered[i].id == widget.selectedId,
                        onTap: () => ref
                            .read(selectedMerchantProvider.notifier)
                            .select(filtered[i].id),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({
    required this.merchant,
    required this.selected,
    required this.onTap,
  });

  final Merchant merchant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    // One request for the whole list, not one per card. Null while it loads or if it
    // fails — the count is a detail under the name, and a card that will not draw
    // because a label is missing is worse than a card with no label.
    final orders = ref.watch(merchantOrderCountsProvider).value?[merchant.id];

    final typeLabel = switch (merchant.type) {
      MerchantType.homeKitchen => 'أكل بيتي',
      MerchantType.restaurant => 'مطعم',
    };

    return InkWell(
      key: MerchantsScreen.rowKey(merchant.id),
      onTap: onTap,
      borderRadius: Radii.cardAll,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        constraints: const BoxConstraints(minHeight: Sizes.minTarget),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(
            color: selected ? colors.brand : colors.hairline,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected ? Elevations.cardPressed : Elevations.card,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: Radii.cardAll,
              child: SizedBox(
                width: 44,
                height: 44,
                child: LuqmaImage(
                  url: merchant.logoUrl,
                  name: merchant.name,
                ),
              ),
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    merchant.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$typeLabel · ${merchant.phone}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (merchant.status == MerchantStatus.pending)
                  _Badge(
                    key: MerchantsScreen.pendingBadgeKey(merchant.id),
                    label: 'مستني موافقة',
                    background: colors.accent,
                    foreground: colors.onAccent,
                  )
                else if (merchant.status == MerchantStatus.suspended)
                  _Badge(
                    label: 'موقوف',
                    background: colors.danger,
                    foreground: colors.onBrand,
                  )
                else
                  _Badge(
                    label: 'نشط',
                    background: colors.success.withValues(alpha: 0.15),
                    foreground: colors.success,
                  ),
                if ((orders ?? 0) > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    strings.merchantsOrderCount(orders!),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
      decoration: BoxDecoration(color: background, borderRadius: Radii.pillAll),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _NothingSelected extends StatelessWidget {
  const _NothingSelected();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: LuqmaEmptyView(
        icon: Icons.storefront_outlined,
        message: 'اختر مطعم من اللستة',
      ),
    );
  }
}

/// The merchant header from A4_MerchantDetail displaying identity, phone, status, and plan.
///
/// Positioned above the menu editor so the admin always knows which shop's catalog is open
/// without cluttering the repetitive dish entry flow below it.
class _MerchantHeader extends StatelessWidget {
  const _MerchantHeader({required this.merchant});

  final Merchant merchant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    final typeLabel = switch (merchant.type) {
      MerchantType.homeKitchen => 'أكل بيتي',
      MerchantType.restaurant => 'مطعم',
    };

    return Container(
      padding: const EdgeInsets.all(Space.gutter),
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: Radii.cardAll,
            child: SizedBox(
              width: 56,
              height: 56,
              child: LuqmaImage(
                url: merchant.logoUrl,
                name: merchant.name,
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  merchant.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.phone,
                      size: Sizes.iconSm,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: Space.xs),
                    Flexible(
                      child: Text(
                        '${merchant.phone} · $typeLabel',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Wrap(
                  spacing: Space.xs,
                  runSpacing: Space.xs,
                  children: [
                    if (merchant.status == MerchantStatus.pending)
                      _Badge(
                        label: 'مستني موافقة',
                        background: colors.accent,
                        foreground: colors.onAccent,
                      )
                    else if (merchant.status == MerchantStatus.suspended)
                      _Badge(
                        label: 'موقوف',
                        background: colors.danger,
                        foreground: colors.onBrand,
                      )
                    else
                      _Badge(
                        label: 'نشط',
                        background: colors.success.withValues(alpha: 0.15),
                        foreground: colors.success,
                      ),
                    if (merchant.planId != null && merchant.planId!.isNotEmpty)
                      _Badge(
                        label: 'خطة ${merchant.planId}',
                        background: colors.surface,
                        foreground: colors.textPrimary,
                      ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Row(
                  children: [
                    ActionChip(
                      key: MerchantCuisinesSheet.openKey,
                      avatar: const Icon(Icons.category_outlined, size: 18),
                      label: const Text('الفئات'),
                      tooltip: 'الفئات',
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) =>
                            MerchantCuisinesSheet(merchant: merchant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The delegation banner from A5_MenuEntry alerting that edits are made on the merchant's behalf.
///
/// Every change made here writes under the admin's session rather than the merchant's,
/// so the banner acts as a visible reminder that changes are committed directly to production.
class _DelegationBanner extends StatelessWidget {
  const _DelegationBanner({required this.merchantName});

  final String merchantName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      key: MerchantsScreen.delegationBannerKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.sm + 2,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.hairline),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: Sizes.iconSm,
            color: colors.price,
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              strings.merchantsMenuDelegationBanner(merchantName),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.price,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.merchant, this.onBack});

  final Merchant merchant;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;
    final orderCount = ref.watch(merchantOrderCountProvider(merchant.id));

    return Scaffold(
      key: MerchantsScreen.detailKey,
      appBar: AppBar(
        title: Text(merchant.name),
        leading: onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_forward),
                tooltip: 'رجوع',
                onPressed: onBack,
              ),
        actions: [
          IconButton(
            key: MerchantsScreen.identityKey,
            tooltip: 'اللوجو والغلاف والوصف',
            icon: Icon(Icons.badge_outlined, color: colors.onBrand),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => MerchantIdentitySheet(merchant: merchant),
            ),
          ),
          IconButton(
            key: MerchantsScreen.billingKey,
            tooltip: 'الحساب والاشتراك',
            icon: Icon(Icons.receipt_long_outlined, color: colors.onBrand),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MerchantBillingScreen(merchantId: merchant.id),
              ),
            ),
          ),
          if (merchant.status != MerchantStatus.approved)
            TextButton(
              key: MerchantsScreen.approveKey,
              onPressed: () => _setStatus(context, ref, MerchantStatus.approved),
              child: Text('اعتماد', style: TextStyle(color: colors.onBrand)),
            )
          else
            TextButton(
              key: MerchantsScreen.suspendKey,
              onPressed: () => _setStatus(context, ref, MerchantStatus.suspended),
              child: Text('إيقاف', style: TextStyle(color: colors.onBrand)),
            ),
          // Delete only while the merchant never traded. Once it has an order the
          // control is disabled and the reason is said in the tooltip — history exists,
          // and history wins. The real count is queried, never a field that can drift.
          IconButton(
            key: MerchantsScreen.deleteKey,
            // Enabled only once the count is known to be zero. Loading and failing both
            // used to read as zero, offering a delete the database would then refuse.
            tooltip: switch (orderCount) {
              AsyncData(value: 0) => 'حذف المطعم',
              AsyncData(:final value) => 'مينفعش حذف — عنده $value طلب',
              AsyncError() => 'مقدرناش نتأكد من الطلبات — مش هينفع الحذف دلوقتي',
              _ => 'لحظة…',
            },
            icon: const Icon(Icons.delete_outline),
            onPressed: orderCount is AsyncData<int> && orderCount.value == 0
                ? () => _confirmDelete(context, ref)
                : null,
          ),
        ],
      ),
      body: AdminContent(
        child: Column(
          children: [
            _MerchantHeader(merchant: merchant),
            _DelegationBanner(merchantName: merchant.name),
            Expanded(child: MenuEditor(merchantId: merchant.id)),
          ],
        ),
      ),
    );
  }

  /// Suspending stops a working shop taking orders, so it is asked first; approving is
  /// what the owner came here to do and is not. Either way the result is said.
  Future<void> _setStatus(
    BuildContext context,
    WidgetRef ref,
    MerchantStatus status,
  ) async {
    if (status == MerchantStatus.suspended) {
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('إيقاف ${merchant.name}'),
          content: const Text(
            'المحل هيختفي من عند العملاء ومش هيستقبل طلبات لحد ما تعتمده تاني.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              key: MerchantsScreen.confirmSuspendKey,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('أوقفه'),
            ),
          ],
        ),
      );
      if (sure != true || !context.mounted) return;
    }
    final result =
        await ref.read(merchantActionsProvider.notifier).setStatus(merchant.id, status);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          Ok() => status == MerchantStatus.approved
              ? 'اتعتمد ${merchant.name}'
              : 'اتوقف ${merchant.name}',
          Err() => 'مقدرناش نغيّر حالة المحل. جرّب تاني.',
        }),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    // Asked, because delete is the one write here with no undo. A merchant that never
    // traded is a typo; deleting the wrong one is an afternoon of re-entering a menu.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف المطعم؟'),
        content: Text('${merchant.name} هيتشال نهائيًا. مفيش رجوع.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            key: MerchantsScreen.confirmDeleteKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('احذف'),
          ),
        ],
      ),
    );

    if (!(confirmed ?? false) || !context.mounted) return;

    final result =
        await ref.read(merchantActionsProvider.notifier).delete(merchant.id);
    if (!context.mounted) return;

    if (result case Err(:final failure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(switch (failure) {
          OfflineFailure() => 'مفيش نت — جرّب تاني.',
          ConflictFailure() => 'المطعم ده ليه طلبات، فمينفعش يتشال.',
          _ => 'مقدرناش نحذف. جرّب تاني.',
        })),
      );
    } else {
      onBack?.call();
    }
  }
}

Future<void> _addMerchant(BuildContext context, WidgetRef ref) async {
  // Awaited rather than read: nothing on this screen watches the zones, so reading them
  // synchronously returns an empty list the first time and creates a merchant with no
  // zone — one that silently cannot receive an order, and whose address flow has nothing
  // to price against.
  final zones = await ref.read(zonesProvider.future);
  if (!context.mounted) return;

  final created = await showDialog<Merchant>(
    context: context,
    // The owner types a name, a number and a zone into this. Dismissing it by tapping
    // beside it throws all three away with no warning, and they are adding fifteen shops
    // in an afternoon.
    barrierDismissible: false,
    builder: (_) => _NewMerchantDialog(zones: zones),
  );

  if (created != null) {
    // Straight into the new merchant: the next thing after adding one is always
    // entering its menu.
    ref.read(selectedMerchantProvider.notifier).select(created.id);
  }
}

class _NewMerchantDialog extends ConsumerStatefulWidget {
  const _NewMerchantDialog({required this.zones});

  final List<Zone> zones;

  @override
  ConsumerState<_NewMerchantDialog> createState() => _NewMerchantDialogState();
}

class _NewMerchantDialogState extends ConsumerState<_NewMerchantDialog> {
  final _formKey = GlobalKey<FormState>();

  /// Minted once, when the dialog opens, and sent again on every retry.
  ///
  /// This is the idempotency, and it has to live here rather than inside the save: an id
  /// made at the moment of sending is a new id each time, and the server can only refuse
  /// a repeat of the *same* one. The lesson C-01 left, where both money paths minted
  /// their key in memory at the point of the request and a lost reply charged twice.
  final _id = luqmaUuid();

  var _name = '';
  var _phone = '';
  late String? _zoneId = widget.zones.firstOrNull?.id;
  var _type = MerchantType.restaurant;

  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await ref.read(merchantActionsProvider.notifier).create(
          id: _id,
          name: _name,
          phone: _phone,
          zoneId: _zoneId!,
          type: _type,
        );
    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final failure):
        // Stays open, with everything still typed in it. It used to pop whatever the
        // answer was, so a shop that was never created looked exactly like one that was —
        // and the name, the number and the zone went with it.
        setState(() {
          _saving = false;
          _error = switch (failure) {
            OfflineFailure() => 'مفيش نت. المحل لسه مااتضافش — جرّب تاني.',
            PermissionFailure() => 'مش من حقك تضيف محل.',
            ConflictFailure() => 'فيه محل بنفس البيانات دي.',
            ValidationFailure() => 'فيه بيانات السيرفر مارضيش عليها. راجع الاسم والرقم.',
            _ => 'مقدرناش نضيف المحل. جرّب تاني.',
          };
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    // A shop with no zone cannot be delivered to and has nothing to price a delivery
    // against, so there is no useful thing to create. The form said so only by hiding the
    // picker and then saving an empty string, which the database refuses — as an error
    // nobody could act on.
    final noZones = widget.zones.isEmpty;

    return AlertDialog(
      title: const Text('مطعم جديد'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (noZones)
                Padding(
                  key: MerchantsScreen.noZonesKey,
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: Text(
                    'مفيش مناطق في المدينة دي. ضيف منطقة من «الأماكن» الأول — المحل من '
                    'غير منطقة مش هيعرف يستقبل أوردر.',
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: colors.danger),
                  ),
                ),
              TextFormField(
                key: MerchantsScreen.nameFieldKey,
                autofocus: true,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'الاسم'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'اكتب اسم المطعم' : null,
                onSaved: (v) => _name = v!.trim(),
              ),
              const SizedBox(height: Space.md),
              TextFormField(
                key: MerchantsScreen.phoneFieldKey,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'التليفون'),
                keyboardType: TextInputType.phone,
                onSaved: (v) => _phone = v?.trim() ?? '',
              ),
              const SizedBox(height: Space.md),
              DropdownButtonFormField<MerchantType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'النوع'),
                items: const [
                  DropdownMenuItem(
                    value: MerchantType.restaurant,
                    child: Text('مطعم'),
                  ),
                  DropdownMenuItem(
                    value: MerchantType.homeKitchen,
                    child: Text('أكل بيتي'),
                  ),
                ],
                onChanged:
                    _saving ? null : (v) => setState(() => _type = v ?? _type),
              ),
              if (!noZones) ...[
                const SizedBox(height: Space.md),
                DropdownButtonFormField<String>(
                  key: MerchantsScreen.zoneFieldKey,
                  initialValue: _zoneId,
                  decoration: const InputDecoration(labelText: 'المنطقة'),
                  // Required, and said so rather than assumed. The picker starts on the
                  // first zone, but a form that cannot express «none chosen» is a form
                  // nobody can correct.
                  validator: (v) => v == null ? 'اختار المنطقة' : null,
                  items: [
                    for (final zone in widget.zones)
                      DropdownMenuItem(value: zone.id, child: Text(zone.name)),
                  ],
                  onChanged: _saving ? null : (v) => setState(() => _zoneId = v),
                ),
              ],
              if (_error case final message?) ...[
                const SizedBox(height: Space.md),
                Text(
                  message,
                  key: MerchantsScreen.createErrorKey,
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: colors.danger),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: MerchantsScreen.saveKey,
          // Single-flight, and no zones is a precondition rather than a message: a second
          // tap while the first is in flight is a second shop on a slow connection, which
          // is the connection this is used on.
          onPressed: _saving || noZones ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: Sizes.iconSm,
                  height: Sizes.iconSm,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('احفظ'),
        ),
      ],
    );
  }
}

/// The shop's own face: its mark, its cover, and the line under its name.
///
/// Here as well as in MerchantApp because the owner onboards every shop personally —
/// they type the menus and shoot the photographs — so the person who will actually fill
/// these in for the first fifteen merchants is sitting in AdminApp, not on the
/// merchant's phone.
///
/// A sheet rather than fields on the detail panel: that screen is the menu editor, which
/// is what it is open for, and three controls set once each should not take space from
/// six hundred menu items entered over a fortnight.
class MerchantIdentitySheet extends ConsumerStatefulWidget {
  const MerchantIdentitySheet({super.key, required this.merchant});

  final Merchant merchant;

  static const logoKey = Key('merchant.identity.logo');
  static const coverKey = Key('merchant.identity.cover');
  static const descriptionKey = Key('merchant.identity.description');
  static const saveKey = Key('merchant.identity.save');

  @override
  ConsumerState<MerchantIdentitySheet> createState() =>
      _MerchantIdentitySheetState();
}

class _MerchantIdentitySheetState extends ConsumerState<MerchantIdentitySheet> {
  late final _description =
      TextEditingController(text: widget.merchant.description ?? '');

  late String? _logoId = widget.merchant.logoMediaId;
  late String? _coverId = widget.merchant.coverMediaId;
  String? _logoUrl;
  String? _coverUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPictures());
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  /// The row carries ids; the picker needs addresses.
  ///
  /// Nothing is read when there is nothing to read: a shop added a minute ago has neither
  /// picture, and resolving two ids that do not exist is two requests for nothing.
  Future<void> _loadPictures() async {
    final wanted = [
      for (final (id, isLogo) in [(_coverId, false), (_logoId, true)])
        if (id != null && id.isNotEmpty) (id, isLogo),
    ];
    if (wanted.isEmpty) return;

    final media = ref.read(mediaRepositoryProvider);
    for (final (id, isLogo) in wanted) {
      final result = await media.get(id);
      if (!mounted) return;
      setState(() {
        if (isLogo) {
          _logoUrl = result.valueOrNull?.url;
        } else {
          _coverUrl = result.valueOrNull?.url;
        }
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final typed = _description.text.trim();

    // One write for all three. Three separate saves is three chances for the second to
    // fail after the first landed, leaving a shop with a new logo and the old description
    // and nothing on screen saying which half went through.
    // Only these three. A full save from the copy this sheet opened with would put back
    // whatever the shop looked like then — a status or plan somebody changed since.
    final result = await ref.read(merchantRepositoryProvider).setIdentity(
          widget.merchant.id,
          logoMediaId: _logoId,
          coverMediaId: _coverId,
          description: typed.isEmpty ? null : typed,
        );
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          Ok() => 'اتحفظ.',
          Err(:final failure) => switch (failure) {
              OfflineFailure() => 'مفيش نت — جرّب تاني.',
              PermissionFailure() => 'مش مسموحلك تعدّل المطعم ده.',
              _ => 'مقدرناش نحفظ. جرّب تاني.',
            },
        }),
      ),
    );
    if (result is Ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.merchant.name, style: theme.textTheme.titleLarge),
                Text(
                  // An admin's upload arrives approved — `admin_media` is `for all` and
                  // policies are OR'd — so unlike the merchant's own upload there is no
                  // wait, and saying so stops somebody re-uploading to "fix" it.
                  'صورك بتظهر على طول من غير مراجعة.',
                  style: LuqmaType.caption.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: Space.lg),
                Text('لوجو المطعم', style: theme.textTheme.titleSmall),
                const SizedBox(height: Space.sm),
                MediaPicker(
                  key: MerchantIdentitySheet.logoKey,
                  kind: MediaKind.merchantLogo,
                  url: _logoUrl,
                  name: widget.merchant.name,
                  ownerId: widget.merchant.id,
                  onUploaded: (media) => setState(() {
                    _logoId = media.id;
                    _logoUrl = media.url;
                  }),
                ),
                const SizedBox(height: Space.lg),
                Text('صورة الغلاف', style: theme.textTheme.titleSmall),
                const SizedBox(height: Space.sm),
                MediaPicker(
                  key: MerchantIdentitySheet.coverKey,
                  kind: MediaKind.merchantCover,
                  url: _coverUrl,
                  name: widget.merchant.name,
                  ownerId: widget.merchant.id,
                  onUploaded: (media) => setState(() {
                    _coverId = media.id;
                    _coverUrl = media.url;
                  }),
                ),
                const SizedBox(height: Space.lg),
                TextField(
                  key: MerchantIdentitySheet.descriptionKey,
                  controller: _description,
                  maxLength: 120,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'وصف قصير',
                    hintText: 'مشويات وحلويات شرقية',
                    helperText: 'بيظهر تحت اسم المطعم في الصفحة الرئيسية.',
                  ),
                ),
                const SizedBox(height: Space.md),
                FilledButton(
                  key: MerchantIdentitySheet.saveKey,
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(Sizes.minTarget),
                  ),
                  child: Text(_saving ? 'بنحفظ…' : 'احفظ'),
                ),
                const SizedBox(height: Space.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
