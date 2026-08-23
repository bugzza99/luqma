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
/// Everything that moves the price is on this one sheet — the extras, how many — and the
/// button carries the running total, so the last number read before committing is the
/// number that lands in the basket. There is no step between choosing and adding.
class ItemSheet extends StatefulWidget {
  const ItemSheet({super.key, required this.item});

  final MenuItem item;

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
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.sm,
                  Space.gutter,
                  Space.lg,
                ),
                children: [
                  Text(item.name, style: theme.textTheme.titleLarge),
                  if (item.description != null && item.description!.isNotEmpty) ...[
                    const SizedBox(height: Space.sm),
                    Text(
                      item.description!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: colors.textSecondary),
                    ),
                  ],
                  if (item.options.isNotEmpty) ...[
                    const SizedBox(height: Space.lg),
                    Text('الإضافات', style: theme.textTheme.titleMedium),
                    for (final option in item.options)
                      CheckboxListTile(
                        key: Key('itemSheet.option.${option.id}'),
                        value: _chosen.contains(option.id),
                        onChanged: (on) => setState(() {
                          if (on ?? false) {
                            _chosen.add(option.id);
                          } else {
                            _chosen.remove(option.id);
                          }
                        }),
                        title: Text(option.name),
                        // A free extra says nothing rather than "مجاناً" on every line,
                        // which reads as a promotion the merchant never made.
                        subtitle: option.price == 0
                            ? null
                            : Text('+ ${strings.price(option.price)}'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                  ],
                  const SizedBox(height: Space.lg),
                  TextField(
                    key: const Key('itemSheet.note'),
                    controller: _note,
                    maxLines: 2,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظة للمطبخ',
                      hintText: 'من غير شطة، مثلاً',
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                0,
                Space.gutter,
                Space.md,
              ),
              child: Row(
                children: [
                  _Stepper(
                    quantity: _quantity,
                    onLess: () => setState(() => _quantity--),
                    onMore: () => setState(() => _quantity++),
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: FilledButton(
                      key: MerchantScreen.addToCartKey,
                      onPressed: () => Navigator.of(context).pop(_choice),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(Sizes.minTarget),
                      ),
                      child: Text('ضيف · ${strings.price(_total)}'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).luqma.border,
          borderRadius: Radii.pillAll,
        ),
      ),
    );
  }
}

/// Minus, the number, plus.
///
/// Minus stops at one. Reaching zero here would be removal, and removal belongs in the
/// basket where the line can be seen — not on a sheet still offering to add it.
///
/// It reports the step rather than the new total: two quick taps landing in the same
/// frame would both compute from the same stale [quantity] and one of them would be
/// swallowed. The owner adds to whatever it currently holds, so every tap counts.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.onLess,
    required this.onMore,
  });

  final int quantity;
  final VoidCallback onLess;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Container(
      decoration: BoxDecoration(
        borderRadius: Radii.pillAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('itemSheet.less'),
            onPressed: quantity > 1 ? onLess : null,
            icon: const Icon(Icons.remove_rounded, size: Sizes.iconSm),
            constraints: const BoxConstraints(
              minWidth: Sizes.minTarget,
              minHeight: Sizes.minTarget,
            ),
          ),
          Text(
            '$quantity',
            key: const Key('itemSheet.quantity'),
            style: LuqmaType.bodyStrong.copyWith(color: colors.textPrimary),
          ),
          IconButton(
            key: const Key('itemSheet.more'),
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
