import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../billing/merchant_billing_screen.dart';
import '../shell/layout.dart';
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

  static Key pendingBadgeKey(String id) => Key('merchants.pending.$id');
  static Key rowKey(String id) => Key('merchants.row.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchants = ref.watch(allMerchantsProvider);
    final selectedId = ref.watch(selectedMerchantProvider);
    final layout = AdminLayout.of(context);

    final selected = merchants.value?.where((m) => m.id == selectedId).firstOrNull;

    // On a phone the detail replaces the list; there is no room to squeeze both, and a
    // half-width menu editor is worse than no second pane at all.
    if (!layout.showsTwoPanes && selected != null) {
      return _Detail(
        merchant: selected,
        onBack: () => ref.read(selectedMerchantProvider.notifier).select(null),
      );
    }

    final list = _List(merchants: merchants, selectedId: selectedId);

    return Scaffold(
      appBar: AppBar(title: const Text('المطاعم')),
      body: layout.showsTwoPanes
          ? Row(
              children: [
                Expanded(flex: 2, child: list),
                VerticalDivider(width: 1, color: Theme.of(context).luqma.hairline),
                Expanded(
                  flex: 3,
                  child: selected == null
                      ? const _NothingSelected()
                      : _Detail(merchant: selected),
                ),
              ],
            )
          : list,
      floatingActionButton: FloatingActionButton.extended(
        key: MerchantsScreen.addKey,
        onPressed: () => _addMerchant(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('مطعم'),
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.merchants, required this.selectedId});

  final AsyncValue<List<Merchant>> merchants;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LuqmaAsyncView(
      value: merchants,
      onRetry: () => ref.invalidate(allMerchantsProvider),
      empty: Center(
          key: MerchantsScreen.emptyKey,
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Text(
              'مفيش مطاعم لسه.\nابدأ بإضافة أول مطعم.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).luqma.textSecondary,
                  ),
            ),
          ),
        ),
      isEmpty: (value) => value.isEmpty,
      builder: (context, value) => ListView.separated(
          padding: const EdgeInsets.all(Space.gutter),
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
          itemBuilder: (context, i) => _Row(
            merchant: value[i],
            selected: value[i].id == selectedId,
            onTap: () => ref
                .read(selectedMerchantProvider.notifier)
                .select(value[i].id),
          ),
        )
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.merchant, required this.selected, required this.onTap});

  final Merchant merchant;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

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
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(merchant.name, style: theme.textTheme.titleMedium),
                  Text(
                    merchant.type == MerchantType.homeKitchen
                        ? 'أكل بيتي'
                        : 'مطعم',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            // Only the states that need a person: approved is the normal case and says
            // nothing worth taking up room for.
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
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'اختر مطعم من اللستة',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.luqma.textSecondary),
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
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final actions = ref.read(merchantActionsProvider.notifier);
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
              onPressed: () =>
                  actions.setStatus(merchant.id, MerchantStatus.approved),
              child: Text('اعتماد', style: TextStyle(color: colors.onBrand)),
            )
          else
            TextButton(
              key: MerchantsScreen.suspendKey,
              onPressed: () =>
                  actions.setStatus(merchant.id, MerchantStatus.suspended),
              child: Text('إيقاف', style: TextStyle(color: colors.onBrand)),
            ),
          // Delete only while the merchant never traded. Once it has an order the
          // control is disabled and the reason is said in the tooltip — history exists,
          // and history wins. The real count is queried, never a field that can drift.
          IconButton(
            key: MerchantsScreen.deleteKey,
            tooltip: switch (orderCount.value ?? 0) {
              0 => 'حذف المطعم',
              final n => 'مينفعش حذف — عنده $n طلب',
            },
            icon: const Icon(Icons.delete_outline),
            onPressed: (orderCount.value ?? 0) == 0
                ? () => _confirmDelete(context, ref)
                : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Space.gutter),
            child: Row(
              children: [
                Icon(Icons.phone, size: Sizes.iconSm, color: colors.textSecondary),
                const SizedBox(width: Space.sm),
                Text(merchant.phone, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
          Divider(height: 1, color: colors.hairline),
          // The menu is most of what this screen is for, so it gets the rest of the
          // space rather than sharing it with fields that are set once.
          Expanded(child: MenuEditor(merchantId: merchant.id)),
        ],
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

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _NewMerchantDialog(
      zones: zones,
      onSave: (name, phone, zoneId, type) async {
        final created = await ref.read(merchantActionsProvider.notifier).create(
              name: name,
              phone: phone,
              zoneId: zoneId,
              type: type,
            );
        if (created != null) {
          // Straight into the new merchant: the next thing after adding one is always
          // entering its menu.
          ref.read(selectedMerchantProvider.notifier).select(created.id);
        }
        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
      },
    ),
  );
}

class _NewMerchantDialog extends StatefulWidget {
  const _NewMerchantDialog({required this.zones, required this.onSave});

  final List<Zone> zones;
  final Future<void> Function(
    String name,
    String phone,
    String zoneId,
    MerchantType type,
  ) onSave;

  @override
  State<_NewMerchantDialog> createState() => _NewMerchantDialogState();
}

class _NewMerchantDialogState extends State<_NewMerchantDialog> {
  final _formKey = GlobalKey<FormState>();

  var _name = '';
  var _phone = '';
  late String? _zoneId = widget.zones.firstOrNull?.id;
  var _type = MerchantType.restaurant;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('مطعم جديد'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: MerchantsScreen.nameFieldKey,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'الاسم'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'اكتب اسم المطعم' : null,
              onSaved: (v) => _name = v!.trim(),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              key: MerchantsScreen.phoneFieldKey,
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
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            if (widget.zones.isNotEmpty) ...[
              const SizedBox(height: Space.md),
              DropdownButtonFormField<String>(
                initialValue: _zoneId,
                decoration: const InputDecoration(labelText: 'المنطقة'),
                items: [
                  for (final zone in widget.zones)
                    DropdownMenuItem(value: zone.id, child: Text(zone.name)),
                ],
                onChanged: (v) => setState(() => _zoneId = v),
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
          key: MerchantsScreen.saveKey,
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            _formKey.currentState!.save();
            widget.onSave(_name, _phone, _zoneId ?? '', _type);
          },
          child: const Text('احفظ'),
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
    final result = await ref.read(merchantRepositoryProvider).saveMerchant(
          widget.merchant.copyWith(
            logoMediaId: _logoId,
            coverMediaId: _coverId,
            description: typed.isEmpty ? null : typed,
          ),
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
                  height: 96,
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
                  height: 120,
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
