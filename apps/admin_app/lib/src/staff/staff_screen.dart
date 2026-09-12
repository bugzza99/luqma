import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../merchants/merchants_controller.dart';
import '../shell/layout.dart';
import 'staff_controller.dart';

/// Watches all active attachments (shops plus platform) for a single courier.
final courierAttachmentsProvider =
    StreamProvider.autoDispose.family<List<CourierRosterItem>, String>(
  (ref, courierUid) => ref
      .watch(courierRosterRepositoryProvider)
      .watchCourierAttachments(courierUid),
);

/// The platform's own accounts: admins, moderators, and the shops' owners and couriers.
///
/// Restyled to A17 Staff:
/// - Categorized filter chips with live counts by role.
/// - Staff rows carrying role-coloured avatars, status labels, and toggle controls.
/// - For couriers, tapping their row opens their multi-shop attachments detail:
///   listing each shop by name and «المنصة» for platform scope, adding shops via
///   the existing [_MerchantPicker], adding platform scope when not yet held, and
///   detaching with mandatory confirmation.
/// - Responsive layout: on wide screens / browsers, list and detail render side by
///   side without breaking; on phones, detail replaces the list with a back button.
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  static const emptyKey = Key('staff.empty');
  static const toggleKey = Key('staff.toggle');
  static const createKey = Key('staff.create');
  static const submitKey = Key('staff.submit');

  static const _roleLabels = {
    'admin': 'أدمن',
    'moderator': 'مشرف',
    'owner': 'صاحب محل',
    'courier': 'كابتن',
  };

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  String? _selectedRole;
  StaffMember? _selectedCourier;

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffListProvider);
    final merchantsAsync = ref.watch(allMerchantsProvider);
    final layout = AdminLayout.of(context);
    final colors = Theme.of(context).luqma;

    final merchantsMap = {
      for (final m in merchantsAsync.value ?? const <Merchant>[])
        m.id: m,
    };

    // Keep selected courier reference fresh with latest state if the list re-emits.
    final currentCourier = staffAsync.value
        ?.where((m) => m.uid == _selectedCourier?.uid)
        .firstOrNull;
    if (currentCourier != null) {
      _selectedCourier = currentCourier;
    }

    // On narrow screens (phone), the courier detail replaces the staff list so that
    // controls have sufficient touch target size and never overflow.
    if (!layout.showsTwoPanes && _selectedCourier != null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_forward),
            tooltip: 'رجوع',
            onPressed: () => setState(() => _selectedCourier = null),
          ),
          title: Text(
            _selectedCourier!.name?.isNotEmpty == true
                ? _selectedCourier!.name!
                : 'ارتباطات الكابتن',
          ),
        ),
        body: AdminContent(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.gutter),
            child: _CourierDetailView(
              courier: _selectedCourier!,
              merchantsMap: merchantsMap,
            ),
          ),
        ),
      );
    }

    final listContent = LuqmaAsyncView<List<StaffMember>>(
      value: staffAsync,
      onRetry: () => ref.invalidate(staffListProvider),
      empty: Center(
        key: StaffScreen.emptyKey,
        child: Text(
          'مفيش حسابات لسه.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
        ),
      ),
      isEmpty: (value) => value.isEmpty,
      builder: (context, members) {
        final filtered = _selectedRole == null
            ? members
            : members.where((m) => m.role == _selectedRole).toList();

        return Column(
          children: [
            _buildRoleFilterBar(context, members),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(Space.xl),
                        child: Text(
                          'مفيش حسابات مطابقة للفلتر.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: colors.textSecondary,
                              ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(Space.gutter),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                      itemBuilder: (context, i) {
                        final member = filtered[i];
                        final isSelected = member.uid == _selectedCourier?.uid;
                        final merchantName = member.merchantId != null
                            ? merchantsMap[member.merchantId]?.name
                            : null;

                        return _StaffRow(
                          member: member,
                          merchantName: merchantName,
                          isSelected: isSelected,
                          onTap: member.role == 'courier'
                              ? () => setState(() => _selectedCourier = member)
                              : null,
                          onToggle: () => _toggle(context, ref, member),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('فريق العمل'),
        actions: [
          IconButton(
            key: StaffScreen.createKey,
            tooltip: 'إضافة حساب',
            icon: const Icon(Icons.person_add_alt),
            onPressed: () => _showCreateDialog(context),
          ),
        ],
      ),
      body: layout.showsTwoPanes
          ? AdminContent(
              child: Row(
                children: [
                  Expanded(flex: 2, child: listContent),
                  VerticalDivider(width: 1, color: colors.hairline),
                  Expanded(
                    flex: 3,
                    child: _selectedCourier == null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.two_wheeler_outlined,
                                  size: 48,
                                  color: colors.textSecondary,
                                ),
                                const SizedBox(height: Space.md),
                                Text(
                                  'اختر كابتن لعرض ارتباطاته',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(Space.gutter),
                            child: _CourierDetailView(
                              courier: _selectedCourier!,
                              merchantsMap: merchantsMap,
                              onClose: () =>
                                  setState(() => _selectedCourier = null),
                            ),
                          ),
                  ),
                ],
              ),
            )
          : AdminContent(child: listContent),
    );
  }

  Widget _buildRoleFilterBar(BuildContext context, List<StaffMember> members) {
    final colors = Theme.of(context).luqma;

    final filters = [
      (label: 'الكل', role: null),
      (label: 'أدمن', role: 'admin'),
      (label: 'مشرفين', role: 'moderator'),
      (label: 'كباتن', role: 'courier'),
      (label: 'أصحاب محال', role: 'owner'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.sm,
      ),
      color: colors.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final filter in filters) ...[
              _RoleFilterChip(
                label: filter.label,
                isSelected: _selectedRole == filter.role,
                onTap: () => setState(() => _selectedRole = filter.role),
              ),
              const SizedBox(width: Space.xs),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    StaffMember member,
  ) async {
    await ref
        .read(staffRepositoryProvider)
        .setActive(member.uid, active: !member.isActive);
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final created = await showDialog<Result<StaffMember>>(
      context: context,
      builder: (_) => const _CreateStaffDialog(),
    );
    if (!mounted || created == null) return;

    if (created is Ok<StaffMember>) {
      ref.invalidate(staffListProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text('اتعمل الحساب لـ ${created.value.name ?? created.value.uid}'),
        ),
      );
    } else if (created case Err(:final failure)) {
      messenger.showSnackBar(
        SnackBar(
          key: const Key('staff.create-error'),
          content: Text(switch (failure) {
            EmailTakenFailure() => 'الإيميل ده متسجل قبل كده.',
            PermissionFailure() => 'مش مسموحلك تعمل حسابات.',
            ConflictFailure() => 'فيه معلومة ناقصة أو غلط.',
            OfflineFailure() => 'مفيش نت — جرّب تاني.',
            _ => 'معرفنش عمل الحساب. جرّب تاني.',
          }),
        ),
      );
    }
  }
}

class _RoleFilterChip extends StatelessWidget {
  const _RoleFilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return InkWell(
      onTap: onTap,
      borderRadius: Radii.pillAll,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected ? colors.brand : colors.card,
          borderRadius: Radii.pillAll,
          border: Border.all(
            color: isSelected ? colors.brand : colors.hairline,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: isSelected ? colors.onBrand : colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({
    required this.member,
    this.merchantName,
    this.isSelected = false,
    this.onTap,
    required this.onToggle,
  });

  final StaffMember member;
  final String? merchantName;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback onToggle;

  Color _roleColor(LuqmaColors colors, String role) => switch (role) {
        'admin' => colors.brand,
        'moderator' => colors.accent,
        'courier' => colors.price,
        'owner' => colors.success,
        _ => colors.textSecondary,
      };

  String _formatScope(StaffMember member, String? merchantName) {
    if (member.scope == 'platform') return 'المنصة';
    if (merchantName != null && merchantName.isNotEmpty) {
      return 'مطعم: $merchantName';
    }
    return 'مطعم';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final isCourier = member.role == 'courier';
    final roleColor = _roleColor(colors, member.role);
    final roleLabel = StaffScreen._roleLabels[member.role] ?? member.role;

    final initial = member.name?.trim().isNotEmpty == true
        ? member.name!.trim().characters.first
        : 'ح';

    return InkWell(
      onTap: isCourier ? onTap : null,
      borderRadius: Radii.cardAll,
      child: AnimatedOpacity(
        opacity: member.isActive ? 1.0 : 0.55,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.md,
            vertical: Space.sm,
          ),
          constraints: const BoxConstraints(minHeight: Sizes.minTarget),
          decoration: BoxDecoration(
            color: isSelected ? colors.surface : colors.card,
            borderRadius: Radii.cardAll,
            border: Border.all(
              color: isSelected ? colors.brand : colors.hairline,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: roleColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  initial,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.onBrand,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name?.isNotEmpty == true ? member.name! : 'حساب',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Space.xs / 2),
                    Text(
                      _formatScope(member, merchantName),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.sm,
                      vertical: Space.xs / 2,
                    ),
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.12),
                      borderRadius: Radii.pillAll,
                    ),
                    child: Text(
                      roleLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: roleColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!member.isActive) ...[
                    const SizedBox(height: Space.xs / 2),
                    Text(
                      'موقوف',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: Space.xs),
              IconButton(
                key: StaffScreen.toggleKey,
                tooltip: member.isActive ? 'تعطيل' : 'تفعيل',
                icon: Icon(
                  member.isActive
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  color: member.isActive ? colors.danger : colors.brand,
                ),
                onPressed: onToggle,
              ),
              if (isCourier)
                Icon(
                  Icons.chevron_left,
                  color: colors.textSecondary,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The detail pane/sheet for managing which shops (and/or platform) a courier carries for.
class _CourierDetailView extends ConsumerWidget {
  const _CourierDetailView({
    required this.courier,
    required this.merchantsMap,
    this.onClose,
  });

  final StaffMember courier;
  final Map<String, Merchant> merchantsMap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final attachmentsAsync = ref.watch(courierAttachmentsProvider(courier.uid));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header card
        Container(
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: Radii.cardAll,
            border: Border.all(color: colors.hairline),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.price,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.delivery_dining,
                  color: colors.onBrand,
                  size: 24,
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      courier.name?.isNotEmpty == true ? courier.name! : 'كابتن',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (courier.phone != null && courier.phone!.isNotEmpty) ...[
                      const SizedBox(height: Space.xs / 2),
                      Text(
                        'هاتف: ${courier.phone}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: 'إغلاق',
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.lg),

        // Live active attachments and actions
        LuqmaAsyncView<List<CourierRosterItem>>(
          value: attachmentsAsync,
          onRetry: () => ref.invalidate(courierAttachmentsProvider(courier.uid)),
          empty: _buildEmptyOrActive(context, ref, const []),
          isEmpty: (items) => items.isEmpty,
          builder: (context, items) => _buildEmptyOrActive(context, ref, items),
        ),
      ],
    );
  }

  Widget _buildEmptyOrActive(
    BuildContext context,
    WidgetRef ref,
    List<CourierRosterItem> items,
  ) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final l10n = LuqmaStrings.of(context);

    // Platform row is represented by merchantId == null
    final hasPlatform = items.any((item) => item.merchantId == null && item.isActive);
    final attachedMerchantIds = {
      for (final item in items)
        if (item.merchantId != null && item.isActive) item.merchantId!,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Action buttons
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _openAddShop(context, ref, attachedMerchantIds),
              icon: const Icon(Icons.add_business_outlined),
              label: Text(l10n.courierAddShop),
            ),
            // Only offered when the courier does not already hold the platform row.
            if (!hasPlatform)
              FilledButton.icon(
                onPressed: () => _attachToPlatform(context, ref),
                icon: const Icon(Icons.add_moderator_outlined),
                label: Text(l10n.courierAddToPlatform),
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        Text(
          l10n.courierActiveAttachments,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Space.sm),
        if (items.isEmpty)
          Container(
            padding: const EdgeInsets.all(Space.xl),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: Radii.cardAll,
              border: Border.all(color: colors.hairline),
            ),
            alignment: Alignment.center,
            child: Text(
              l10n.courierNoAttachments,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
            itemBuilder: (context, i) {
              final item = items[i];
              final isPlatform = item.merchantId == null;
              final displayName = isPlatform
                  ? l10n.courierPlatformRow
                  : (item.merchantName ??
                      merchantsMap[item.merchantId]?.name ??
                      item.merchantId ??
                      'محل');

              return Container(
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
                    Icon(
                      isPlatform
                          ? Icons.admin_panel_settings_outlined
                          : Icons.storefront_outlined,
                      color: isPlatform ? colors.brand : colors.price,
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            isPlatform ? 'حساب على مستوى المنصة' : 'محل تجاري',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Detach button — always confirmed first to avoid accidental mis-taps
                    // which immediately revoke order visibility in the street.
                    IconButton(
                      tooltip: l10n.courierDetachTooltip,
                      icon: Icon(Icons.link_off, color: colors.danger),
                      onPressed: () => _confirmAndDetach(context, ref, item),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _attachToPlatform(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(courierRosterRepositoryProvider)
        .attachCourierToMerchant(courierUid: courier.uid, merchantId: null);

    if (result is Err && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر ربط الكابتن بالمنصة. حاول مرة أخرى.')),
      );
    }
  }

  Future<void> _openAddShop(
    BuildContext context,
    WidgetRef ref,
    Set<String> attachedMerchantIds,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AddShopDialog(
        courierUid: courier.uid,
        excludedIds: attachedMerchantIds,
      ),
    );
  }

  Future<void> _confirmAndDetach(
    BuildContext context,
    WidgetRef ref,
    CourierRosterItem item,
  ) async {
    final l10n = LuqmaStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).luqma;
        return AlertDialog(
          title: Text(l10n.courierDetachConfirmTitle),
          content: Text(l10n.courierDetachConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colors.danger),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.courierDetachConfirmAction),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(courierRosterRepositoryProvider)
        .detachCourierFromMerchant(
          courierUid: courier.uid,
          merchantId: item.merchantId,
        );

    if (result is Err && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر إلغاء الربط. حاول مرة أخرى.')),
      );
    }
  }
}

/// Dialog allowing an admin to pick a shop name and attach it to a courier.
/// Reuses [_MerchantPicker] to uphold the "Never ask anybody to type a uuid" rule.
class _AddShopDialog extends ConsumerStatefulWidget {
  const _AddShopDialog({
    required this.courierUid,
    this.excludedIds = const {},
  });

  final String courierUid;
  final Set<String> excludedIds;

  @override
  ConsumerState<_AddShopDialog> createState() => _AddShopDialogState();
}

class _AddShopDialogState extends ConsumerState<_AddShopDialog> {
  String? _merchantId;
  final _form = GlobalKey<FormState>();

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(courierRosterRepositoryProvider)
        .attachCourierToMerchant(
          courierUid: widget.courierUid,
          merchantId: _merchantId,
        );
    if (!mounted) return;
    if (result is Ok) {
      Navigator.of(context).pop();
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر ربط المحل. حاول مرة أخرى.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة محل'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MerchantPicker(
                selected: _merchantId,
                excludedIds: widget.excludedIds,
                onChanged: (id) => setState(() => _merchantId = id),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}

/// The form the owner fills to mint one account.
class _CreateStaffDialog extends ConsumerStatefulWidget {
  const _CreateStaffDialog();

  @override
  ConsumerState<_CreateStaffDialog> createState() => _CreateStaffDialogState();
}

class _CreateStaffDialogState extends ConsumerState<_CreateStaffDialog> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  String _scope = 'merchant';
  String _role = 'owner';

  String? _merchantId;

  bool get _isMerchantScope => _scope == 'merchant';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final result = await ref.read(staffRepositoryProvider).createAccount(
          email: _email.text.trim(),
          password: _password.text,
          name: _name.text.trim(),
          scope: _scope,
          role: _role,
          merchantId: _isMerchantScope ? _merchantId : null,
        );
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('حساب جديد'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('staff.email'),
                controller: _email,
                decoration: const InputDecoration(labelText: 'الإيميل'),
                keyboardType: TextInputType.emailAddress,
                validator: (v) =>
                    v != null && v.contains('@') ? null : 'اكتب إيميل صحيح',
              ),
              TextFormField(
                key: const Key('staff.password'),
                controller: _password,
                decoration:
                    const InputDecoration(labelText: 'كلمة السر (8 حروف على الأقل)'),
                obscureText: true,
                validator: (v) =>
                    v != null && v.length >= 8 ? null : '8 حروف على الأقل',
              ),
              TextFormField(
                key: const Key('staff.name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'الاسم'),
              ),
              DropdownButtonFormField<String>(
                key: const Key('staff.scope'),
                initialValue: _scope,
                decoration: const InputDecoration(labelText: 'النطاق'),
                items: const [
                  DropdownMenuItem(value: 'merchant', child: Text('مطعم')),
                  DropdownMenuItem(value: 'platform', child: Text('المنصة')),
                ],
                onChanged: (v) => setState(() {
                  _scope = v ?? _scope;
                  _role = _isMerchantScope ? 'owner' : 'admin';
                }),
              ),
              DropdownButtonFormField<String>(
                key: const Key('staff.role'),
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: _isMerchantScope
                    ? const [
                        DropdownMenuItem(value: 'owner', child: Text('صاحب مطعم')),
                        DropdownMenuItem(value: 'courier', child: Text('دليفري')),
                      ]
                    : const [
                        DropdownMenuItem(value: 'admin', child: Text('أدمن')),
                        DropdownMenuItem(value: 'moderator', child: Text('مشرف')),
                      ],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              if (_isMerchantScope)
                _MerchantPicker(
                  selected: _merchantId,
                  onChanged: (id) => setState(() => _merchantId = id),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: StaffScreen.submitKey,
          onPressed: _submit,
          child: const Text('اعمل الحساب'),
        ),
      ],
    );
  }
}

/// Which shop an account belongs to, chosen from the list of them.
///
/// A dropdown of names rather than a box for a uuid. Reused across staff creation
/// and courier attachment addition.
class _MerchantPicker extends ConsumerWidget {
  const _MerchantPicker({
    required this.selected,
    required this.onChanged,
    this.excludedIds = const {},
  });

  final String? selected;
  final ValueChanged<String?> onChanged;
  final Set<String> excludedIds;

  static const pickerKey = Key('staff.merchant');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchants = ref.watch(allMerchantsProvider);

    return switch (merchants) {
      AsyncValue(hasError: true) => const InputDecorator(
          decoration: InputDecoration(labelText: 'المطعم'),
          child: Text('مقدرناش نجيب المطاعم. اقفل وافتح تاني.'),
        ),
      AsyncValue(hasValue: true, :final value?) => DropdownButtonFormField<String>(
          key: pickerKey,
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'المطعم'),
          items: [
            for (final merchant in value)
              if (!excludedIds.contains(merchant.id))
                DropdownMenuItem(
                  value: merchant.id,
                  child: Text(merchant.name, overflow: TextOverflow.ellipsis),
                ),
          ],
          onChanged: onChanged,
          validator: (v) => v != null && v.isNotEmpty ? null : 'اختار المطعم',
        ),
      _ => const InputDecorator(
          decoration: InputDecoration(labelText: 'المطعم'),
          child: Text('بنجيب المطاعم…'),
        ),
    };
  }
}
