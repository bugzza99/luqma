import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'sections/item_tile.dart';
import 'sections/merchant_tile.dart';

/// Which list this screen is the whole of.
enum SeeAll { merchants, items }

/// Everything the shelf above only had room for a corner of.
///
/// The home's sections are deliberately short — a taster each, so a customer sees that
/// the city has restaurants *and* home kitchens *and* offers before they have scrolled
/// anywhere. That only works if the heading is a way in: a section showing six of forty
/// shops with nothing to tap is a screen that hides its own contents.
///
/// One screen for both lists rather than two, because they differ in a tile builder and
/// a provider. Two would be two places to fix the same empty state.
class SeeAllScreen extends ConsumerWidget {
  const SeeAllScreen({super.key, required this.title, required this.showing});

  final String title;
  final SeeAll showing;

  static const gridKey = Key('seeAll.grid');
  static const emptyKey = Key('seeAll.empty');
  static const errorKey = Key('seeAll.error');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: Text(title)),
      body: switch (showing) {
        SeeAll.merchants => _Grid<Merchant>(
            value: ref.watch(merchantsProvider(ref.watch(currentCityProvider))),
            onRetry: () => ref.invalidate(
              merchantsProvider(ref.watch(currentCityProvider)),
            ),
            empty: 'مفيش مطاعم لسه.',
            // Wider than they are tall: the tile is a logo beside two lines, and a
            // squarer cell would be a box with a hole under the words.
            aspectRatio: 1.55,
            tile: (merchant) => MerchantTile(merchant: merchant),
          ),
        SeeAll.items => _Grid<MenuItem>(
            value: ref.watch(popularItemsProvider),
            onRetry: () => ref.invalidate(popularItemsProvider),
            empty: 'مفيش أكل لسه.',
            // Taller than it is wide: a 4:3 picture with a name, a shop and a price
            // underneath it.
            aspectRatio: 0.78,
            tile: (item) => ItemTile(item: item, width: double.infinity),
          ),
      },
    );
  }
}

class _Grid<T> extends StatelessWidget {
  const _Grid({
    required this.value,
    required this.onRetry,
    required this.empty,
    required this.aspectRatio,
    required this.tile,
  });

  final AsyncValue<List<T>> value;
  final VoidCallback onRetry;
  final String empty;
  final double aspectRatio;
  final Widget Function(T) tile;

  @override
  Widget build(BuildContext context) {
    return LuqmaAsyncView(
      value: value,
      errorKey: SeeAllScreen.errorKey,
      onRetry: onRetry,
      empty: LuqmaEmptyView(key: SeeAllScreen.emptyKey, title: empty),
      isEmpty: (list) => list.isEmpty,
      builder: (context, list) => GridView.builder(
        key: SeeAllScreen.gridKey,
        padding: const EdgeInsets.all(Space.gutter),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: Space.sm,
          crossAxisSpacing: Space.sm,
          childAspectRatio: aspectRatio,
        ),
        itemCount: list.length,
        itemBuilder: (context, i) =>
            LuqmaEntrance(index: i, child: tile(list[i])),
      ),
    );
  }
}
