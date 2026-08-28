import 'package:flutter/material.dart';
import 'package:luqma_core/luqma_core.dart';

import '../cart/open_cart.dart';
import 'meal_screen.dart';
import 'preorder_checkout_screen.dart';

/// Opens one home-cooked meal.
///
/// One function rather than a callback threaded down through the home-section registry:
/// the registry builds sections from a fixed map keyed by a server-chosen string and has
/// no navigation to hand them.
Future<void> openMeal(BuildContext context, String mealId) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MealScreen(
        mealId: mealId,
        onReserve: (meal, quantity) =>
            openPreorderCheckout(context, meal, quantity),
      ),
    ),
  );
}

Future<void> openPreorderCheckout(
  BuildContext context,
  DailyMeal meal,
  int quantity, {
  VoidCallback? onSignIn,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PreorderCheckoutScreen(
        meal: meal,
        quantity: quantity,
        // The same landing as an ordinary order: everything between here and the shell
        // is torn down, so going "back" from a confirmed reservation never returns to a
        // checkout for one already made.
        onPlaced: (order) => openPlacedOrder(context, order),
        onSignIn: onSignIn,
      ),
    ),
  );
}
