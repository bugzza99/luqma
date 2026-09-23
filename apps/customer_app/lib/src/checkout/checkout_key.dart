import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../cart/cart.dart';

/// The id `place_order` settles a duplicate by, kept with the basket it was made for (B6).
///
/// It was made with the checkout *screen*. A reply lost after the order had committed, a
/// step back to look at the basket, checkout opened again — a new screen, a new id, and a
/// second order the server had no way to recognise as the first. So the id now lives as
/// long as the basket does: the same basket, unchanged, is given the same id however many
/// times checkout is opened; a basket that changed is a different order and gets a new
/// one; and the empty basket left behind after an order starts the next one afresh.
///
/// "Unchanged" is identity, not equality. The basket is immutable and every change to it
/// makes a new one, so the object itself answers the question without a deep comparison
/// that could call two different orders the same.
final checkoutKeyProvider =
    NotifierProvider<CheckoutKey, void>(CheckoutKey.new);

class CheckoutKey extends Notifier<void> {
  Cart? _basket;
  String? _key;

  @override
  void build() {}

  String keyFor(Cart basket) {
    if (basket.isNotEmpty && identical(basket, _basket) && _key != null) return _key!;
    _basket = basket.isEmpty ? null : basket;
    return _key = newClientOrderId();
  }

  String? _reservation;
  String? _reservationKey;

  /// The same, for a home kitchen's reservation, which never goes in the basket: one
  /// meal and quantity is one reservation until it is placed. Opening the screen again
  /// after a lost reply must not take a second portion from the cook's count.
  String keyForReservation(String mealId, int quantity) {
    final tag = '$mealId×$quantity';
    if (tag == _reservation && _reservationKey != null) return _reservationKey!;
    _reservation = tag;
    return _reservationKey = newClientOrderId();
  }

  /// The reservation went through; the next one, even of the same meal, is new.
  void reservationPlaced() {
    _reservation = null;
    _reservationKey = null;
  }
}
