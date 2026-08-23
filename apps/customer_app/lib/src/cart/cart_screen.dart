import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'cart.dart';
import 'cart_controller.dart';

/// The basket.
///
/// Nothing is hidden here and nothing is decided elsewhere: the lines, what they cost,
/// and whether this basket can actually be sent. The two things that can stop it — a
/// merchant that shut, and a total under their floor — say so on this screen, next to
/// the button they disable, rather than failing at checkout after more effort is spent.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key, required this.onCheckout});

  /// Where "كمّل الطلب" goes. Injected rather than routed from inside so the shell owns
  /// navigation — and required, so whether the button is enabled says something about
  /// the basket rather than about whether anybody wired it up.
  final VoidCallback onCheckout;

  static const emptyKey = Key('cart.empty');
  static const subtotalKey = Key('cart.subtotal');
  static const checkoutKey = Key('cart.checkout');
  static const shortfallKey = Key('cart.shortfall');
  static const closedKey = Key('cart.closed');

  static Key lineKey(String lineId) => Key('cart.line.$lineId');
  static Key lessKey(String lineId) => Key('cart.less.$lineId');
  static Key moreKey(String lineId) => Key('cart.more.$lineId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('السلة')),
      body: cart.isEmpty ? const _Empty() : _Full(cart: cart),
      bottomNavigationBar:
          cart.isEmpty ? null : _Footer(cart: cart, onCheckout: onCheckout),
    );
  }
}

class _Full extends StatelessWidget {
  const _Full({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.xxxl,
      ),
      children: [
        for (final line in cart.lines) ...[
          _LineRow(line: line),
          const SizedBox(height: Space.sm),
        ],
      ],
    );
  }
}

class _LineRow extends ConsumerWidget {
  const _LineRow({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return Container(
      key: CartScreen.lineKey(line.id),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: Radii.cardAll,
        border: Border.all(color: colors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.name, style: theme.textTheme.titleMedium),
                if (line.options.isNotEmpty) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    line.options.map((o) => o.name).join('، '),
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
                const SizedBox(height: Space.sm),
                // The line total, not the unit price: a "5 ج" beside a line of two
                // loaves is a wrong number sitting directly above a correct sum.
                Text(
                  strings.price(line.lineTotal),
                  style: LuqmaType.priceSmall.copyWith(color: colors.price),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          _Stepper(line: line),
        ],
      ),
    );
  }
}

/// Minus, the number, plus. Minus at one removes the line — that is how somebody takes
/// something out, and a separate bin icon would be a second control for one action.
class _Stepper extends ConsumerWidget {
  const _Stepper({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;
    // Read from the notifier's current state rather than from [line], which is a
    // frame old: two quick taps would otherwise both compute from the same number.
    void step(int by) {
      final controller = ref.read(cartProvider.notifier);
      final current = controller.state.lines
          .where((l) => l.id == line.id)
          .map((l) => l.quantity)
          .firstOrNull;
      if (current == null) return;
      controller.setQuantity(line.id, current + by);
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: Radii.pillAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: CartScreen.lessKey(line.id),
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
            onPressed: () => step(1),
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

class _Footer extends ConsumerWidget {
  const _Footer({required this.cart, required this.onCheckout});

  final Cart cart;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    final merchant = ref.watch(merchantProvider(cart.merchantId ?? '')).value;
    final open = merchant?.acceptsOrdersAt(DateTime.now()) ?? false;
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
              if (merchant != null && !open)
                _Notice(
                  noticeKey: CartScreen.closedKey,
                  icon: Icons.schedule_rounded,
                  color: colors.danger,
                  // The basket is kept: it is still what they wanted, and it will send
                  // itself fine tomorrow.
                  text: '${strings.merchantClosed} — سلتك محفوظة.',
                )
              else if (shortfall > 0)
                _Notice(
                  noticeKey: CartScreen.shortfallKey,
                  icon: Icons.add_shopping_cart_rounded,
                  color: colors.textSecondary,
                  // The gap, not just the floor: otherwise the customer does the
                  // subtraction themselves to find out what would fix it.
                  text: 'ناقص ${strings.price(shortfall)} توصل لأقل طلب '
                      '${strings.price(minOrder)}',
                ),
              if (merchant == null || !open || shortfall > 0)
                const SizedBox(height: Space.md),
              Row(
                key: CartScreen.subtotalKey,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'إجمالي الأكل',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colors.textSecondary),
                  ),
                  Text(
                    strings.price(cart.subtotal),
                    style: LuqmaType.price.copyWith(color: colors.price),
                  ),
                ],
              ),
              const SizedBox(height: Space.xs),
              // The fee depends on the address, which is the next screen. Promising a
              // final total here and changing it there is the worse of the two.
              Text(
                'التوصيل بيتحسب بعد ما تختار العنوان',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: Space.md),
              FilledButton(
                key: CartScreen.checkoutKey,
                onPressed: canCheckout ? onCheckout : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('كمّل الطلب'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.noticeKey,
    required this.icon,
    required this.color,
    required this.text,
  });

  final Key noticeKey;
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: noticeKey,
      children: [
        Icon(icon, size: Sizes.iconSm, color: color),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Center(
      key: CartScreen.emptyKey,
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_basket_outlined,
              size: 56,
              color: colors.textSecondary,
            ),
            const SizedBox(height: Space.lg),
            Text(
              'السلة فاضية',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Space.sm),
            Text(
              'اختار من المطاعم والأكل البيتي وهيتحطّ هنا.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
