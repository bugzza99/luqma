import 'package:flutter/material.dart';
import 'package:luqma_core/luqma_core.dart';

import '../checkout/checkout_screen.dart';
import '../orders/order_screen.dart';
import 'cart_screen.dart';

/// The basket, and everything downstream of it.
///
/// One place, because two entry points reach this flow — the button on the shell and the
/// bar on a merchant screen — and a second copy would be a second chance to get the
/// last step wrong.
Future<void> openCart(BuildContext context, {VoidCallback? onSignIn}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CartScreen(
        onCheckout: () => openCheckout(context, onSignIn: onSignIn),
      ),
    ),
  );
}

Future<void> openCheckout(BuildContext context, {VoidCallback? onSignIn}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CheckoutScreen(
        onPlaced: (order) => openPlacedOrder(context, order),
        onSignIn: onSignIn == null
            ? null
            : () {
                Navigator.of(context).popUntil((route) => route.isFirst);
                onSignIn();
              },
      ),
    ),
  );
}

/// Lands on the order that was just created, with nothing behind it but the shell.
///
/// Everything between is torn down: going "back" from a placed order must never return
/// to a checkout for an order that has already been sent.
void openPlacedOrder(BuildContext context, Order order) {
  Navigator.of(context).popUntil((route) => route.isFirst);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => OrderScreen(orderId: order.id),
    ),
  );
}
