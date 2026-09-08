import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'cart.dart';
import 'cart_controller.dart';

/// The basket.
///
/// Blocking reasons belong beside the button they disable, before the customer spends
/// effort choosing an address. Only that address can determine the delivery charge.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key, required this.onCheckout});

  /// Where "اختار العنوان" goes. Injected rather than routed from inside so the shell owns
  /// navigation — and required, so whether the button is enabled says something about
  /// the basket rather than about whether anybody wired it up.
  final VoidCallback onCheckout;

  static const emptyKey = Key('cart.empty');
  static const subtotalKey = Key('cart.subtotal');
  static const checkoutKey = Key('cart.checkout');
  static const shortfallKey = Key('cart.shortfall');
  static const closedKey = Key('cart.closed');
  static const missingKey = Key('cart.missing');
  static const summaryKey = Key('cart.summary');
  static const deliveryNoteKey = Key('cart.deliveryNote');
  static const cashKey = Key('cart.cash');
  static const shopKey = Key('cart.shop');
  static const backKey = Key('cart.back');
  static const subtotalMotionKey = Key('cart.subtotalMotion');
  static Key imageKey(String id) => Key('cart.image.$id');
  static Key exitKey(String id) => Key('cart.exit.$id');

  static Key lineKey(String lineId) => Key('cart.line.$lineId');
  static Key lessKey(String lineId) => Key('cart.less.$lineId');
  static Key moreKey(String lineId) => Key('cart.more.$lineId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('السلة'),
        // No colours here. `luqmaTheme`'s `appBarTheme` already paints every bar in all
        // three apps burgundy on `onBrand`, and this was the only screen restating it —
        // which is the same trap the motion tokens fell into: chrome a screen has to
        // remember to ask for is chrome the twenty-sixth screen forgets.
        leading: IconButton(
          key: backKey,
          tooltip: 'رجوع',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: _Full(cart: cart),
      bottomNavigationBar:
          cart.isEmpty ? null : _Footer(cart: cart, onCheckout: onCheckout),
    );
  }
}

class _Full extends ConsumerStatefulWidget {
  const _Full({required this.cart});

  final Cart cart;

  @override
  ConsumerState<_Full> createState() => _FullState();
}

class _FullState extends ConsumerState<_Full> {
  late List<CartLine> _rows = [...widget.cart.lines];

  @override
  void didUpdateWidget(_Full oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = {for (final line in widget.cart.lines) line.id: line};
    _rows = [
      for (final line in _rows) current.remove(line.id) ?? line,
      ...current.values,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduced = Motion.of(context, Motion.quick) == Duration.zero;
    final ids = {for (final line in widget.cart.lines) line.id};
    // Retain only the departing presentation; the basket and its subtotal change on tap.
    if (reduced) _rows.removeWhere((line) => !ids.contains(line.id));
    if (_rows.isEmpty) {
      return const LuqmaEmptyView(
        key: CartScreen.emptyKey,
        icon: Icons.shopping_basket_outlined,
        title: 'السلة فاضية',
        message: 'اختار من المطاعم والأكل البيتي وهيتحطّ هنا.',
      );
    }
    final merchant = ref.watch(merchantProvider(
      widget.cart.merchantId ?? _rows.first.merchantId,
    )).value;
    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        if (merchant != null) ...[
          Text('من ${merchant.name}', key: CartScreen.shopKey,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.luqma.textSecondary)),
          const SizedBox(height: Space.md),
        ],
        for (var i = 0; i < _rows.length; i++)
          _DepartingLine(
            key: ValueKey(_rows[i].id),
            line: _rows[i],
            index: i,
            removed: !ids.contains(_rows[i].id),
            onRemoved: (id) => setState(() =>
                _rows.removeWhere((line) => line.id == id)),
          ),
        // `_rows`, not `widget.cart`. The cart empties on the tap while the last line is
        // still collapsing, so gating on the cart snapped the summary and the cash note
        // out in one frame beneath a row that was politely animating away — the exact
        // thing that reads as a bug rather than as a removal.
        if (_rows.isNotEmpty) ...[
          _Summary(cart: widget.cart),
          const SizedBox(height: Space.md),
          Row(
            key: CartScreen.cashKey,
            children: [
              Icon(Icons.credit_card_rounded, size: Sizes.iconSm,
                  color: theme.luqma.textSecondary),
              const SizedBox(width: Space.sm),
              Expanded(child: Text('الدفع كاش عند الاستلام',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.luqma.textSecondary))),
            ],
          ),
        ],
      ],
    );
  }
}

class _DepartingLine extends StatefulWidget {
  const _DepartingLine({
    super.key,
    required this.line,
    required this.index,
    required this.removed,
    required this.onRemoved,
  });

  final CartLine line;
  final int index;
  final bool removed;
  final ValueChanged<String> onRemoved;

  @override
  State<_DepartingLine> createState() => _DepartingLineState();
}

class _DepartingLineState extends State<_DepartingLine>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, value: 1);
  late final _size = CurvedAnimation(parent: _controller, curve: Motion.exit);

  @override
  void didUpdateWidget(_DepartingLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.removed && !oldWidget.removed) {
      _controller.duration = Motion.of(context, Motion.quick);
      _controller.reverse().then((_) {
        if (mounted && widget.removed) widget.onRemoved(widget.line.id);
      });
    } else if (!widget.removed && oldWidget.removed) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _size.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: _LineRow(line: widget.line),
    );
    return SizeTransition(
      key: CartScreen.exitKey(widget.line.id),
      sizeFactor: _size,
      child: IgnorePointer(
        ignoring: widget.removed,
        child: ExcludeSemantics(
          excluding: widget.removed,
          // A tap during arrival starts the exit alone, rather than moving twice.
          child: widget.removed || Motion.of(context, Motion.quick) == Duration.zero
              ? child : LuqmaEntrance(index: widget.index, child: child),
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final CartLine line;

  static const thumbnailSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      key: CartScreen.lineKey(line.id),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        boxShadow: theme.brightness == Brightness.light
            ? Elevations.card : Elevations.none,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Decorative *here*, unlike on the home grid. With no photo the fallback draws
          // a monogram of `line.name`, and that same string is a `Text` a few pixels
          // away — so without this the row is announced twice, «فراخ مشوية، صورة» and
          // then «فراخ مشوية».
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: Radii.imageAll,
              child: SizedBox.square(
                dimension: thumbnailSize,
                // The ordered snapshot has no photo; a later menu edit must not rewrite
                // it.
                child: LuqmaImage(key: CartScreen.imageKey(line.id),
                    url: null, name: line.name),
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, style: theme.textTheme.titleMedium),
                if (line.options.isNotEmpty) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    line.options.map((o) => '+ ${o.name}').join('\n'),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ],
                if (line.note != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    line.note!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Two portions must carry the amount for both, including their extras.
              Text(strings.price(line.lineTotal),
                  style: LuqmaType.priceSmall.copyWith(color: colors.price)),
              const SizedBox(height: Space.xs),
              _Stepper(line: line),
            ],
          ),
        ],
      ),
    );
  }
}

/// Minus, the number, plus. Minus at one removes the line — that is how somebody takes
/// something out, and a separate bin icon would be a second control for one action.
class _Stepper extends ConsumerWidget {
  const _Stepper({required this.line});

  // The visible outline is smaller than the controls so fingers keep the house target.
  static const boxHeight = 30.0;

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;
    // The step, not the new total: [line] is a frame old, so two quick taps would both
    // compute the same number and one of them would be swallowed.
    void step(int by) => ref.read(cartProvider.notifier).changeQuantity(line.id, by);

    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Center(child: Container(
            height: boxHeight,
            decoration: BoxDecoration(
              borderRadius: Radii.fieldAll,
              border: Border.all(color: colors.border),
            ),
          )),
        ),
        Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: CartScreen.lessKey(line.id),
            // The icon changes at one, so the name has to change with it: the
            // control that says "one less" and the one that empties the line are
            // not the same promise.
            tooltip: line.quantity > 1 ? 'واحد أقل' : 'شيل الصنف',
            onPressed: () => step(-1),
            icon: Icon(
              line.quantity > 1
                  ? Icons.remove_rounded
                  : Icons.delete_outline_rounded,
              size: Sizes.iconSm,
            ),
            constraints: const BoxConstraints(
              minWidth: Sizes.minTarget,
              minHeight: Sizes.minTarget,
            ),
          ),
          Text(
            '${line.quantity}',
            style: LuqmaType.bodyStrong.copyWith(color: colors.textPrimary),
          ),
          IconButton(
            key: CartScreen.moreKey(line.id),
            tooltip: 'واحد زيادة',
            onPressed: () => step(1),
            icon: const Icon(Icons.add_rounded, size: Sizes.iconSm),
            constraints: const BoxConstraints(
              minWidth: Sizes.minTarget,
              minHeight: Sizes.minTarget,
            ),
          ),
        ],
      ),
      ],
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.cart, required this.onCheckout});

  static const buttonHeight = 50.0;

  final Cart cart;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    // The whole `AsyncValue`, not its `.value`. `merchantProvider` is a `FutureProvider`,
    // so its first state is always `AsyncLoading` — where `.value` is null, exactly like a
    // shop that is genuinely gone. Branching on null alone therefore drew the red «المطعم
    // مش متاح» over a Supabase round trip, on the ordinary path: opening the basket from
    // the shell's badge, where nothing else is holding this provider alive, so a returning
    // customer met a false sentence in the alarming tone before the shop name arrived.
    //
    // `hasError` first, for the reason `CLAUDE.md` gives about the merchant inbox: a
    // stream that fails before it has ever emitted stays `AsyncLoading` with the error
    // hanging off it, so an error arm placed after a loading arm never fires.
    final merchantAsync = ref.watch(merchantProvider(cart.merchantId ?? ''));
    final merchant = merchantAsync.value;
    // Loading says nothing. It is the honest thing to say while nothing is known, and
    // `canCheckout` already refuses the button without a merchant.
    final missing = merchantAsync.hasError ||
        (!merchantAsync.isLoading && merchant == null);
    // Never DateTime.now(): whether a shop is open depends on the hour, and a widget
    // reading the wall clock can only be tested by waiting for the right one.
    final open =
        merchant?.acceptsOrdersAt(ref.watch(clockProvider)()) ?? false;
    final minOrder = merchant?.minOrder ?? 0;
    final shortfall = cart.shortfallFrom(minOrder);

    // Until the merchant is known, the button waits rather than promising something
    // that a moment later turns out to be refused.
    final canCheckout = merchant != null && open && shortfall == 0;

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (missing)
                const LuqmaNotice(
                  key: CartScreen.missingKey,
                  icon: Icons.storefront_outlined,
                  tone: NoticeTone.problem,
                  text: 'المطعم مش متاح دلوقتي — سلتك محفوظة.',
                )
              else if (merchant != null && !open)
                LuqmaNotice(
                  key: CartScreen.closedKey,
                  icon: Icons.schedule_rounded,
                  tone: NoticeTone.problem,
                  // The basket is kept: it is still what they wanted, and it will send
                  // itself fine tomorrow.
                  text: '${strings.merchantClosed} — سلتك محفوظة.',
                )
              else if (shortfall > 0)
                LuqmaNotice(
                  key: CartScreen.shortfallKey,
                  icon: Icons.add_shopping_cart_rounded,
                  tone: NoticeTone.information,
                  // The gap, not just the floor: otherwise the customer does the
                  // subtraction themselves to find out what would fix it.
                  text: 'ناقص ${strings.price(shortfall)} توصل لأقل طلب '
                      '${strings.price(minOrder)}',
                ),
              // The same condition as the notices above, or a gap is reserved over a
              // notice that is not drawn — which is what a loading merchant now does.
              if (missing || (merchant != null && (!open || shortfall > 0)))
                const SizedBox(height: Space.md),
              FilledButton(
                key: CartScreen.checkoutKey,
                onPressed: canCheckout ? onCheckout : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(buttonHeight),
                ),
                child: const Text('اختار العنوان'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



class _Summary extends StatelessWidget {
  const _Summary({required this.cart});
  final Cart cart;
  static const pulseFrom = 0.92;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final amount = Text(LuqmaStrings.of(context).price(cart.subtotal),
        style: LuqmaType.price.copyWith(color: colors.price));
    return Container(
      key: CartScreen.summaryKey,
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
        boxShadow: theme.brightness == Brightness.light
            ? Elevations.card : Elevations.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            key: CartScreen.subtotalKey,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('الأصناف', style: theme.textTheme.bodyMedium),
              // Only the current amount exists, even on the first frame of the pulse.
              if (Motion.of(context, Motion.quick) == Duration.zero) amount
              else TweenAnimationBuilder<double>(
                key: ValueKey(cart.subtotal),
                tween: Tween(begin: pulseFrom, end: 1),
                duration: Motion.of(context, Motion.quick),
                curve: Motion.enter,
                builder: (context, scale, child) => Transform.scale(
                    key: CartScreen.subtotalMotionKey, scale: scale, child: child),
                child: amount,
              ),
            ],
          ),
          Divider(color: colors.hairline, height: Space.xl),
          // The address is next; quoting a fee now would promise a bill we cannot know.
          Text('التوصيل بيتحسب بعد ما تختار العنوان',
              key: CartScreen.deliveryNoteKey,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary)),
        ],
      ),
    );
  }
}
