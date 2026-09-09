import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../cart/cart.dart';
import '../cart/cart_controller.dart';
import '../cart/open_cart.dart';
import 'item_sheet.dart';
import 'menu_filter.dart';
import 'merchant_hours.dart';

/// One merchant: who they are, what they cook, and what is in the basket so far.
class MerchantScreen extends ConsumerWidget {
  const MerchantScreen({super.key, required this.merchantId, this.openItemId});

  final String merchantId;

  /// A dish to present the moment the menu arrives.
  ///
  /// Tapping a dish on the home used to land on the shop's page with the dish nowhere in
  /// sight — the customer picked «سمك مشوي» and got a menu to find it in again. It opens
  /// here rather than as a sheet of its own because adding anything needs the shop:
  /// whether it is open, whether the dish is still available, and whose basket this is.
  /// Dismissing the sheet leaves them on the shop's page, which is where somebody who
  /// tapped a dish from that shop wants to be.
  final String? openItemId;

  static const cartBarKey = Key('merchant.cartBar');
  static const closedBannerKey = Key('merchant.closed');
  static const itemSheetKey = Key('merchant.itemSheet');
  static const addToCartKey = Key('merchant.addToCart');
  static const replaceCartKey = Key('merchant.replaceCart');
  static const confirmReplaceKey = Key('merchant.confirmReplace');
  static const cancelReplaceKey = Key('merchant.cancelReplace');

  /// The dish photograph at the head of the item sheet.
  static const itemImageKey = Key('merchant.itemImage');

  /// The «إضافات» heading, present only when the dish has extras.
  static const itemOptionsHeadingKey = Key('merchant.itemOptionsHeading');

  /// The kitchen-note field on the item sheet.
  static const itemNoteKey = Key('merchant.itemNote');

  /// The item sheet's quantity stepper: the two controls and the number between them.
  static const itemLessKey = Key('merchant.itemLess');
  static const itemMoreKey = Key('merchant.itemMore');
  static const itemQuantityKey = Key('merchant.itemQuantity');

  /// One extra's row on the item sheet — the whole row, which is the tap target.
  static Key itemOptionKey(String optionId) => Key('merchant.itemOption.$optionId');

  /// The cover image, so a test can read the address it was handed rather than guess
  /// among the several [LuqmaImage]s on the screen.
  static const coverKey = Key('merchant.cover');

  /// The «أكل بيتي» badge — present only for a home kitchen.
  static const badgeKey = Key('merchant.badge');

  /// The rating figure, shown once enough people have left one.
  static const ratingKey = Key('merchant.rating');

  /// What stands where the rating goes before the threshold is met.
  static const noRatingKey = Key('merchant.rating.none');

  /// The open / closed / busy line in the info block.
  static const statusKey = Key('merchant.status');

  /// The category filter row, absent when the menu has fewer than two sections.
  static const categoryChipsKey = Key('merchant.categoryChips');

  /// The "الكل" chip that clears the filter.
  static const categoryAllChipKey = Key('merchant.categoryChip.all');

  /// The always-present shell the basket bar animates inside. Its height is zero while
  /// the basket is empty and grows as the bar arrives.
  static const cartDockKey = Key('merchant.cartDock');

  static Key soldOutKey(String itemId) => Key('merchant.soldOut.$itemId');
  static Key itemKey(String itemId) => Key('merchant.item.$itemId');
  static Key categoryChipKey(String categoryId) =>
      Key('merchant.categoryChip.$categoryId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchant = ref.watch(merchantProvider(merchantId));
    final itemsAsync = ref.watch(menuItemsProvider(merchantId));
    final categoriesAsync = ref.watch(menuCategoriesProvider(merchantId));
    final items = itemsAsync.value ?? const <MenuItem>[];
    final categories = categoriesAsync.value ?? const <MenuCategory>[];

    // The same rule the merchant stream below is given, and for the same reason. These
    // two were collapsed with `.value ?? const []`, so a dropped connection drew the
    // shop with an empty menu: a kitchen that appears to cook nothing, with no error and
    // no way to retry. An empty menu and an unreachable one look identical to a customer
    // and are not remotely the same thing.
    final menuError = itemsAsync.error ?? categoriesAsync.error;
    if (menuError != null) {
      return Scaffold(
        appBar: AppBar(),
        body: LuqmaErrorView(
          failure: menuError,
          onRetry: () {
            ref.invalidate(menuItemsProvider(merchantId));
            ref.invalidate(menuCategoriesProvider(merchantId));
          },
        ),
      );
    }

    return LuqmaAsyncView(
      value: merchant,
      onRetry: () => ref.invalidate(merchantProvider(merchantId)),
      loading: const Scaffold(body: Center(child: CircularProgressIndicator())),
      builder: (context, value) =>
          _Loaded(merchant: value, categories: categories, items: items,
              openItemId: openItemId),
    );
  }
}

class _Loaded extends ConsumerStatefulWidget {
  const _Loaded({
    required this.merchant,
    required this.categories,
    required this.items,
    this.openItemId,
  });

  final Merchant merchant;
  final List<MenuCategory> categories;
  final List<MenuItem> items;
  final String? openItemId;

  @override
  ConsumerState<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends ConsumerState<_Loaded> {
  /// Presented once, on the first build that has the menu.
  ///
  /// `_Loaded` is built from a stream, so it rebuilds whenever the shop or the menu
  /// changes — without this the sheet would be pushed again on every one of them, and a
  /// customer editing their choice would watch a second copy open on top of it.
  bool _presented = false;

  @override
  void initState() {
    super.initState();
    final wanted = widget.openItemId;
    if (wanted == null) return;

    // After the first frame: this runs during `initState`, and pushing a route while the
    // tree is still being built is the thing Flutter asserts about.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _presented) return;
      final item = widget.items.where((i) => i.id == wanted).firstOrNull;
      // Gone from the menu since the home last loaded it. The shop's page is still the
      // right place to have landed, so nothing is said and nothing opens.
      if (item == null) return;
      _presented = true;
      _openItem(item);
    });
  }

  /// Which category the chips have narrowed the menu to, or null for the whole menu.
  /// Screen-local and ephemeral — it does not need to outlive the route, so it is state
  /// here rather than a provider.
  String? _category;

  @override
  Widget build(BuildContext context) {
    final merchant = widget.merchant;
    // From the shared clock, so a test can move it rather than wait for an evening.
    final now = ref.watch(clockProvider)();
    final state = merchantOpenState(merchant, now);
    final closingMinute = closingMinuteAt(merchant, now);
    final cart = ref.watch(cartProvider);

    final groups = _group(widget.categories, widget.items);
    final named = [
      for (final group in groups)
        if (group.name != null) group,
    ];
    final filter = menuFilter(
      namedCategoryIds: [for (final group in named) group.id],
      chosen: _category,
    );
    final showChips = filter.showChips;
    final selected = filter.selected;

    final canOrder = state == MerchantOpenState.open;

    return Scaffold(
      appBar: AppBar(title: Text(merchant.name)),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Cover(merchant: merchant),
          if (state != MerchantOpenState.open) _StatusBanner(state: state),
          _Summary(
            merchant: merchant,
            state: state,
            closingMinute: closingMinute,
          ),
          if (showChips)
            _CategoryChips(
              groups: named,
              selected: selected,
              onSelect: (id) => setState(() => _category = id),
            ),
          ..._menu(groups, selected: selected, canOrder: canOrder),
          const SizedBox(height: Space.xxxl),
        ],
      ),
      bottomNavigationBar: _CartDock(
        cart: cart,
        onOpenCart: () => openCart(context),
      ),
    );
  }

  /// The menu rows. Filtered to one section and heading-less when a chip is pressed;
  /// grouped under headings otherwise.
  List<Widget> _menu(
    List<({String? id, String? name, List<MenuItem> items})> groups, {
    required String? selected,
    required bool canOrder,
  }) {
    if (selected != null) {
      final picked =
          widget.items.where((item) => item.categoryId == selected).toList();
      return [
        for (var i = 0; i < picked.length; i++)
          _entry(picked[i], index: i, scope: selected, canOrder: canOrder),
      ];
    }

    final out = <Widget>[];
    var index = 0;
    for (final group in groups) {
      if (group.name != null) {
        out.add(
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
          ),
        );
      } else {
        out.add(const SizedBox(height: Space.lg));
      }
      for (final item in group.items) {
        out.add(_entry(item, index: index++, scope: null, canOrder: canOrder));
      }
    }
    return out;
  }

  Widget _entry(
    MenuItem item, {
    required int index,
    required String? scope,
    required bool canOrder,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.sm),
      child: LuqmaEntrance(
        // Scoped by the current filter so switching sections restages the new set,
        // while a row that stays put across a rebuild keeps its place without flicker.
        key: ValueKey('merchant.entrance.${scope ?? 'all'}.${item.id}'),
        index: index,
        child: _ItemRow(
          item: item,
          // A closed or busy kitchen still shows its menu at full strength — that is how
          // somebody decides to come back later — but nothing can be put in a basket
          // from it. Only sold-out dishes are dimmed.
          enabled: canOrder && item.isAvailable,
          onTap: () => _openItem(item),
        ),
      ),
    );
  }

  /// Items under their category headings, then whatever is left over under none.
  ///
  /// The leftovers matter: a merchant who renames or deletes a category leaves items
  /// pointing at an id nothing matches, and grouping strictly by category would drop
  /// those dishes off the customer's menu without a word to anybody.
  static List<({String? id, String? name, List<MenuItem> items})> _group(
    List<MenuCategory> categories,
    List<MenuItem> items,
  ) {
    final known = {for (final c in categories) c.id};
    return [
      for (final category in categories)
        if (items.any((i) => i.categoryId == category.id))
          (
            id: category.id,
            name: category.name,
            items: items.where((i) => i.categoryId == category.id).toList(),
          ),
      if (items.any((i) => !known.contains(i.categoryId)))
        (
          id: null,
          name: null,
          items: items.where((i) => !known.contains(i.categoryId)).toList(),
        ),
    ];
  }

  Future<void> _openItem(MenuItem item) async {
    final choice = await showModalBottomSheet<ItemChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ItemSheet(item: item),
    );
    if (choice == null || !mounted) return;

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

/// The shop's photograph, or the tint that stands in until one is shot.
///
/// This is the largest empty space on the screen on launch day, so it has to read as a
/// deliberate frame rather than something that failed to load — which is exactly what
/// [LuqmaImage]'s monogram fallback is for.
class _Cover extends StatelessWidget {
  const _Cover({required this.merchant});

  final Merchant merchant;

  /// The artboard's cover height. Not a [Space] step — a picture height measured against
  /// this screen, held here the way [Sizes] holds the other measured ones.
  static const _height = 168.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      width: double.infinity,
      child: LuqmaImage(
        key: MerchantScreen.coverKey,
        url: merchant.coverUrl,
        name: merchant.name,
      ),
    );
  }
}

/// The strip below the cover on a shop that is not taking orders. Keeps the reassurance
/// the old banner carried — the menu is still there to read — and names *which* kind of
/// "not now" it is.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.state});

  final MerchantOpenState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final lead = state == MerchantOpenState.paused
        ? strings.merchantBusy
        : strings.merchantClosed;

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
              '$lead — تقدر تتفرج على المنيو.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Who the shop is, how good it is, when it closes, and the terms of ordering from it.
class _Summary extends ConsumerWidget {
  const _Summary({
    required this.merchant,
    required this.state,
    required this.closingMinute,
  });

  final Merchant merchant;
  final MerchantOpenState state;
  final int? closingMinute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final config = ref.watch(appConfigProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    merchant.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                // The «موثّق» slot in the artboard has nothing behind it — there is no
                // verified concept in this product. This says the true thing instead:
                // that the customer is looking at a home kitchen, which is the whole
                // point of the marketplace. Dark ink on the orange, never white.
                if (merchant.type == MerchantType.homeKitchen) ...[
                  const SizedBox(width: Space.sm),
                  const _Badge(),
                ],
              ],
            ),
            const SizedBox(height: Space.sm),
            // Wrap, not Row: every line here is text that scales, and a fixed row of it
            // overflows the moment somebody turns their type size up.
            Wrap(
              spacing: Space.lg,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (merchant.ratingCount >= config.minRatingsToShow)
                  _Rating(merchant: merchant)
                else
                  // What the home's merchant row shows in the same case: a word, not an
                  // empty gap that reads as a rating which failed to load.
                  Text(
                    'جديد',
                    key: MerchantScreen.noRatingKey,
                    style: LuqmaType.caption
                        .copyWith(color: colors.textSecondary),
                  ),
                _StatusText(state: state, closingMinute: closingMinute),
              ],
            ),
            const SizedBox(height: Space.xs),
            Wrap(
              spacing: Space.lg,
              runSpacing: Space.xs,
              children: [
                _DeliveryFact(merchant: merchant),
                if (merchant.minOrder > 0)
                  _Fact(
                    label: 'أقل طلب ',
                    value: strings.price(merchant.minOrder),
                  ),
                _Fact(label: '~${strings.minutes(merchant.prepMinutes)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The «أكل بيتي» pill.
class _Badge extends StatelessWidget {
  const _Badge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    return Container(
      key: MerchantScreen.badgeKey,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: Radii.pillAll,
      ),
      child: Text(
        'أكل بيتي',
        style: LuqmaType.caption.copyWith(
          color: colors.onAccent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The average, with how many ratings stand behind it.
class _Rating extends StatelessWidget {
  const _Rating({required this.merchant});

  final Merchant merchant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Row(
      key: MerchantScreen.ratingKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        // On white beside 14sp digits — `price`, not `accent`: orange clears contrast on
        // white only from 18sp.
        Icon(Icons.star_rounded, size: Sizes.iconSm - 4, color: colors.price),
        const SizedBox(width: Space.xs),
        Text(
          merchant.ratingAvg.toStringAsFixed(1),
          style: LuqmaType.priceSmall.copyWith(color: colors.price),
        ),
        const SizedBox(width: Space.xs),
        Text(
          '(${strings.ratingsCount(merchant.ratingCount)})',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// «مفتوح لحد ١ ص» / «مقفول دلوقتي» / «مشغول دلوقتي», derived from the hours and the pause.
class _StatusText extends StatelessWidget {
  const _StatusText({required this.state, required this.closingMinute});

  final MerchantOpenState state;
  final int? closingMinute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final (label, tone) = switch (state) {
      MerchantOpenState.open => (
          closingMinute == null
              ? 'مفتوح دلوقتي'
              : 'مفتوح لحد ${formatDayMinute(closingMinute!, strings)}',
          colors.textSecondary,
        ),
      MerchantOpenState.paused => ('مشغول دلوقتي', colors.danger),
      MerchantOpenState.closed => ('مقفول دلوقتي', colors.danger),
    };

    return Text(
      label,
      key: MerchantScreen.statusKey,
      style: theme.textTheme.bodySmall?.copyWith(color: tone),
    );
  }
}

/// What delivery costs, or that it costs nothing, or that the zone decides.
///
/// The fee value wears `price` on this screen — the merchant's own page is where the
/// terms are read, and the artboard puts the number in the accent-for-text colour. Free
/// delivery is an offer and the whole phrase carries it.
class _DeliveryFact extends ConsumerWidget {
  const _DeliveryFact({required this.merchant});

  final Merchant merchant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    // Clamped, not raw. The server applies the admin's range and so does
    // `Delivery.feeFor`; quoting the unclamped number here is how a customer is shown 5
    // and charged 10.
    final raw = merchant.deliveryFeeOverride;
    final fee = raw == null
        ? null
        : Delivery.quotedOverride(raw, ref.watch(appConfigProvider));

    if (fee == 0) {
      return Text(
        'توصيل مجاني',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: colors.price, fontWeight: FontWeight.w700),
      );
    }
    if (fee == null) {
      return const _Fact(label: 'التوصيل حسب المنطقة');
    }
    return _Fact(
      label: 'التوصيل ',
      value: strings.price(fee),
      valueColor: colors.price,
    );
  }
}

/// One fact on the info line: a grey label, optionally with a bold value after it.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, this.value, this.valueColor});

  final String label;
  final String? value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final base =
        theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary);

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: label),
          if (value != null)
            TextSpan(
              text: value,
              style: base?.copyWith(
                color: valueColor ?? colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

/// The category filter. "الكل" first, then one pill per section; the pressed one fills
/// burgundy, and pressing it again releases it — the same gesture in and out.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final List<({String? id, String? name, List<MenuItem> items})> groups;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    final chips = <Widget>[
      LuqmaChip(
        key: MerchantScreen.categoryAllChipKey,
        label: 'الكل',
        selected: selected == null,
        onTap: () => onSelect(null),
      ),
      for (final group in groups)
        LuqmaChip(
          key: MerchantScreen.categoryChipKey(group.id!),
          label: group.name!,
          selected: selected == group.id,
          onTap: () => onSelect(selected == group.id ? null : group.id),
        ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      // A horizontal scroller rather than a fixed-height row: the strip's height follows
      // the chip text, so turning the type size up widens the pills instead of clipping
      // them.
      child: SingleChildScrollView(
        key: MerchantScreen.categoryChipsKey,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter,
          vertical: Space.sm,
        ),
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: Space.sm),
              chips[i],
            ],
          ],
        ),
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

  /// The artboard's thumbnail edge. An image size measured against the row, so it is a
  /// named constant here rather than a [Space] step.
  static const _thumb = 78.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final card = Container(
      padding: const EdgeInsets.all(Space.md),
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
                if (item.description != null &&
                    item.description!.isNotEmpty) ...[
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
          ClipRRect(
            borderRadius: Radii.imageAll,
            child: SizedBox(
              width: _thumb,
              height: _thumb,
              child: LuqmaImage(url: item.imageUrl, name: item.name),
            ),
          ),
        ],
      ),
    );

    return Opacity(
      key: MerchantScreen.itemKey(item.id),
      opacity: item.isAvailable ? 1 : 0.6,
      // A sold-out or shut-shop row is inert rather than a pressable that answers a
      // finger and then does nothing.
      child: enabled ? LuqmaPressable(onTap: onTap, child: card) : card,
    );
  }
}

/// The always-present shell for the basket bar.
///
/// It stays in the tree at zero height while the basket is empty and grows the bar in
/// when the first thing lands — the bar is the shortest path to checkout, so it should
/// arrive rather than blink into place. [Motion.of] collapses the whole thing for anyone
/// who asked the OS for less motion.
class _CartDock extends StatelessWidget {
  const _CartDock({required this.cart, required this.onOpenCart});

  final Cart cart;
  final VoidCallback onOpenCart;

  @override
  Widget build(BuildContext context) {
    final strings = LuqmaStrings.of(context);

    return SizedBox(
      key: MerchantScreen.cartDockKey,
      child: AnimatedSwitcher(
        duration: Motion.of(context, Motion.sheet),
        switchInCurve: Motion.enter,
        switchOutCurve: Motion.exit,
        transitionBuilder: (child, animation) => SizeTransition(
          sizeFactor: animation,
          // Revealed from the screen's bottom edge upward. `alignment`, not the
          // deprecated `axisAlignment`: same anchor, expressed on both axes.
          alignment: Alignment.bottomCenter,
          child: FadeTransition(opacity: animation, child: child),
        ),
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.bottomCenter,
          children: [...previousChildren, ?currentChild],
        ),
        child: cart.isEmpty
            ? const SizedBox(key: ValueKey('cart.empty'), width: double.infinity)
            : _CartBar(
                key: const ValueKey('cart.present'),
                cart: cart,
                strings: strings,
                onOpenCart: onOpenCart,
              ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({
    super.key,
    required this.cart,
    required this.strings,
    required this.onOpenCart,
  });

  final Cart cart;
  final LuqmaStrings strings;
  final VoidCallback onOpenCart;

  /// The artboard's call-to-action height, a touch taller than the theme's 48 minimum.
  static const _ctaHeight = 50.0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.md,
            Space.gutter,
            Space.md,
          ),
          child: FilledButton(
            key: MerchantScreen.cartBarKey,
            onPressed: onOpenCart,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(_ctaHeight),
            ),
            // Both halves flex. On a 400px phone — which is most of them — "شوف السلة"
            // beside "صنفين · ١٥٠ ج" is wider than the button, and a Row of two natural
            // widths overflows rather than shrinking. The count is what gives way first:
            // the label is the instruction, and the total is already on the basket
            // screen.
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text('شوف السلة', overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: Space.sm),
                Flexible(
                  child: AnimatedSwitcher(
                    duration: Motion.of(context, Motion.quick),
                    // Keyed on the text so a count or total change cross-fades rather
                    // than snapping.
                    child: Text(
                      '${strings.itemCount(cart.itemCount)} · '
                      '${strings.price(cart.subtotal)}',
                      key: ValueKey('${cart.itemCount}:${cart.subtotal}'),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: LuqmaType.button.copyWith(color: colors.onBrand),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
