import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../l10n/money.dart';
import '../models/menu_item.dart';
import '../models/merchant.dart';
import '../models/money.dart';
import '../providers/providers.dart';
import '../theme/colors.dart';
import '../theme/dimens.dart';

/// Editing a merchant's menu.
///
/// The same widget serves MerchantApp and AdminApp. That is not a convenience: the owner
/// enters every menu personally during onboarding and merchants edit theirs afterwards,
/// so two implementations would be two sets of validation rules over the same data, and
/// they would drift. The only thing that differs is where [merchantId] comes from.
class MenuEditor extends ConsumerWidget {
  const MenuEditor({super.key, required this.merchantId});

  final String merchantId;

  static const nameFieldKey = Key('menu.name');
  static const priceFieldKey = Key('menu.price');
  static const descriptionFieldKey = Key('menu.description');
  static const availableSwitchKey = Key('menu.available');
  static const saveItemKey = Key('menu.saveItem');

  static Key addItemKey(String categoryId) => Key('menu.addItem.$categoryId');
  static Key unavailableKey(String itemId) => Key('menu.unavailable.$itemId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = LuqmaStrings.of(context);
    final categories =
        ref.watch(menuCategoriesProvider(merchantId)).value ?? const <MenuCategory>[];
    final items = ref.watch(menuItemsProvider(merchantId)).value ?? const <MenuItem>[];

    if (categories.isEmpty) {
      return Center(child: Text(strings.menuNoCategories));
    }

    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        for (final category in categories)
          _CategorySection(
            merchantId: merchantId,
            category: category,
            items: items.where((i) => i.categoryId == category.id).toList(),
          ),
      ],
    );
  }
}

class _CategorySection extends ConsumerWidget {
  const _CategorySection({
    required this.merchantId,
    required this.category,
    required this.items,
  });

  final String merchantId;
  final MenuCategory category;
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
              TextButton(
                key: MenuEditor.addItemKey(category.id),
                onPressed: () => _editItem(context, ref, merchantId, null, category.id),
                child: Text(strings.menuAddItem),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          for (final item in items)
            _ItemRow(
              item: item,
              onTap: () => _editItem(context, ref, merchantId, item, category.id),
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap});

  final MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return InkWell(
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
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: theme.textTheme.titleMedium),
                  // An unavailable item stays on the merchant's menu and leaves the
                  // customer's, so which is which has to read at a glance.
                  if (!item.isAvailable)
                    Text(
                      strings.menuUnavailable,
                      key: MenuEditor.unavailableKey(item.id),
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
                    ),
                ],
              ),
            ),
            Text(
              strings.price(item.price),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.price,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _editItem(
  BuildContext context,
  WidgetRef ref,
  String merchantId,
  MenuItem? existing,
  String categoryId,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _ItemSheet(
      merchantId: merchantId,
      categoryId: categoryId,
      existing: existing,
      onSave: (item) async {
        await ref.read(menuRepositoryProvider).saveItem(item);
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      },
    ),
  );
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({
    required this.merchantId,
    required this.categoryId,
    required this.existing,
    required this.onSave,
  });

  final String merchantId;
  final String categoryId;
  final MenuItem? existing;
  final Future<void> Function(MenuItem) onSave;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  final _formKey = GlobalKey<FormState>();

  late String _name = widget.existing?.name ?? '';
  late String _price =
      widget.existing == null ? '' : Money.format(widget.existing!.price);
  late String? _description = widget.existing?.description;
  late bool _available = widget.existing?.isAvailable ?? true;

  @override
  Widget build(BuildContext context) {
    final strings = LuqmaStrings.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: Space.gutter,
        right: Space.gutter,
        top: Space.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: MenuEditor.nameFieldKey,
              initialValue: _name,
              decoration: InputDecoration(labelText: strings.menuItemName),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? strings.menuNameRequired : null,
              onSaved: (v) => _name = v!.trim(),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              key: MenuEditor.priceFieldKey,
              initialValue: _price,
              decoration: InputDecoration(labelText: strings.menuItemPrice),
              keyboardType: TextInputType.number,
              // Refused rather than rounded: a price the app cannot read exactly would
              // otherwise become a menu that says one figure while the courier collects
              // another.
              validator: (v) =>
                  Money.parse(v ?? '') == null ? strings.menuPriceInvalid : null,
              onSaved: (v) => _price = v!,
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              key: MenuEditor.descriptionFieldKey,
              initialValue: _description,
              decoration: InputDecoration(labelText: strings.menuItemDescription),
              maxLines: 2,
              onSaved: (v) => _description = v,
            ),
            const SizedBox(height: Space.md),
            SwitchListTile(
              key: MenuEditor.availableSwitchKey,
              value: _available,
              title: Text(strings.menuItemAvailable),
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _available = v),
            ),
            const SizedBox(height: Space.lg),
            FilledButton(
              key: MenuEditor.saveItemKey,
              onPressed: _submit,
              child: Text(strings.menuSaveItem),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    widget.onSave(
      MenuItem(
        // Empty means create. Reusing the existing id is what keeps an edit from
        // producing a second copy of the same dish.
        id: widget.existing?.id ?? '',
        merchantId: widget.merchantId,
        categoryId: widget.categoryId,
        name: _name,
        price: Money.parse(_price)!,
        description: _description,
        mediaId: widget.existing?.mediaId,
        isAvailable: _available,
        options: widget.existing?.options ?? const [],
        sortOrder: widget.existing?.sortOrder ?? 0,
      ),
    );
  }
}
