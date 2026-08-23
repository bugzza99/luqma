import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../account/account_screen.dart';
import '../cart/cart.dart';
import '../cart/cart_controller.dart';
import '../cart/open_cart.dart';
import '../home/home_screen.dart';
import '../orders/orders_screen.dart';

/// The three tabs, and the basket that sits above all of them.
///
/// Navigation is imperative — pushes onto one Navigator — rather than a route table.
/// Nothing here is deep-linked and nothing is gated: the app is browsable signed out,
/// and the account is asked for at the one moment it is needed. A router would be
/// machinery for decisions this app does not make.
class CustomerShell extends ConsumerStatefulWidget {
  const CustomerShell({super.key});

  static const homeTabKey = Key('shell.tab.home');
  static const ordersTabKey = Key('shell.tab.orders');
  static const accountTabKey = Key('shell.tab.account');
  static const cartKey = Key('shell.cart');

  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  int _tab = 0;

  void _goToAccount() => setState(() => _tab = 2);

  void _openCart() => openCart(context, onSignIn: _goToAccount);

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final colors = Theme.of(context).luqma;

    return Scaffold(
      backgroundColor: colors.background,
      // One stack rather than a builder per tab, so each tab keeps its scroll position
      // and its loaded data. Coming back to a half-scrolled home and finding it reset
      // is the app forgetting what somebody was doing.
      body: IndexedStack(
        index: _tab,
        children: [
          const HomeScreen(),
          OrdersScreen(onSignIn: _goToAccount),
          const AccountScreen(),
        ],
      ),
      floatingActionButton:
          cart.isEmpty ? null : _CartButton(cart: cart, onTap: _openCart),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            key: CustomerShell.homeTabKey,
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            key: CustomerShell.ordersTabKey,
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'طلباتي',
          ),
          NavigationDestination(
            key: CustomerShell.accountTabKey,
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'حسابي',
          ),
        ],
      ),
    );
  }
}

/// The basket, wherever the customer happens to be.
///
/// It belongs to the app rather than to one tab: a basket assembled on the home has to
/// still be reachable from طلباتي, or somebody loses it by tapping the wrong thing.
class _CartButton extends StatelessWidget {
  const _CartButton({required this.cart, required this.onTap});

  final Cart cart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    return FloatingActionButton.extended(
      key: CustomerShell.cartKey,
      onPressed: onTap,
      backgroundColor: colors.brand,
      foregroundColor: colors.onBrand,
      icon: Badge(
        // Pieces, not lines: two of one dish is two things in the basket.
        label: Text('${cart.itemCount}'),
        backgroundColor: colors.accent,
        textColor: colors.onAccent,
        child: const Icon(Icons.shopping_basket_outlined),
      ),
      label: Text(
        strings.price(cart.subtotal),
        style: LuqmaType.button.copyWith(color: colors.onBrand),
      ),
    );
  }
}
