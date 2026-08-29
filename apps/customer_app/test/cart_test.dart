import 'package:customer_app/src/cart/cart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The basket, before any of it reaches a server.
///
/// Its rules are all consequences of one fact: an order goes to exactly one kitchen. A
/// basket that quietly mixes two merchants produces an order nobody can cook.
void main() {
  const chicken = MenuItem(
    id: 'i1',
    merchantId: 'm1',
    categoryId: 'c1',
    name: 'فراخ مشوية',
    price: 12000,
    options: [MenuOption(id: 'o1', name: 'أرز زيادة', price: 1500)],
  );
  const kofta = MenuItem(
    id: 'i2',
    merchantId: 'm1',
    categoryId: 'c1',
    name: 'كفتة',
    price: 8500,
  );
  const koshari = MenuItem(
    id: 'i3',
    merchantId: 'm2',
    categoryId: 'c1',
    name: 'كشري',
    price: 4000,
  );

  group('adding', () {
    test('an empty cart takes the first item and remembers its merchant', () {
      final cart = Cart.empty.add(chicken);

      expect(cart.merchantId, 'm1');
      expect(cart.lines.single.name, 'فراخ مشوية');
      expect(cart.lines.single.quantity, 1);
    });

    test('the same item again raises the quantity rather than repeating the line', () {
      final cart = Cart.empty.add(chicken).add(chicken);

      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.quantity, 2);
    });

    // Same dish, different extras, is a different thing to cook.
    test('the same item with different options is a separate line', () {
      final cart = Cart.empty
          .add(chicken)
          .add(chicken, options: const [MenuOption(id: 'o1', name: 'أرز زيادة', price: 1500)]);

      expect(cart.lines, hasLength(2));
    });

    test('options are priced into the line', () {
      final cart = Cart.empty.add(
        chicken,
        options: const [MenuOption(id: 'o1', name: 'أرز زيادة', price: 1500)],
      );

      expect(cart.lines.single.optionsTotal, 1500);
      expect(cart.subtotal, 13500);
    });

    test('a note rides along with the line', () {
      final cart = Cart.empty.add(chicken, note: 'من غير شطة');
      expect(cart.lines.single.note, 'من غير شطة');
    });

    // The rule everything else follows from.
    test('an item from another merchant is refused, not silently mixed', () {
      final cart = Cart.empty.add(chicken);

      expect(cart.canAdd(koshari), isFalse);
      expect(() => cart.add(koshari), throwsA(isA<StateError>()));
    });

    test('switching merchant means starting a new basket', () {
      final cart = Cart.empty.add(chicken).replaceWith(koshari);

      expect(cart.merchantId, 'm2');
      expect(cart.lines.single.name, 'كشري');
    });
  });

  group('changing quantity', () {
    test('increasing and decreasing a line', () {
      var cart = Cart.empty.add(chicken);
      cart = cart.setQuantity(cart.lines.single.id, 3);

      expect(cart.lines.single.quantity, 3);
      expect(cart.subtotal, 36000);
    });

    // Zero is how a person removes something; making them find a delete button as well
    // is a second way to do one thing.
    test('setting a quantity to zero removes the line', () {
      var cart = Cart.empty.add(chicken).add(kofta);
      cart = cart.setQuantity(cart.lines.first.id, 0);

      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.name, 'كفتة');
    });

    test('removing the last line empties the cart and forgets the merchant', () {
      var cart = Cart.empty.add(chicken);
      cart = cart.setQuantity(cart.lines.single.id, 0);

      expect(cart.isEmpty, isTrue);
      expect(cart.merchantId, isNull,
          reason: 'an empty cart belongs to nobody, so any merchant may fill it');
    });

    test('a negative quantity is treated as zero, not as a negative price', () {
      var cart = Cart.empty.add(chicken);
      cart = cart.setQuantity(cart.lines.single.id, -5);
      expect(cart.isEmpty, isTrue);
    });
  });

  group('what it costs', () {
    test('the subtotal is the lines', () {
      final cart = Cart.empty.add(chicken).add(kofta);
      expect(cart.subtotal, 20500);
    });

    test('an empty cart costs nothing', () {
      expect(Cart.empty.subtotal, 0);
      expect(Cart.empty.itemCount, 0);
    });

    test('the item count counts pieces, not lines', () {
      var cart = Cart.empty.add(chicken).add(kofta);
      cart = cart.setQuantity(cart.lines.first.id, 3);
      expect(cart.itemCount, 4);
    });
  });

  group('the minimum order', () {
    test('a basket under the merchant minimum cannot be sent', () {
      final cart = Cart.empty.add(kofta);
      expect(cart.meetsMinimum(10000), isFalse);
      expect(cart.shortfallFrom(10000), 1500);
    });

    test('exactly the minimum is enough', () {
      final cart = Cart.empty.add(kofta).setQuantity('', 0);
      expect(Cart.empty.add(kofta).meetsMinimum(8500), isTrue);
      expect(cart.shortfallFrom(0), 0);
    });

    // The delivery fee is not food. Counting it toward the minimum would let a distant
    // customer clear a merchant's floor without buying more from them.
    test('the minimum is measured on the food alone', () {
      final cart = Cart.empty.add(kofta);
      expect(cart.subtotal, 8500);
      expect(cart.meetsMinimum(9000), isFalse);
    });
  });

  group('turning it into order lines', () {
    test('each cart line becomes an order line with its options priced in', () {
      final cart = Cart.empty.add(
        chicken,
        options: const [MenuOption(id: 'o1', name: 'أرز زيادة', price: 1500)],
      );

      final lines = cart.toOrderLines();

      expect(lines.single.itemId, 'i1');
      expect(lines.single.unitPrice, 12000);
      expect(lines.single.optionsTotal, 1500);
      expect(lines.single.lineTotal, 13500);
    });

    // The name is copied, not referenced: a menu edited tomorrow must not rewrite what
    // somebody ordered today.
    test('the name is carried, not looked up later', () {
      final lines = Cart.empty.add(chicken).toOrderLines();
      expect(lines.single.name, 'فراخ مشوية');
    });
  });
}
