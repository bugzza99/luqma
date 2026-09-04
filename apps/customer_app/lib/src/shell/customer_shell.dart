import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../account/account_screen.dart';
import '../cart/cart.dart';
import '../cart/cart_controller.dart';
import '../cart/open_cart.dart';
import '../home/home_screen.dart';
import '../orders/order_screen.dart';
import '../orders/orders_screen.dart';
import 'customer_tab.dart';

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
  void _goToAccount() => ref.read(customerTabProvider.notifier).goToAccount();

  void _openCart() => openCart(context, onSignIn: _goToAccount);

  /// Where a tapped notification lands.
  ///
  /// The tab moves as well as the route being pushed, so back from the order leaves
  /// somebody on طلباتي rather than on whatever tab the app happened to be showing when
  /// the notification arrived — which, coming from a cold start, is الرئيسية and has
  /// nothing to do with why they opened the app.
  void _openOrder(String orderId) {
    ref.read(customerTabProvider.notifier).show(CustomerTab.orders);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => OrderScreen(orderId: orderId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final tab = ref.watch(customerTabProvider);
    final colors = Theme.of(context).luqma;

    return LuqmaTappedOrder(
      onOpen: _openOrder,
      child: LuqmaTabPopScope(
        currentIndex: tab,
        // Switching tabs never pushes a route — see the doc comment above — so back on
        // طلباتي or حسابي used to find nothing on the Navigator's stack and exit the app
        // outright. It returns to الرئيسية first now, and only exits from there.
        onHome: () => ref.read(customerTabProvider.notifier).show(CustomerTab.home),
        child: Scaffold(
          backgroundColor: colors.background,
          // One stack rather than a builder per tab, so each tab keeps its scroll position
          // and its loaded data. Coming back to a half-scrolled home and finding it reset
          // is the app forgetting what somebody was doing.
          body: IndexedStack(
            index: tab,
            children: [
              const HomeScreen(),
              OrdersScreen(onSignIn: _goToAccount),
              const AccountScreen(),
            ],
          ),
          floatingActionButton:
              cart.isEmpty ? null : _CartButton(cart: cart, onTap: _openCart),
          bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (i) =>
                ref.read(customerTabProvider.notifier).show(i),
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
        ),
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
