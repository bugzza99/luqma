import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../merchants/merchants_controller.dart';
import '../shell/layout.dart';
import 'staff_controller.dart';

/// Watches all active attachments (shops plus platform) for a single courier.
final courierAttachmentsProvider = StreamProvider.autoDispose
    .family<List<CourierRosterItem>, String>(
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
  static const newPasswordFieldKey = Key('staff.new_password');
  static const confirmPasswordFieldKey = Key('staff.confirm_password');
  static const changePasswordKey = Key('staff.change_password');
  static const toggleNewPasswordVisibilityKey = Key(
    'staff.toggle_new_password',
  );
  static const toggleConfirmPasswordVisibilityKey = Key(
    'staff.toggle_confirm_password',
  );
  static const deleteAccountKey = Key('staff.delete_account');
  static const confirmDeleteAccountKey = Key('staff.confirm_delete_account');

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
      for (final m in merchantsAsync.value ?? const <Merchant>[]) m.id: m,
    };

    // Keep selected courier reference fresh with latest state if the list re-emits.
    final currentCourier = staffAsync.value
        ?.where((m) => m.uid == _selectedCourier?.uid)
        .firstOrNull;
    if (currentCourier != null) {
      _selectedCourier = currentCourier;
    } else if (staffAsync.hasValue && _selectedCourier != null) {
      _selectedCourier = null;
    }

    // On narrow screens (phone), the staff detail replaces the staff list so that
    // controls have sufficient touch target size and never overflow.
    if (!layout.showsTwoPanes && _selectedCourier != null) {
      // Back steps out of the detail to the list, as the arrow does, rather than leaving
      // «الفريق» altogether.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _selectedCourier = null);
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_forward),
              tooltip: 'رجوع',
              onPressed: () => setState(() => _selectedCourier = null),
            ),
            title: Text(
              _selectedCourier!.name?.isNotEmpty == true
                  ? _selectedCourier!.name!
                  : (_selectedCourier!.role == 'courier'
                        ? 'ارتباطات الكابتن'
                        : 'تفاصيل الحساب'),
            ),
          ),
          body: AdminContent(
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Space.gutter),
                child: _CourierDetailView(
                  // Keyed by the account: a password change or deletion still in flight for
                  // one member must not finish into the pane of the next one selected.
                  key: ValueKey(_selectedCourier!.uid),
                  courier: _selectedCourier!,
                  merchantsMap: merchantsMap,
                  onDeleted: () {
                    setState(() => _selectedCourier = null);
                    ref.invalidate(staffListProvider);
                  },
                ),
              ),
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
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
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
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(Space.gutter),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: Space.sm),
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
                          onTap: () =>
                              setState(() => _selectedCourier = member),
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
                crossAxisAlignment: CrossAxisAlignment.start,
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
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: colors.textSecondary),
                                ),
                              ],
                            ),
                          )
                        : Align(
                            alignment: Alignment.topCenter,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(Space.gutter),
                              child: _CourierDetailView(
                                key: ValueKey(_selectedCourier!.uid),
                                courier: _selectedCourier!,
                                merchantsMap: merchantsMap,
                                onClose: () =>
                                    setState(() => _selectedCourier = null),
                                onDeleted: () {
                                  setState(() => _selectedCourier = null);
                                  ref.invalidate(staffListProvider);
                                },
                              ),
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
    if (member.isActive) {
      final name = member.name?.isNotEmpty == true ? member.name! : member.uid;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تعطيل الحساب'),
          content: Text('$name مش هيقدر يدخل لحد ما تفعّله تاني.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('تعطيل'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    final result = await ref
        .read(staffRepositoryProvider)
        .setActive(member.uid, active: !member.isActive);
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (result is Ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            member.isActive ? 'تم تعطيل الحساب' : 'تم تفعيل الحساب',
          ),
        ),
      );
    } else if (result case Err(:final failure)) {
      final reason = switch (failure) {
        PermissionFailure() => 'مش مسموحلك تعدل حالة الحساب.',
        NotFoundFailure() => 'الحساب مش موجود.',
        OfflineFailure() => 'مفيش نت — جرّب تاني.',
        _ => 'معرفناش نغير حالة الحساب. جرّب تاني.',
      };
      messenger.showSnackBar(SnackBar(content: Text(reason)));
    }
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final created = await showDialog<StaffMember>(
      context: context,
      builder: (_) => const _CreateStaffDialog(),
    );
    if (!mounted || created == null) return;

    ref.invalidate(staffListProvider);
    messenger.showSnackBar(
      SnackBar(content: Text('اتعمل الحساب لـ ${created.name ?? created.uid}')),
    );
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
      onTap: onTap,
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
                Icon(Icons.chevron_left, color: colors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// The detail pane/sheet for managing a staff member's attachments, password, and account.
class _CourierDetailView extends ConsumerStatefulWidget {
  const _CourierDetailView({
    super.key,
    required this.courier,
    required this.merchantsMap,
    this.onClose,
    this.onDeleted,
  });

  final StaffMember courier;
  final Map<String, Merchant> merchantsMap;
  final VoidCallback? onClose;
  final VoidCallback? onDeleted;

  @override
  ConsumerState<_CourierDetailView> createState() => _CourierDetailViewState();
}

class _CourierDetailViewState extends ConsumerState<_CourierDetailView> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _changingPassword = false;
  bool _deletingAccount = false;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CourierDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courier.uid != widget.courier.uid) {
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    }
  }

  Future<void> _changePassword() async {
    // Trimmed as the server trims it, so what passes here is what the server accepts.
    final password = _newPasswordController.text.trim();
    setState(() => _changingPassword = true);
    final result = await ref
        .read(customerRepositoryProvider)
        .setPassword(widget.courier.uid, password);
    if (!mounted) return;
    setState(() => _changingPassword = false);

    final messenger = ScaffoldMessenger.of(context);

    if (result is Ok) {
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      messenger.showSnackBar(const SnackBar(content: Text('اتغيرت كلمة السر')));
    } else if (result case Err(:final failure)) {
      final message = switch (failure) {
        PermissionFailure() => 'مش مسموح لك تغيّر كلمة السر.',
        NotFoundFailure() => 'الحساب مش موجود.',
        OfflineFailure() => 'مفيش نت — اتأكد من اتصالك وجرّب تاني.',
        _ => 'مقدرناش نغيّر كلمة السر. حاول تاني.',
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _deleteAccount() async {
    final colors = Theme.of(context).luqma;
    final isOwner = widget.courier.role == 'owner';

    final noticeText = isOwner
        ? 'المحل هيفضل موجود من غير صاحب لحد ما تربطه بحساب تاني'
        : 'هيتشال من كل المحلات';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الحساب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(noticeText),
            const SizedBox(height: Space.xs),
            const Text('مش هتقدر ترجع في الخطوة دي بعد ما تحذف.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            key: StaffScreen.confirmDeleteAccountKey,
            style: TextButton.styleFrom(foregroundColor: colors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('احذف نهائياً'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deletingAccount = true);
    final result = await ref
        .read(adminRepositoryProvider)
        .deleteAccount(widget.courier.uid);
    if (!mounted) return;
    setState(() => _deletingAccount = false);

    final messenger = ScaffoldMessenger.of(context);

    if (result is Ok) {
      messenger.showSnackBar(const SnackBar(content: Text('الحساب اتحذف')));
      widget.onDeleted?.call();
    } else if (result case Err(:final failure)) {
      final message = switch (failure) {
        // Carrying an order right now: deleting them would take the courier off food
        // in the street. Nothing to retry until the order is finished.
        OrderInFlightFailure() =>
          'المندوب ده شايل طلب دلوقتي. استنى لما الطلب يخلص وبعدين احذفه.',
        PermissionFailure() => 'مش مسموح لك تحذف الحساب.',
        NotFoundFailure() => 'الحساب مش موجود.',
        OfflineFailure() => 'مفيش نت — اتأكد من اتصالك وجرّب تاني.',
        _ => 'مقدرناش نحذف الحساب. حاول تاني.',
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Widget _buildPasswordBlock(
    BuildContext context,
    LuqmaColors colors,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.border),
        boxShadow: Elevations.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'كلمة السر',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: Space.md),
          Builder(
            builder: (context) {
              final p1 = _newPasswordController.text.trim();
              final p2 = _confirmPasswordController.text.trim();

              String? p1Error;
              if (p1.isNotEmpty && (p1.length < 8 || p1.length > 72)) {
                p1Error = 'كلمة السر لازم تكون 8 حروف على الأقل.';
              }

              String? p2Error;
              if (p2.isNotEmpty && p1 != p2) {
                p2Error = 'كلمتي السر مش متطابقتين.';
              }

              final canSubmit =
                  p1.length >= 8 &&
                  p1.length <= 72 &&
                  p1 == p2 &&
                  !_changingPassword;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    key: StaffScreen.newPasswordFieldKey,
                    controller: _newPasswordController,
                    obscureText: _obscureNew,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'كلمة السر الجديدة',
                      errorText: p1Error,
                      suffixIcon: IconButton(
                        key: StaffScreen.toggleNewPasswordVisibilityKey,
                        icon: Icon(
                          _obscureNew
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        tooltip: _obscureNew
                            ? 'إظهار كلمة السر'
                            : 'إخفاء كلمة السر',
                        onPressed: () =>
                            setState(() => _obscureNew = !_obscureNew),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: Space.sm),
                  TextFormField(
                    key: StaffScreen.confirmPasswordFieldKey,
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirm,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'اكتبها تاني',
                      errorText: p2Error,
                      suffixIcon: IconButton(
                        key: StaffScreen.toggleConfirmPasswordVisibilityKey,
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        tooltip: _obscureConfirm
                            ? 'إظهار كلمة السر'
                            : 'إخفاء كلمة السر',
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: Space.md),
                  FilledButton(
                    key: StaffScreen.changePasswordKey,
                    onPressed: canSubmit ? _changePassword : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(Sizes.minTarget),
                    ),
                    child: _changingPassword
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('غيّر كلمة السر'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteAction(
    BuildContext context,
    LuqmaColors colors,
    ThemeData theme,
  ) {
    return Center(
      child: TextButton.icon(
        key: StaffScreen.deleteAccountKey,
        onPressed: _deletingAccount ? null : _deleteAccount,
        icon: Icon(Icons.delete_forever_outlined, color: colors.danger),
        label: Text(
          'احذف الحساب',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.danger,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: TextButton.styleFrom(
          foregroundColor: colors.danger,
          minimumSize: const Size(Sizes.minTarget, Sizes.minTarget),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final courier = widget.courier;
    final isCourier = courier.role == 'courier';
    final isOwner = courier.role == 'owner';
    final attachmentsAsync = isCourier
        ? ref.watch(courierAttachmentsProvider(courier.uid))
        : null;

    final headerIcon = isCourier
        ? Icons.delivery_dining
        : (isOwner
              ? Icons.storefront_outlined
              : Icons.admin_panel_settings_outlined);
    final headerColor = isCourier
        ? colors.price
        : (isOwner ? colors.success : colors.brand);

    final merchantName = courier.merchantId != null
        ? widget.merchantsMap[courier.merchantId]?.name
        : null;

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
                  color: headerColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(headerIcon, color: colors.onBrand, size: 24),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      courier.name?.isNotEmpty == true
                          ? courier.name!
                          : (StaffScreen._roleLabels[courier.role] ?? 'حساب'),
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
                    if (merchantName != null && merchantName.isNotEmpty) ...[
                      const SizedBox(height: Space.xs / 2),
                      Text(
                        'مطعم: $merchantName',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  tooltip: 'إغلاق',
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
            ],
          ),
        ),

        // Live active attachments and actions (couriers only)
        if (isCourier && attachmentsAsync != null) ...[
          const SizedBox(height: Space.lg),
          LuqmaAsyncView<List<CourierRosterItem>>(
            value: attachmentsAsync,
            onRetry: () =>
                ref.invalidate(courierAttachmentsProvider(courier.uid)),
            empty: _buildEmptyOrActive(context, const []),
            isEmpty: (items) => items.isEmpty,
            builder: (context, items) => _buildEmptyOrActive(context, items),
          ),
        ],

        // Typed-password block for merchant-scope staff (owner or courier): the reset
        // refuses every platform-scope account.
        if (courier.scope == 'merchant') ...[
          const SizedBox(height: Space.lg),
          _buildPasswordBlock(context, colors, theme),
        ],
        // Delete for merchant-scope staff, and for a platform courier since the owner's
        // decision of 2026-09-23. Platform admins and moderators are never deleted here.
        if (courier.scope == 'merchant' || courier.role == 'courier') ...[
          const SizedBox(height: Space.xl),
          _buildDeleteAction(context, colors, theme),
          const SizedBox(height: Space.lg),
        ],
      ],
    );
  }

  Widget _buildEmptyOrActive(
    BuildContext context,
    List<CourierRosterItem> items,
  ) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final l10n = LuqmaStrings.of(context);

    // Platform row is represented by merchantId == null
    final hasPlatform = items.any(
      (item) => item.merchantId == null && item.isActive,
    );
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
              onPressed: () => _openAddShop(context, attachedMerchantIds),
              icon: const Icon(Icons.add_business_outlined),
              label: Text(l10n.courierAddShop),
            ),
            // Only offered when the courier does not already hold the platform row.
            if (!hasPlatform)
              FilledButton.icon(
                onPressed: () => _attachToPlatform(context),
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
                        widget.merchantsMap[item.merchantId]?.name ??
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
                      onPressed: () => _confirmAndDetach(context, item),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _attachToPlatform(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(courierRosterRepositoryProvider)
        .attachCourierToMerchant(
          courierUid: widget.courier.uid,
          merchantId: null,
        );

    if (result is Err && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تعذر ربط الكابتن بالمنصة. حاول مرة أخرى.'),
        ),
      );
    }
  }

  Future<void> _openAddShop(
    BuildContext context,
    Set<String> attachedMerchantIds,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AddShopDialog(
        courierUid: widget.courier.uid,
        excludedIds: attachedMerchantIds,
      ),
    );
  }

  Future<void> _confirmAndDetach(
    BuildContext context,
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
          courierUid: widget.courier.uid,
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
  const _AddShopDialog({required this.courierUid, this.excludedIds = const {}});

  final String courierUid;
  final Set<String> excludedIds;

  @override
  ConsumerState<_AddShopDialog> createState() => _AddShopDialogState();
}

class _AddShopDialogState extends ConsumerState<_AddShopDialog> {
  String? _merchantId;
  final _form = GlobalKey<FormState>();
  bool _submitting = false;

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref
        .read(courierRosterRepositoryProvider)
        .attachCourierToMerchant(
          courierUid: widget.courierUid,
          merchantId: _merchantId,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
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
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
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
  bool _submitting = false;
  String? _error;

  bool get _isMerchantScope => _scope == 'merchant';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_form.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref
        .read(staffRepositoryProvider)
        .createAccount(
          email: _email.text.trim(),
          password: _password.text,
          name: _name.text.trim(),
          scope: _scope,
          role: _role,
          merchantId: _isMerchantScope ? _merchantId : null,
        );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (result is Ok<StaffMember>) {
      Navigator.of(context).pop(result.value);
    } else if (result case Err(:final failure)) {
      final msg = switch (failure) {
        EmailTakenFailure() => 'الإيميل ده متسجل قبل كده.',
        PermissionFailure() => 'مش مسموحلك تعمل حسابات.',
        ConflictFailure() => 'فيه معلومة ناقصة أو غلط.',
        OfflineFailure() => 'مفيش نت — جرّب تاني.',
        _ => 'معرفناش نعمل الحساب. جرّب تاني.',
      };
      setState(() => _error = msg);
    }
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
                decoration: const InputDecoration(
                  labelText: 'كلمة السر (8 حروف على الأقل)',
                ),
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
                        DropdownMenuItem(
                          value: 'owner',
                          child: Text('صاحب مطعم'),
                        ),
                        DropdownMenuItem(
                          value: 'courier',
                          child: Text('دليفري'),
                        ),
                      ]
                    : const [
                        DropdownMenuItem(value: 'admin', child: Text('أدمن')),
                        DropdownMenuItem(
                          value: 'moderator',
                          child: Text('مشرف'),
                        ),
                      ],
                onChanged: (v) => setState(() => _role = v ?? _role),
              ),
              if (_isMerchantScope)
                _MerchantPicker(
                  selected: _merchantId,
                  onChanged: (id) => setState(() => _merchantId = id),
                ),
              // Said inside the form as well: a SnackBar under a dialog is half hidden.
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(
                    _error!,
                    key: const Key('staff.create-error'),
                    style: TextStyle(color: Theme.of(context).luqma.danger),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          key: StaffScreen.submitKey,
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('اعمل الحساب'),
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
      AsyncValue(hasValue: true, :final value?) =>
        DropdownButtonFormField<String>(
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
