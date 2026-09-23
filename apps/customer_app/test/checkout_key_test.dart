import 'package:customer_app/src/cart/cart.dart';
import 'package:customer_app/src/cart/cart_controller.dart';
import 'package:customer_app/src/checkout/checkout_key.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// B6. One basket, one checkout id — however many times the screen is opened.
///
/// The id `place_order` settles duplicates by was made with the checkout *screen*. A
/// reply lost after the order committed, a step back to look at the basket, checkout
/// opened again: a new screen, a new id, and a second order the server had no way to
/// recognise. The id belongs to the basket it was made for.
void main() {
  const dish = MenuItem(
    id: 'i1',
    merchantId: 'm1',
    categoryId: 'c1',
    name: 'فراخ',
    price: 12000,
  );

  ProviderContainer container() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  test('the same basket is given the same id, screen after screen', () {
    final c = container();
    c.read(cartProvider.notifier).add(dish);
    final basket = c.read(cartProvider);

    final first = c.read(checkoutKeyProvider.notifier).keyFor(basket);
    final again = c.read(checkoutKeyProvider.notifier).keyFor(c.read(cartProvider));

    expect(again, first);
  });

  test('a basket that changed is a different order, with a different id', () {
    final c = container();
    c.read(cartProvider.notifier).add(dish);
    final first = c.read(checkoutKeyProvider.notifier).keyFor(c.read(cartProvider));

    c.read(cartProvider.notifier).add(dish);
    final changed = c.read(checkoutKeyProvider.notifier).keyFor(c.read(cartProvider));

    expect(changed, isNot(first));
  });

  test('the basket emptied after an order starts the next one afresh', () {
    final c = container();
    c.read(cartProvider.notifier).add(dish);
    final first = c.read(checkoutKeyProvider.notifier).keyFor(c.read(cartProvider));

    c.read(cartProvider.notifier).clear();
    c.read(cartProvider.notifier).add(dish);
    final next = c.read(checkoutKeyProvider.notifier).keyFor(c.read(cartProvider));

    expect(next, isNot(first));
  });

  test('an empty basket is never given an id to reuse', () {
    final c = container();
    expect(
      c.read(checkoutKeyProvider.notifier).keyFor(Cart.empty),
      isNot(c.read(checkoutKeyProvider.notifier).keyFor(Cart.empty)),
    );
  });

  test('a reservation keeps its id until it is placed', () {
    final c = container();
    final keys = c.read(checkoutKeyProvider.notifier);

    final first = keys.keyForReservation('meal-1', 2);
    expect(keys.keyForReservation('meal-1', 2), first, reason: 'the screen opened again');
    expect(keys.keyForReservation('meal-1', 3), isNot(first), reason: 'a different ask');

    final asked = keys.keyForReservation('meal-1', 2);
    keys.reservationPlaced();
    expect(keys.keyForReservation('meal-1', 2), isNot(asked),
        reason: 'the same meal again tomorrow is a new reservation');
  });
}
