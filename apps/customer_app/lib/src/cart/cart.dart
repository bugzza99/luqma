import 'package:flutter/foundation.dart';
import 'package:luqma_core/luqma_core.dart';

/// One thing in the basket: a menu item, the extras chosen with it, and how many.
@immutable
class CartLine {
  const CartLine({
    required this.id,
    required this.itemId,
    required this.merchantId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    this.options = const [],
    this.note,
  });

  /// Identifies this line within the basket. Derived from the item and the chosen
  /// options, so adding the same dish with the same extras finds the existing line
  /// instead of stacking a second one beside it.
  final String id;

  final String itemId;
  final String merchantId;

  /// Copied from the menu, never looked up again. A price or a name edited tomorrow
  /// must not rewrite what somebody ordered today.
  final String name;
  final int unitPrice;
  final int quantity;
  final List<MenuOption> options;
  final String? note;

  int get optionsTotal => options.fold(0, (sum, o) => sum + o.price);
  int get lineTotal => (unitPrice + optionsTotal) * quantity;

  CartLine copyWith({int? quantity}) => CartLine(
        id: id,
        itemId: itemId,
        merchantId: merchantId,
        name: name,
        unitPrice: unitPrice,
        quantity: quantity ?? this.quantity,
        options: options,
        note: note,
      );

  static String idFor(MenuItem item, List<MenuOption> options, String? note) {
    final chosen = options.map((o) => o.id).toList()..sort();
    return '${item.id}|${chosen.join(",")}|${note ?? ""}';
  }
}

/// The basket.
///
/// Every rule here follows from one fact: an order goes to exactly one kitchen. A basket
/// that quietly mixes two merchants produces an order nobody can cook, so mixing is
/// refused outright rather than resolved at checkout, where the customer has already
/// spent the effort.
@immutable
class Cart {
  const Cart({this.merchantId, this.lines = const []});

  static const empty = Cart();

  /// Whose kitchen this basket belongs to. Null while it is empty — an empty basket
  /// belongs to nobody, so any merchant may fill it.
  final String? merchantId;

  final List<CartLine> lines;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  /// Pieces, not lines — three of one dish is three items in the basket.
  int get itemCount => lines.fold(0, (sum, l) => sum + l.quantity);

  /// The food only, in piastres.
  int get subtotal => lines.fold(0, (sum, l) => sum + l.lineTotal);

  bool canAdd(MenuItem item) => isEmpty || item.merchantId == merchantId;

  Cart add(MenuItem item, {List<MenuOption> options = const [], String? note}) {
    if (!canAdd(item)) {
      throw StateError(
        'Cart holds ${item.merchantId == merchantId ? "" : "another merchant"}: '
        'call canAdd first and offer replaceWith.',
      );
    }

    final id = CartLine.idFor(item, options, note);
    final existing = lines.indexWhere((l) => l.id == id);

    if (existing >= 0) {
      final updated = [...lines];
      updated[existing] = lines[existing].copyWith(
        quantity: lines[existing].quantity + 1,
      );
      return Cart(merchantId: item.merchantId, lines: updated);
    }

    return Cart(
      merchantId: item.merchantId,
      lines: [
        ...lines,
        CartLine(
          id: id,
          itemId: item.id,
          merchantId: item.merchantId,
          name: item.name,
          unitPrice: item.price,
          quantity: 1,
          options: options,
          note: note,
        ),
      ],
    );
  }

  /// Throws the basket away and starts again with [item]. What the customer chooses
  /// when they are told the basket belongs to another kitchen.
  Cart replaceWith(MenuItem item,
          {List<MenuOption> options = const [], String? note}) =>
      empty.add(item, options: options, note: note);

  /// Sets a line's quantity. Zero or less removes it — that is how a person takes
  /// something out, and a separate delete control would be a second way to do one thing.
  Cart setQuantity(String lineId, int quantity) {
    if (quantity <= 0) {
      final remaining = lines.where((l) => l.id != lineId).toList();
      // A basket with nothing in it belongs to nobody again.
      return remaining.isEmpty ? empty : Cart(merchantId: merchantId, lines: remaining);
    }

    return Cart(
      merchantId: merchantId,
      lines: [
        for (final line in lines)
          if (line.id == lineId) line.copyWith(quantity: quantity) else line,
      ],
    );
  }

  Cart remove(String lineId) => setQuantity(lineId, 0);

  /// Whether the food clears the merchant's floor.
  ///
  /// Measured on the food alone. Counting the delivery fee would let a customer in a
  /// distant zone clear the floor without buying any more from the merchant, which is
  /// the opposite of what a minimum is for.
  bool meetsMinimum(int minOrder) => subtotal >= minOrder;

  int shortfallFrom(int minOrder) {
    final gap = minOrder - subtotal;
    return gap > 0 ? gap : 0;
  }

  List<OrderLine> toOrderLines() => [
        for (final line in lines)
          OrderLine(
            itemId: line.itemId,
            name: line.name,
            unitPrice: line.unitPrice,
            quantity: line.quantity,
            // The chosen extras, by id. The cart has held the whole `MenuOption`
            // objects since it was written and flattened them to a number right here —
            // which left the server with nothing to check the number against.
            optionIds: [for (final o in line.options) o.id],
            optionsTotal: line.optionsTotal,
            note: line.note,
          ),
      ];
}
