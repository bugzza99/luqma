import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../cart/cart.dart';
import '../cart/cart_controller.dart';
import '../cart/open_cart.dart';
import 'item_sheet.dart';

/// One merchant: who they are, what they cook, and what is in the basket so far.
class MerchantScreen extends ConsumerWidget {
  const MerchantScreen({super.key, required this.merchantId});

  final String merchantId;

  static const cartBarKey = Key('merchant.cartBar');
  static const closedBannerKey = Key('merchant.closed');
  static const itemSheetKey = Key('merchant.itemSheet');
  static const addToCartKey = Key('merchant.addToCart');
  static const replaceCartKey = Key('merchant.replaceCart');
  static const confirmReplaceKey = Key('merchant.confirmReplace');
  static const cancelReplaceKey = Key('merchant.cancelReplace');

  static Key soldOutKey(String itemId) => Key('merchant.soldOut.$itemId');
  static Key itemKey(String itemId) => Key('merchant.item.$itemId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchant = ref.watch(merchantProvider(merchantId));
    final items = ref.watch(menuItemsProvider(merchantId)).value ?? const <MenuItem>[];
    final categories =
        ref.watch(menuCategoriesProvider(merchantId)).value ?? const <MenuCategory>[];
    final cart = ref.watch(cartProvider);

    return switch (merchant) {
      // An error arm comes first, and matches on `hasError` rather than on the
      // `AsyncError` type: a stream that fails before it has ever emitted stays
      // `AsyncLoading` with the error hanging off it, so a type match never fires
      // and the screen spins for ever on a dropped connection.
      AsyncValue(hasError: true, :final error?) => Scaffold(
          appBar: AppBar(),
          body: LuqmaErrorView(failure: error, onRetry: () => ref.invalidate(merchantProvider(merchantId))),
        ),
      AsyncValue(hasValue: true, :final value?) => _Loaded(
          merchant: value,
          categories: categories,
          items: items,
          cart: cart,
        ),
          _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
};
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({
    required this.merchant,
    required this.categories,
    required this.items,
    required this.cart,
  });

  final Merchant merchant;
  final List<MenuCategory> categories;
  final List<MenuItem> items;
  final Cart cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = merchant.acceptsOrdersAt(DateTime.now());
    final strings = LuqmaStrings.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(merchant.name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xxxl),
        children: [
          if (!open) const _ClosedBanner(),
          _Summary(merchant: merchant),
          for (final group in _group(categories, items)) ...[
            if (group.name != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.lg,
                  Space.gutter,
                  Space.sm,
                ),
                child: Text(
                  group.name!,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              )
            else
              const SizedBox(height: Space.lg),
            for (final item in group.items)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  0,
                  Space.gutter,
                  Space.sm,
                ),
                child: _ItemRow(
                  item: item,
                  // A closed kitchen still shows its menu at full strength — that is how
                  // somebody decides to come back later — but nothing can be put in a
                  // basket from it. Only sold-out dishes are dimmed.
                  enabled: open && item.isAvailable,
                  onTap: () => _openItem(context, ref, item),
                ),
              ),
          ],
        ],
      ),
      bottomNavigationBar: cart.isNotEmpty
          ? _CartBar(
              cart: cart,
              strings: strings,
              onOpenCart: () => openCart(context),
            )
          : null,
    );
  }

  /// Items under their category headings, then whatever is left over under none.
  ///
  /// The leftovers matter: a merchant who renames or deletes a category leaves items
  /// pointing at an id nothing matches, and grouping strictly by category would drop
  /// those dishes off the customer's menu without a word to anybody.
  static List<({String? name, List<MenuItem> items})> _group(
    List<MenuCategory> categories,
    List<MenuItem> items,
  ) {
    final known = {for (final c in categories) c.id};
    return [
      for (final category in categories)
        if (items.any((i) => i.categoryId == category.id))
          (
            name: category.name,
            items: items.where((i) => i.categoryId == category.id).toList(),
          ),
      if (items.any((i) => !known.contains(i.categoryId)))
        (
          name: null,
          items: items.where((i) => !known.contains(i.categoryId)).toList(),
        ),
    ];
  }

  Future<void> _openItem(BuildContext context, WidgetRef ref, MenuItem item) async {
    final choice = await showModalBottomSheet<ItemChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ItemSheet(item: item),
    );
    if (choice == null || !context.mounted) return;

    final controller = ref.read(cartProvider.notifier);

    if (controller.canAdd(item)) {
      controller.add(
        item,
        options: choice.options,
        note: choice.note,
        quantity: choice.quantity,
      );
      return;
    }

    // The basket belongs to another kitchen. Never resolved silently: it holds somebody's
    // decisions, and losing it without being asked is worse than the question.
    final replace = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: MerchantScreen.replaceCartKey,
        title: const Text('تبدأ سلة جديدة؟'),
        content: const Text(
          'سلتك دلوقتي من مطعم تاني. الطلب بيروح لمطبخ واحد، '
          'فلو كملت هنا السلة القديمة هتتمسح.',
        ),
        actions: [
          TextButton(
            key: MerchantScreen.cancelReplaceKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('سيبها زي ما هي'),
          ),
          FilledButton(
            key: MerchantScreen.confirmReplaceKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ابدأ سلة جديدة'),
          ),
        ],
      ),
    );

    if (replace ?? false) {
      controller.replaceWith(
        item,
        options: choice.options,
        note: choice.note,
        quantity: choice.quantity,
      );
    }
  }
}

class _ClosedBanner extends StatelessWidget {
  const _ClosedBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    return Container(
      key: MerchantScreen.closedBannerKey,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.gutter,
        vertical: Space.md,
      ),
      color: colors.surface,
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, size: Sizes.iconSm, color: colors.danger),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text(
              '${LuqmaStrings.of(context).merchantClosed} — تقدر تتفرج على المنيو.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.merchant});

  final Merchant merchant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final config = ref.watch(appConfigProvider);

    return Container(
      color: colors.card,
      padding: const EdgeInsets.all(Space.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(merchant.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.xs,
            children: [
              if (merchant.ratingCount >= config.minRatingsToShow)
                _Fact(
                  label: '${merchant.ratingAvg.toStringAsFixed(1)} ★',
                  emphasise: true,
                ),
              if (merchant.minOrder > 0)
                _Fact(label: 'أقل طلب ${strings.price(merchant.minOrder)}'),
              _Fact(
                label: merchant.type == MerchantType.homeKitchen
                    ? 'أكل بيتي'
                    : 'مطعم',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, this.emphasise = false});

  final String label;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: emphasise ? theme.luqma.price : theme.luqma.textSecondary,
        fontWeight: emphasise ? FontWeight.w700 : FontWeight.w400,
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.enabled,
    required this.onTap,
  });

  final MenuItem item;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Opacity(
      opacity: item.isAvailable ? 1 : 0.6,
      child: InkWell(
        key: MerchantScreen.itemKey(item.id),
        onTap: enabled ? onTap : null,
        borderRadius: Radii.cardAll,
        child: Container(
          padding: const EdgeInsets.all(Space.md - 1),
          constraints: const BoxConstraints(minHeight: Sizes.minTarget),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: Radii.cardAll,
            border: Border.all(color: colors.hairline),
            boxShadow: Elevations.card,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: theme.textTheme.titleMedium),
                    if (item.description != null && item.description!.isNotEmpty) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        item.description!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: Space.xs),
                    if (item.isAvailable)
                      Text(
                        strings.price(item.price),
                        style: LuqmaType.price.copyWith(color: colors.price),
                      )
                    else
                      Text(
                        'خلص النهارده',
                        key: MerchantScreen.soldOutKey(item.id),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: Radii.imageAll,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.cart,
    required this.strings,
    required this.onOpenCart,
  });

  final Cart cart;
  final LuqmaStrings strings;
  final VoidCallback onOpenCart;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return SafeArea(
      key: MerchantScreen.cartBarKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: FilledButton(
          onPressed: onOpenCart,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          // Both halves flex. On a 400px phone — which is most of them — "شوف السلة"
          // beside "٣ أصناف · ١٥٠ ج" is wider than the button, and a Row of two natural
          // widths overflows rather than shrinking. The count is what gives way first:
          // the label is the instruction, and the total is already on the basket screen.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text('شوف السلة', overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: Space.sm),
              Flexible(
                child: Text(
                  '${strings.orderCount(cart.itemCount)} · '
                  '${strings.price(cart.subtotal)}',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: LuqmaType.button.copyWith(color: colors.onBrand),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

