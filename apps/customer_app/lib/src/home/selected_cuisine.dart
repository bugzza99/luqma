import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// Which cuisine circle is pressed, if any.
///
/// This exists because the two halves of the interaction live in different sections. The
/// circles are `categoryChips`; the list they filter is `merchantList`; and the home
/// screen builds each section from a registry, independently, in whatever order the admin
/// arranged them — so neither can reach the other.
///
/// Without a shared place to put it, the filter would have been smuggled into one of the
/// two sections and read out of it by the other, which stops working the moment the admin
/// removes a section or puts them in the other order.
///
/// Null means every merchant, not none: a customer who has not pressed anything wants the
/// whole list.
final selectedCuisineProvider =
    NotifierProvider<SelectedCuisine, String?>(SelectedCuisine.new);

class SelectedCuisine extends Notifier<String?> {
  @override
  String? build() => null;

  /// Presses a circle, or releases the one that was pressed.
  void select(String? cuisineId) => state = cuisineId;

  /// Pressing the circle that is already pressed clears it — the same gesture in and out,
  /// so nobody has to find a separate "all" to escape a filter they did not mean.
  void toggle(String cuisineId) =>
      state = state == cuisineId ? null : cuisineId;
}

/// The merchants in the pressed circle, or null when nothing is pressed.
///
/// Null and empty are different answers and must stay so: null is "no filter, show
/// everything", empty is "this cuisine has no merchants yet", and collapsing them would
/// show the whole city under a circle that should have been empty.
final merchantsInSelectedCuisineProvider = FutureProvider<Set<String>?>((ref) async {
  final selected = ref.watch(selectedCuisineProvider);
  if (selected == null) return null;

  final result = await ref.watch(cuisineRepositoryProvider).merchantsIn(selected);
  // A failed lookup shows everything rather than nothing. Being unable to narrow a list
  // is not a reason to hide it.
  return result.valueOrNull;
});
