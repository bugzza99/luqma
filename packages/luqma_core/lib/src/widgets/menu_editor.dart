import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/money.dart';
import '../models/media.dart';
import '../models/menu_item.dart';
import '../models/merchant.dart';
import '../models/money.dart';
import '../providers/providers.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';
import '../theme/typography.dart';
import '../result.dart';
import 'chip.dart';
import 'error_view.dart';
import 'luqma_image.dart';
import 'media_picker.dart';

/// Editing a merchant's menu.
///
/// The same widget serves MerchantApp and AdminApp. That is not a convenience: the owner
/// enters every menu personally during onboarding and merchants edit theirs afterwards,
/// so two implementations would be two sets of validation rules over the same data, and
/// they would drift. The only thing that differs is where [merchantId] comes from.
class MenuEditor extends ConsumerStatefulWidget {
  const MenuEditor({super.key, required this.merchantId});

  final String merchantId;

  static const nameFieldKey = Key('menu.name');
  static const priceFieldKey = Key('menu.price');
  static const descriptionFieldKey = Key('menu.description');
  static const availableSwitchKey = Key('menu.available');
  static const saveItemKey = Key('menu.saveItem');
  static const deleteItemKey = Key('menu.deleteItem');
  static const confirmDeleteKey = Key('menu.confirmDelete');
  static const itemPhotoKey = Key('menu.itemPhoto');
  static const addCategoryKey = Key('menu.addCategory');
  static const categoryNameFieldKey = Key('menu.categoryName');
  static const saveCategoryKey = Key('menu.saveCategory');
  static const allCategoriesChipKey = Key('menu.categoryChip.all');
  static const pendingReviewBannerKey = Key('menu.pendingReviewBanner');
  static const emptyAddCategoryKey = Key('menu.emptyAddCategory');

  static Key renameCategoryKey(String categoryId) => Key('menu.renameCategory.$categoryId');
  static Key offersHintKey(String categoryId) => Key('menu.offersHint.$categoryId');

  static Key categoryChipKey(String categoryId) =>
      Key('menu.categoryChip.$categoryId');
  static Key addItemKey(String categoryId) => Key('menu.addItem.$categoryId');
  static Key unavailableKey(String itemId) => Key('menu.unavailable.$itemId');
  static Key itemAvailableSwitchKey(String itemId) =>
      Key('menu.itemAvailableSwitch.$itemId');
  static Key itemKebabKey(String itemId) => Key('menu.itemKebab.$itemId');

  @override
  ConsumerState<MenuEditor> createState() => _MenuEditorState();
}

class _MenuEditorState extends ConsumerState<MenuEditor> {
  String? _selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    final strings = LuqmaStrings.of(context);
    final categoriesAsync = ref.watch(menuCategoriesProvider(widget.merchantId));
    // Loading and failing are not "this menu is empty". Treating them as empty offered the
    // add button over a menu that had not arrived yet — harmless now that adding touches
    // one row, but a lie about the shop either way.
    if (categoriesAsync.hasError && !categoriesAsync.hasValue) {
      return LuqmaErrorView(
        failure: categoriesAsync.error,
        onRetry: () => ref.invalidate(menuCategoriesProvider(widget.merchantId)),
      );
    }
    if (!categoriesAsync.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final categories = categoriesAsync.value!;
    final items =
        ref.watch(menuItemsProvider(widget.merchantId)).value ??
        const <MenuItem>[];

    // An empty menu used to be a sentence and nothing else: the add-category chip lives in
    // the row of category chips, which is only drawn above a list that already has one. The
    // first real shop opened this screen, in the partner app and in AdminApp, and had no
    // way to start. The server gives a restaurant four shelves now, but a shop that deleted
    // them all — or a home kitchen that wants one — must still find a way in.
    if (categories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.menuNoCategories, textAlign: TextAlign.center),
              const SizedBox(height: Space.lg),
              FilledButton.icon(
                key: MenuEditor.emptyAddCategoryKey,
                onPressed: () => _addCategory(context, ref, widget.merchantId, categories),
                icon: const Icon(Icons.add),
                label: const Text('أضف قسم'),
              ),
            ],
          ),
        ),
      );
    }

    final filteredCategories = _selectedCategoryId == null
        ? categories
        : categories.where((c) => c.id == _selectedCategoryId).toList();

    return Column(
      children: [
        // Category filter chips across the top (M03)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.gutter,
            vertical: Space.sm,
          ),
          child: Row(
            children: [
              LuqmaChip(
                key: MenuEditor.allCategoriesChipKey,
                label: '${strings.menuAllCategories} (${items.length})',
                selected: _selectedCategoryId == null,
                onTap: () => setState(() => _selectedCategoryId = null),
              ),
              const SizedBox(width: Space.sm),
              for (final category in categories) ...[
                LuqmaChip(
                  key: MenuEditor.categoryChipKey(category.id),
                  label:
                      '${category.name} (${items.where((i) => i.categoryId == category.id).length})',
                  selected: _selectedCategoryId == category.id,
                  onTap: () => setState(() => _selectedCategoryId = category.id),
                ),
                const SizedBox(width: Space.sm),
              ],
              LuqmaChip(
                key: MenuEditor.addCategoryKey,
                label: strings.menuAddCategory,
                selected: false,
                dashed: true,
                onTap: () => _addCategory(
                  context,
                  ref,
                  widget.merchantId,
                  categories,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(Space.gutter),
            children: [
              for (final category in filteredCategories)
                _CategorySection(
                  merchantId: widget.merchantId,
                  category: category,
                  categories: categories,
                  items: items.where((i) => i.categoryId == category.id).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addCategory(
    BuildContext context,
    WidgetRef ref,
    String merchantId,
    List<MenuCategory> categories,
  ) async {
    final controller = TextEditingController();
    final strings = LuqmaStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.menuNewCategory),
        content: TextField(
          key: MenuEditor.categoryNameFieldKey,
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: strings.menuCategoryNameRequired,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.menuCancel),
          ),
          FilledButton(
            key: MenuEditor.saveCategoryKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.addressSave),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && controller.text.trim().isNotEmpty) {
      final newName = controller.text.trim();
      final nextSort = categories.isEmpty
          ? 0
          : categories.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
      // One row, not the whole list: see `MenuRepository.addCategory`.
      final result = await ref
          .read(menuRepositoryProvider)
          .addCategory(merchantId, newName, nextSort);
      if (result is Err && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مقدرناش نضيف القسم. اتأكد من النت وجرّب تاني.')),
        );
      }
    }
  }
}

/// Renames through the same save the add path uses, so the server sees one list either way.
extension on _CategorySection {
  Future<void> _renameCategory(BuildContext context, WidgetRef ref) async {
    final strings = LuqmaStrings.of(context);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _RenameCategoryDialog(
        initial: category.name,
        label: strings.menuCategoryNameRequired,
        cancel: strings.menuCancel,
        save: strings.addressSave,
      ),
    );
    // The section can vanish while the dialog is open — the other app deleted it, and the
    // list rebuilt without it — and `ref` belongs to a widget that is gone by then.
    if (!context.mounted) return;
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == category.name) return;

    // One row, not the whole list: a list captured before the dialog opened would delete
    // whatever the other app added while it was open.
    final result = await ref
        .read(menuRepositoryProvider)
        .renameCategory(merchantId, category.id, trimmed);
    if (result is Err && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('مقدرناش نغيّر اسم «${category.name}». جرّب تاني.')),
      );
    }
  }
}

/// Owns its controller, so the controller outlives the closing animation rather than
/// being disposed under a text field that is still on screen.
class _RenameCategoryDialog extends StatefulWidget {
  const _RenameCategoryDialog({
    required this.initial,
    required this.label,
    required this.cancel,
    required this.save,
  });

  final String initial;
  final String label;
  final String cancel;
  final String save;

  @override
  State<_RenameCategoryDialog> createState() => _RenameCategoryDialogState();
}

class _RenameCategoryDialogState extends State<_RenameCategoryDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اسم القسم'),
      content: TextField(
        key: MenuEditor.categoryNameFieldKey,
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.cancel),
        ),
        FilledButton(
          key: MenuEditor.saveCategoryKey,
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.save),
        ),
      ],
    );
  }
}

class _CategorySection extends ConsumerWidget {
  const _CategorySection({
    required this.merchantId,
    required this.category,
    required this.categories,
    required this.items,
  });

  final String merchantId;
  final MenuCategory category;
  final List<MenuCategory> categories;
  final List<MenuItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strings = LuqmaStrings.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(category.name, style: theme.textTheme.titleLarge),
              ),
              // The four shelves a restaurant starts with are a starting point, not a rule:
              // a shop that sells sandwiches calls the first one what it is.
              IconButton(
                key: MenuEditor.renameCategoryKey(category.id),
                tooltip: 'تغيير اسم القسم',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _renameCategory(context, ref),
              ),
              TextButton(
                key: MenuEditor.addItemKey(category.id),
                onPressed: () => _editItem(
                  context,
                  ref,
                  merchantId,
                  null,
                  category.id,
                  categories,
                ),
                child: Text(strings.menuAddItem),
              ),
            ],
          ),
          // The shop cannot see the customer's home, so it is told here: this is the one
          // shelf whose dishes leave the shop and appear on everybody's first screen.
          if (category.isOffers)
            Padding(
              key: MenuEditor.offersHintKey(category.id),
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'اللي تحطه هنا بيظهر للعملاء في «العروض» في أول الصفحة الرئيسية.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.luqma.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: Space.sm),
          for (final item in items)
            _ItemRow(
              item: item,
              categories: categories,
              merchantId: merchantId,
              onTap: () => _editItem(
                context,
                ref,
                merchantId,
                item,
                category.id,
                categories,
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  const _ItemRow({
    required this.item,
    required this.categories,
    required this.merchantId,
    required this.onTap,
  });

  final MenuItem item;
  final List<MenuCategory> categories;
  final String merchantId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Opacity(
      opacity: item.isAvailable ? 1.0 : 0.62,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.cardAll,
        child: Container(
          margin: const EdgeInsets.only(bottom: Space.sm),
          padding: const EdgeInsets.all(Space.md),
          constraints: const BoxConstraints(minHeight: Sizes.minTarget),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: Radii.cardAll,
            border: Border.all(color: colors.hairline),
            boxShadow: Elevations.card,
          ),
          child: Row(
            children: [
              // Dish thumbnail or monogram (48x48 rounded 8)
              ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: LuqmaImage(
                    url: item.imageUrl,
                    name: item.name,
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      strings.price(item.price),
                      style: LuqmaType.priceSmall.copyWith(
                        color: colors.price,
                      ),
                    ),
                    if (!item.isAvailable)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          strings.menuUnavailable,
                          key: MenuEditor.unavailableKey(item.id),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.danger,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Availability toggle directly on row (M03)
              Switch(
                key: MenuEditor.itemAvailableSwitchKey(item.id),
                value: item.isAvailable,
                activeThumbColor: colors.success,
                onChanged: (val) async {
                  await ref
                      .read(menuRepositoryProvider)
                      .saveItem(item.copyWith(isAvailable: val));
                },
              ),
              // Kebab menu for actions (M03)
              PopupMenuButton<String>(
                key: MenuEditor.itemKebabKey(item.id),
                tooltip: 'خيارات',
                icon: const Icon(Icons.more_vert, size: Sizes.iconMd),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined, size: Sizes.iconSm),
                        const SizedBox(width: Space.sm),
                        Text(strings.menuEditItem),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: Sizes.iconSm,
                          color: colors.danger,
                        ),
                        const SizedBox(width: Space.sm),
                        Text(
                          strings.menuDeleteItem,
                          style: TextStyle(color: colors.danger),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (val) {
                  if (val == 'edit') {
                    onTap();
                  } else if (val == 'delete') {
                    _confirmDeleteItem(context, ref, item);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteItem(
    BuildContext context,
    WidgetRef ref,
    MenuItem item,
  ) async {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.menuDeleteItemConfirm),
        content: Text('«${item.name}» ${strings.menuDeleteItemMessage}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.menuCancel),
          ),
          FilledButton(
            key: MenuEditor.confirmDeleteKey,
            style: FilledButton.styleFrom(backgroundColor: colors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.menuDeleteConfirmAction),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(menuRepositoryProvider).deleteItem(item.id);
    }
  }
}

Future<void> _editItem(
  BuildContext context,
  WidgetRef ref,
  String merchantId,
  MenuItem? existing,
  String categoryId,
  List<MenuCategory> categories,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
    builder: (sheetContext) => _ItemSheet(
      merchantId: merchantId,
      categoryId: categoryId,
      categories: categories,
      existing: existing,
      onSave: (item) async {
        await ref.read(menuRepositoryProvider).saveItem(item);
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      },
      onDelete: (itemId) async {
        await ref.read(menuRepositoryProvider).deleteItem(itemId);
      },
    ),
  );
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({
    required this.merchantId,
    required this.categoryId,
    required this.categories,
    required this.existing,
    required this.onSave,
    this.onDelete,
  });

  final String merchantId;
  final String categoryId;
  final List<MenuCategory> categories;
  final MenuItem? existing;
  final Future<void> Function(MenuItem) onSave;
  final Future<void> Function(String)? onDelete;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  final _formKey = GlobalKey<FormState>();

  late String _categoryId = widget.categoryId;
  late String _name = widget.existing?.name ?? '';
  late String _price = widget.existing == null
      ? ''
      : Money.format(widget.existing!.price);
  late String? _description = widget.existing?.description;
  late bool _available = widget.existing?.isAvailable ?? true;
  late String? _mediaId = widget.existing?.mediaId;

  /// The picture as it stands. Held rather than looked up: the row the caller handed us
  /// carries an id, and resolving it to a URL is a read this sheet does not need — the
  /// picker draws the dish's monogram until a new photograph replaces it.
  String? _mediaUrl;
  bool _photoPendingReview = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: Space.gutter,
        right: Space.gutter,
        top: Space.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      // Scrolls, because the sheet carries a photograph, form fields, and buttons,
      // and soft keyboards consume half the vertical viewport.
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with title and close action (M04)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? strings.menuNewItem
                          : strings.menuEditItem,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'إغلاق',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: Space.md),

              // Photo slot card with pending review banner (M04)
              Container(
                padding: const EdgeInsets.all(Space.md),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: Radii.cardAll,
                  border: Border.all(color: colors.hairline),
                  boxShadow: Elevations.card,
                ),
                child: Column(
                  children: [
                    MediaPicker(
                      key: MenuEditor.itemPhotoKey,
                      kind: MediaKind.menuItem,
                      url: _mediaUrl ?? widget.existing?.imageUrl,
                      name: _name.isEmpty ? (widget.existing?.name ?? '') : _name,
                      ownerId: widget.existing?.id,
                      onUploaded: (media) => setState(() {
                        _mediaId = media.id;
                        _mediaUrl = media.url;
                        _photoPendingReview = true;
                      }),
                    ),
                    if (_photoPendingReview) ...[
                      const SizedBox(height: Space.sm),
                      Container(
                        key: MenuEditor.pendingReviewBannerKey,
                        width: double.infinity,
                        padding: const EdgeInsets.all(Space.sm),
                        // Tokens, not two amber literals. `CLAUDE.md` is explicit that no
                        // colour is written in a screen, and these two were invented
                        // here — a wash and an ink that exist nowhere else in the
                        // product and that nothing keeps in step with either theme.
                        // A photograph waiting for approval is exactly what the accent
                        // is for, and `priceStrong` is the ink the palette already
                        // records as passing on a pale ground.
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: .12),
                          borderRadius: Radii.fieldAll,
                        ),
                        child: Text(
                          strings.menuItemUnderReview,
                          style: LuqmaType.bodySmall
                              .copyWith(color: colors.price),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: Space.md),

              // Name field
              TextFormField(
                key: MenuEditor.nameFieldKey,
                initialValue: _name,
                decoration: InputDecoration(labelText: strings.menuItemName),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? strings.menuNameRequired
                    : null,
                onSaved: (v) => _name = v!.trim(),
              ),
              const SizedBox(height: Space.md),

              // Category selector if multiple categories exist
              if (widget.categories.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  decoration: const InputDecoration(labelText: 'الفئة'),
                  items: [
                    for (final cat in widget.categories)
                      DropdownMenuItem(
                        value: cat.id,
                        child: Text(cat.name),
                      ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _categoryId = val);
                  },
                ),
                const SizedBox(height: Space.md),
              ],

              // Description field
              TextFormField(
                key: MenuEditor.descriptionFieldKey,
                initialValue: _description,
                decoration: InputDecoration(
                  labelText: strings.menuItemDescription,
                ),
                maxLines: 2,
                onSaved: (v) => _description = v,
              ),
              const SizedBox(height: Space.md),

              // Price field
              TextFormField(
                key: MenuEditor.priceFieldKey,
                initialValue: _price,
                decoration: InputDecoration(
                  labelText: strings.menuItemPrice,
                  suffixText: 'ج',
                ),
                keyboardType: TextInputType.number,
                validator: (v) => Money.parse(v ?? '') == null
                    ? strings.menuPriceInvalid
                    : null,
                onSaved: (v) => _price = v!,
              ),
              const SizedBox(height: Space.md),

              // Availability toggle card (M04)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: Radii.fieldAll,
                  border: Border.all(color: colors.hairline),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.menuItemAvailableTitle,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            strings.menuItemAvailableSubtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      key: MenuEditor.availableSwitchKey,
                      value: _available,
                      activeThumbColor: colors.success,
                      onChanged: (v) => setState(() => _available = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.lg),

              // Action buttons (M04: Delete + Save)
              Row(
                children: [
                  if (widget.existing != null) ...[
                    Expanded(
                      flex: 1,
                      child: OutlinedButton(
                        key: MenuEditor.deleteItemKey,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colors.danger,
                          side: BorderSide(color: colors.danger),
                          minimumSize: const Size.fromHeight(Sizes.minTarget),
                        ),
                        onPressed: () => _confirmDelete(context),
                        child: Text(strings.menuDeleteItem),
                      ),
                    ),
                    const SizedBox(width: Space.md),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: MenuEditor.saveItemKey,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(Sizes.minTarget),
                      ),
                      onPressed: _submit,
                      child: Text(
                        widget.existing == null
                            ? strings.menuSaveItem
                            : strings.menuSaveItemChanges,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.menuDeleteItemConfirm),
        content: Text(
          '«${widget.existing!.name}» ${strings.menuDeleteItemMessage}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.menuCancel),
          ),
          FilledButton(
            key: MenuEditor.confirmDeleteKey,
            style: FilledButton.styleFrom(backgroundColor: colors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.menuDeleteConfirmAction),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      await widget.onDelete?.call(widget.existing!.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    widget.onSave(
      MenuItem(
        id: widget.existing?.id ?? '',
        merchantId: widget.merchantId,
        categoryId: _categoryId,
        name: _name,
        price: Money.parse(_price)!,
        description: _description,
        mediaId: _mediaId,
        isAvailable: _available,
        options: widget.existing?.options ?? const [],
        sortOrder: widget.existing?.sortOrder ?? 0,
      ),
    );
  }
}
