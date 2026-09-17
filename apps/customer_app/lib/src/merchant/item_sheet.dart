import 'package:flutter/material.dart';
import 'package:luqma_core/luqma_core.dart';

import 'merchant_screen.dart';

/// What the customer settled on in the sheet.
@immutable
class ItemChoice {
  const ItemChoice({this.options = const [], this.note, this.quantity = 1});

  final List<MenuOption> options;
  final String? note;
  final int quantity;
}

/// One dish, opened.
///
/// Everything that moves the price is on this one sheet — the picture, the extras, how
/// many — and the button carries the running total, so the last number read before
/// committing is the number that lands in the basket. There is no step between choosing
/// and adding.
///
/// It is only ever reached from a menu row that is enabled, so there is no sold-out or
/// shut-shop branch here: `_LoadedState._entry` makes an unavailable row inert and the
/// sheet never opens for one.
class ItemSheet extends StatefulWidget {
  const ItemSheet({super.key, required this.item});

  final MenuItem item;

  /// The dish photograph's slot at the head of the sheet. A picture height measured
  /// against this surface — not a [Space] step — held as a named constant the way
  /// `MealCard.imageHeight` holds its own.
  static const imageHeight = 168.0;

  @override
  State<ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<ItemSheet> {
  final _chosen = <String>{};
  final _note = TextEditingController();
  int _quantity = 1;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  List<MenuOption> get _options =>
      widget.item.options.where((o) => _chosen.contains(o.id)).toList();

  int get _total =>
      (widget.item.price + _options.fold<int>(0, (sum, o) => sum + o.price)) *
      _quantity;

  ItemChoice get _choice {
    final note = _note.text.trim();
    return ItemChoice(
      options: _options,
      // Whitespace is not a note; sending it would put a blank line on the ticket.
      note: note.isEmpty ? null : note,
      quantity: _quantity,
    );
  }

  void _toggle(String id) => setState(() {
        // `remove` reports whether it was there; one lookup does both halves.
        if (!_chosen.remove(id)) _chosen.add(id);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final item = widget.item;

    return Padding(
      key: MerchantScreen.itemSheetKey,
      // Lifts the sheet clear of the keyboard while the note has focus, so the button
      // the customer is aiming for is never underneath it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Grabber(),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: Space.lg),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      Space.sm,
                      Space.gutter,
                      0,
                    ),
                    child: ClipRRect(
                      borderRadius: Radii.imageAll,
                      child: SizedBox(
                        height: ItemSheet.imageHeight,
                        width: double.infinity,
                        // The dish is the thing being sold, and on launch day there is no
                        // photograph of it — [LuqmaImage] draws the tinted monogram from
                        // the name rather than a grey box. Its default `contain` is right
                        // here for the same reason the shop cover keeps it: a crop of the
                        // merchant's own photo throws away the part they framed.
                        child: LuqmaImage(
                          key: MerchantScreen.itemImageKey,
                          url: item.imageUrl,
                          name: item.name,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        const SizedBox(width: Space.md),
                        Text(
                          strings.price(item.price),
                          style: LuqmaType.price.copyWith(color: colors.price),
                        ),
                      ],
                    ),
                  ),
                  if (item.description != null &&
                      item.description!.isNotEmpty) ...[
                    const SizedBox(height: Space.xs),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: Space.gutter),
                      child: Text(
                        item.description!,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ],
                  // No extras, no heading: an «إضافات» title over nothing is a section
                  // that says nothing, so the whole block goes away.
                  if (item.options.isNotEmpty) ...[
                    const SizedBox(height: Space.lg),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: Space.gutter),
                      child: Text(
                        'إضافات',
                        key: MerchantScreen.itemOptionsHeadingKey,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: Space.xs),
                    for (final option in item.options)
                      _OptionRow(
                        option: option,
                        checked: _chosen.contains(option.id),
                        onTap: () => _toggle(option.id),
                        // A free extra shows no surcharge rather than «مجاناً» on every
                        // line, which reads as an offer the merchant never made.
                        priceLabel: option.price == 0
                            ? null
                            : '+${strings.price(option.price)}',
                      ),
                  ],
                  const SizedBox(height: Space.lg),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: Space.gutter),
                    child: TextField(
                      key: MerchantScreen.itemNoteKey,
                      controller: _note,
                      maxLines: 2,
                      // A cap, so a paragraph does not land on a kitchen ticket; no
                      // counter, because the artboard's field is a plain box and a
                      // short optional note does not need a running count.
                      maxLength: 120,
                      decoration: const InputDecoration(
                        hintText: 'ملاحظة للمطبخ… (اختياري)',
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _Footer(
              quantity: _quantity,
              total: _total,
              // The floor lives here, not only in whether [_Footer] is handed a
              // callback. That guard is computed at build time, so two decrements
              // landing before the rebuild — two fingers, an assistive tap plus a
              // finger — both see `quantity > 1` and take it to zero, and a basket line
              // of zero is a dish nobody ordered and nobody is charged for.
              onLess: () => setState(() {
                if (_quantity > 1) _quantity--;
              }),
              onMore: () => setState(() => _quantity++),
              onAdd: () => Navigator.of(context).pop(_choice),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  /// The drag handle from the artboard. Its own dimensions, measured, not a [Space] step.
  static const _width = 40.0;
  static const _height = 4.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Container(
        width: _width,
        height: _height,
        decoration: BoxDecoration(
          // A handle is decoration, so it takes the decorative line rather than the
          // interactive one — the artboard has it on `hairline`.
          color: Theme.of(context).luqma.hairline,
          borderRadius: Radii.pillAll,
        ),
      ),
    );
  }
}

/// One extra: its name on the right, its surcharge and a box on the left.
///
/// The artboard draws the box at 22px, which is under half the 48 a finger needs — so
/// the whole row is the tap target and the box is only what the choice looks like. The
/// box fills rather than snapping when it is chosen.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.checked,
    required this.onTap,
    required this.priceLabel,
  });

  final MenuOption option;
  final bool checked;
  final VoidCallback onTap;
  final String? priceLabel;

  /// The checkbox glyph from the artboard. A control smaller than [Sizes.minTarget] —
  /// the row around it carries the touch target — so these are named constants here
  /// rather than tokens.
  static const _boxSize = 22.0;
  static const _boxRadius = 6.0;
  static const _boxStroke = 1.5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return LuqmaPressable(
      key: MerchantScreen.itemOptionKey(option.id),
      onTap: onTap,
      selected: checked,
      child: Container(
        constraints: const BoxConstraints(minHeight: Sizes.minTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.gutter,
          vertical: Space.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(option.name, style: theme.textTheme.bodyLarge),
            ),
            if (priceLabel != null) ...[
              const SizedBox(width: Space.sm),
              Text(
                priceLabel!,
                style: LuqmaType.priceSmall.copyWith(color: colors.price),
              ),
            ],
            const SizedBox(width: Space.md),
            _CheckBox(checked: checked),
          ],
        ),
      ),
    );
  }
}

/// Outlined when unchosen; a filled burgundy square with a white tick when chosen,
/// filling over [Motion.quick] rather than switching in one frame.
class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return AnimatedContainer(
      duration: Motion.of(context, Motion.quick),
      curve: Motion.enter,
      width: _OptionRow._boxSize,
      height: _OptionRow._boxSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: checked ? colors.brand : colors.card,
        borderRadius:
            const BorderRadius.all(Radius.circular(_OptionRow._boxRadius)),
        border: Border.all(
          color: checked ? colors.brand : colors.border,
          width: _OptionRow._boxStroke,
        ),
      ),
      child: AnimatedScale(
        scale: checked ? 1.0 : 0.0,
        duration: Motion.of(context, Motion.quick),
        curve: Motion.enter,
        child: Icon(
          Icons.check_rounded,
          size: _OptionRow._boxSize - 8,
          color: colors.onBrand,
        ),
      ),
    );
  }
}

/// The stepper and the add button, on one line and the same height.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.quantity,
    required this.total,
    required this.onLess,
    required this.onMore,
    required this.onAdd,
  });

  final int quantity;
  final int total;
  final VoidCallback onLess;
  final VoidCallback onMore;
  final VoidCallback onAdd;

  /// Both controls stand a shade over the theme's 48 minimum, as the merchant screen's
  /// basket bar does. One value, so the two cannot drift apart.
  static const _controlHeight = 50.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Space.md,
      ),
      child: Row(
        children: [
          _Stepper(
            height: _controlHeight,
            quantity: quantity,
            // The floor is one. Taking the last one out is removal, and removal belongs
            // in the basket where the line can be seen — not on a sheet still offering
            // to add it. A null callback greys the control and drops it from the screen
            // reader's list of actions, so it looks as inert as it is.
            onLess: quantity > 1 ? onLess : null,
            onMore: onMore,
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: FilledButton(
              key: MerchantScreen.addToCartKey,
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(_controlHeight),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Flexible(
                    child: Text('أضف للسلة', overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: Space.sm),
                  _Total(total: total),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The amount on the add button, which moves when it changes and is never two amounts.
///
/// This was an [AnimatedSwitcher] cross-fading the old total into the new one, which is
/// the ordinary way to animate a changing label and the wrong way to animate a **price**:
/// for the length of the fade both numbers are on the button at once, one of them wrong,
/// and the button stays enabled throughout. Somebody who ticks an extra, reads 60 while
/// 75 is fading up under it, and taps, is charged the number they did not read. It is a
/// sixth of a second, and it is the only moment on this sheet where the screen and the
/// basket disagree — so it should not exist at all.
///
/// So the text is never animated: it is rebuilt at the new amount immediately, and what
/// moves is its scale. Exactly one price is on screen in every frame, and it still
/// answers the tap.
class _Total extends StatelessWidget {
  const _Total({required this.total});

  final int total;

  /// Where the pulse starts. Small enough to read as the number reacting rather than as
  /// it arriving from somewhere.
  static const _from = 0.88;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    final text = Text(
      strings.price(total),
      style: LuqmaType.button.copyWith(color: colors.onBrand),
    );

    // Returned before the builder rather than through a zero duration. A tween with no
    // duration still paints its `begin` for the first frame, and more to the point an
    // animation already running when the setting changes keeps the duration it was
    // created with — so the switcher this replaced went on fading for 160ms after
    // somebody turned motion off. Nothing to collapse is the only reliable collapse.
    if (MediaQuery.disableAnimationsOf(context)) return text;

    return TweenAnimationBuilder<double>(
      // Restarts the pulse whenever the amount changes; without it the tween has already
      // finished and the new number simply appears.
      key: ValueKey(total),
      tween: Tween(begin: _from, end: 1),
      duration: Motion.quick,
      curve: Motion.enter,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: text,
    );
  }
}

/// Minus, the number, plus, inside one outlined pill-cornered box.
///
/// It reports the step rather than the new total: two quick taps landing in the same
/// frame would both compute from the same stale [quantity] and one would be swallowed.
/// The owner adds to whatever it currently holds, so every tap counts. A null [onLess]
/// is the floor at one — see [_Footer].
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.height,
    required this.quantity,
    required this.onLess,
    required this.onMore,
  });

  final double height;
  final int quantity;
  final VoidCallback? onLess;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: Radii.fieldAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: MerchantScreen.itemLessKey,
            tooltip: 'واحد أقل',
            onPressed: onLess,
            icon: const Icon(Icons.remove_rounded, size: Sizes.iconSm),
            constraints: const BoxConstraints(
              minWidth: Sizes.minTarget,
              minHeight: Sizes.minTarget,
            ),
          ),
          Text(
            '$quantity',
            key: MerchantScreen.itemQuantityKey,
            style: LuqmaType.bodyStrong.copyWith(color: colors.textPrimary),
          ),
          IconButton(
            key: MerchantScreen.itemMoreKey,
            tooltip: 'واحد زيادة',
            onPressed: onMore,
            icon: const Icon(Icons.add_rounded, size: Sizes.iconSm),
            constraints: const BoxConstraints(
              minWidth: Sizes.minTarget,
              minHeight: Sizes.minTarget,
            ),
          ),
        ],
      ),
    );
  }
}
