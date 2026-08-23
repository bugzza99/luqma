import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'cart.dart';

part 'cart_controller.g.dart';

/// The basket provider, under the name the rest of the app calls it.
///
/// Code generation names a provider after its notifier class, and `Cart` is already the
/// basket itself — so the notifier is `CartController` and this alias keeps every call
/// site reading `cartProvider` rather than `cartControllerProvider`.
const cartProvider = cartControllerProvider;

/// The basket, held for the life of the app session.
///
/// Kept alive deliberately: a basket that emptied itself when the customer navigated
/// away from the merchant would be the single most infuriating thing this app could do.
/// It is not persisted to disk either — a basket assembled yesterday is stale (prices
/// change, items sell out), and reviving one is worse than starting again.
@Riverpod(keepAlive: true)
class CartController extends _$CartController {
  CartController();

  /// Starts from an existing basket. For tests and for restoring a session.
  CartController.seeded(this._seed);

  Cart? _seed;

  @override
  Cart build() => _seed ?? Cart.empty;

  /// Whether [item] can join the basket as it stands.
  bool canAdd(MenuItem item) => state.canAdd(item);

  void add(
    MenuItem item, {
    List<MenuOption> options = const [],
    String? note,
    int quantity = 1,
  }) {
    state = _added(state, item, options, note, quantity);
  }

  /// Throws the basket away and starts a new one. Only ever called after the customer
  /// has been asked — see MerchantScreen.
  void replaceWith(
    MenuItem item, {
    List<MenuOption> options = const [],
    String? note,
    int quantity = 1,
  }) {
    state = _added(Cart.empty, item, options, note, quantity);
  }

  /// [Cart.add] puts in one at a time, and the sheet lets somebody ask for four. Adding
  /// repeatedly keeps the one place that knows how a line merges — `Cart` — rather than
  /// teaching the basket a second way to grow.
  static Cart _added(
    Cart cart,
    MenuItem item,
    List<MenuOption> options,
    String? note,
    int quantity,
  ) {
    var next = cart;
    for (var i = 0; i < quantity; i++) {
      next = next.add(item, options: options, note: note);
    }
    return next;
  }

  void setQuantity(String lineId, int quantity) {
    state = state.setQuantity(lineId, quantity);
  }

  /// Moves a line's quantity by [by], relative to what the basket holds right now.
  ///
  /// Relative rather than absolute because the caller is a widget holding a line that is
  /// a frame old: two taps landing before a rebuild would both compute the same new
  /// total and one of them would be swallowed.
  void changeQuantity(String lineId, int by) {
    final line = state.lines.where((l) => l.id == lineId).firstOrNull;
    if (line == null) return;
    setQuantity(lineId, line.quantity + by);
  }

  void clear() => state = Cart.empty;
}
