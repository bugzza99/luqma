import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../see_all_screen.dart';
import 'item_tile.dart';
import 'section_header.dart';
import 'section_gap.dart';

/// The food the city actually orders.
///
/// This heading used to be a second merchant list sorted by `ratingCount`, with a comment
/// admitting it stood in for an order count nothing computed — so "الأكتر طلباً" ranked
/// shops by how many people had reviewed them, and on a launch with no reviews it was
/// every shop in arbitrary order under a promise it did not keep.
///
/// A shelf that scrolls sideways rather than a grid: this is a taster, and the section
/// below it is the whole list. A grid here would push everything else off the screen and
/// make the home one long ranking.
class PopularItemsSection extends ConsumerWidget {
  const PopularItemsSection({super.key, required this.section})
      : _offers = false;

  /// The shops' offers: the same shelf, filled from every shop's «العروض» shelf rather
  /// than from what the city orders. One widget for both, because a dish tile that looks
  /// different in the second section of the home than in the fourth is a design nobody
  /// chose.
  const PopularItemsSection.offers({super.key, required this.section})
      : _offers = true;

  final HomeSection section;
  final bool _offers;

  static const shelfKey = Key('popularItems.shelf');
  static const offersShelfKey = Key('offers.shelf');
  static const emptyKey = Key('popularItems.empty');

  String get _title => section.titleAr.isNotEmpty
      ? section.titleAr
      : (_offers ? 'العروض' : 'الأكتر طلباً');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shelf = ref.watch(_offers ? offerItemsProvider : popularItemsProvider);

    // A shelf that cannot be read is not the same as an empty one, and on this screen
    // both come to the same thing: the home has five other sections working, and an
    // error box wedged between two of them is worse than one section quietly absent.
    // `adSlot` takes the same line, for the same reason.
    if (shelf.hasError) return const SizedBox.shrink();

    return SectionGap(
      child: LuqmaAsyncView(
      value: shelf,
      empty: const SizedBox.shrink(),
      isEmpty: (value) => value.isEmpty,
      loading: const _Skeleton(),
      builder: (context, items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: _title,
            // The shelf holds twenty; «see all» is every offer in the city, so a shop
            // whose offer did not fit on the shelf is still one tap away.
            onSeeAll: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SeeAllScreen(
                  title: _title,
                  showing: _offers ? SeeAll.offers : SeeAll.items,
                ),
              ),
            ),
          ),
          SizedBox(
            key: _offers ? offersShelfKey : shelfKey,
            height: 206,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
              itemBuilder: (context, i) =>
                  LuqmaEntrance(index: i, child: ItemTile(item: items[i])),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

/// Three tiles' worth of nothing, at the shelf's own height, so the sections under it do
/// not jump when the food arrives.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    return SizedBox(
      height: 206,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: 3,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (_, _) => Container(
          width: 150,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: Radii.cardAll,
          ),
        ),
      ),
    );
  }
}
