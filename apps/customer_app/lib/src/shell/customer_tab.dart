import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which of the three tabs is showing.
///
/// A provider rather than `setState` in the shell, for the same reason
/// `selectedCuisineProvider` is one: the home's sections are built by a registry from a
/// server-chosen list, so a section cannot be handed a callback and cannot reach the
/// shell that contains it.
///
/// What that cost: a signed-out customer who opened a home-cooked meal from the home
/// and tapped احجز reached a checkout whose "سجّل دخول" button was disabled, because
/// `openMeal` had no `onSignIn` to forward. Every other route to a checkout — the basket
/// on the shell, the bar on a merchant screen — went through `openCart`, which the shell
/// does hand its own callback. The one path built out of a registry section was the one
/// with no way in.
final customerTabProvider =
    NotifierProvider<CustomerTab, int>(CustomerTab.new);

class CustomerTab extends Notifier<int> {
  static const home = 0;
  static const orders = 1;
  static const account = 2;

  @override
  int build() => home;

  void show(int tab) => state = tab;

  /// Where every "you need an account for this" lands.
  void goToAccount() => state = account;
}
