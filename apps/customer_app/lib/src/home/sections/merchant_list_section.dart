import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../see_all_screen.dart';
import '../selected_cuisine.dart';
import 'merchant_tile.dart';

import 'section_header.dart';

/// A list of merchants, ordered by whatever the section asked for.
///
/// One widget behind two section types — `merchantList` and `topRated` — because they
/// differ only in sort order. `mostOrdered` used to be the third, and it is not a
/// merchant list at all: what a customer wants under "the most ordered" is food they can
/// tap. It is [PopularItemsSection] now.
///
/// Two across rather than one. A full-width card gives each shop a 16:9 photograph and
/// most of the fold, so the home showed two shops before the screen ran out — which on a
/// list of forty is a list nobody reaches the end of.
class MerchantListSection extends ConsumerWidget {
  const MerchantListSection({
    super.key,
    required this.section,
    this.topRated = false,
  });

  final HomeSection section;
  final bool topRated;

  String get _title {
    if (section.titleAr.isNotEmpty) return section.titleAr;
    if (topRated) return 'الأعلى تقييماً';
    return 'كل المطاعم';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchants = ref.watch(merchantsProvider(ref.watch(currentCityProvider)));
    // Nothing on the card says which merchant paid. Saying so would make the placement
    // worth less than it cost.
    final boosted = ref.watch(boostedMerchantsProvider);
    // Null means nothing is pressed, and everything shows. Empty means the pressed
    // circle has no merchants in it yet — a different answer, and it has to stay one.
    final inCuisine = ref.watch(merchantsInSelectedCuisineProvider).value;

    return LuqmaAsyncView(
      value: merchants,
      empty: const SizedBox.shrink(),
      isEmpty: (value) => value.isEmpty,
      loading: const _Skeleton(),
      builder: (context, value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: _title,
              onSeeAll: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SeeAllScreen(title: _title, showing: SeeAll.merchants),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              // `shrinkWrap` with the scroll off: this grid sits inside the home's own
              // scroll view, and a nested scrollable would trap the gesture — a drag
              // starting on a shop would move the grid a pixel instead of the page.
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: Space.sm,
                  crossAxisSpacing: Space.sm,
                  childAspectRatio: 1.55,
                ),
                itemCount: _shown(value, inCuisine, boosted).length,
                itemBuilder: (context, i) => LuqmaEntrance(
                  // Indexed so the tiles arrive in order rather than all at once.
                  // `Motion.staggerMax` caps it, so a long list still lands as an
                  // arrival rather than a wait.
                  index: i,
                  child: MerchantTile(
                    merchant: _shown(value, inCuisine, boosted)[i],
                  ),
                ),
              ),
            ),
          ],
        )
    );
  }

  /// What this section actually draws: filtered, sorted, boosted.
  List<Merchant> _shown(
    List<Merchant> all,
    Set<String>? inCuisine,
    Set<String> boosted,
  ) =>
      _sorted(_filtered(all, inCuisine), boosted);

  /// Narrowed to the pressed cuisine, if one is pressed.
  List<Merchant> _filtered(List<Merchant> merchants, Set<String>? inCuisine) =>
      inCuisine == null
          ? merchants
          : merchants.where((m) => inCuisine.contains(m.id)).toList();

  List<Merchant> _sorted(List<Merchant> merchants, Set<String> boosted) {
    final list = [...merchants];
    if (topRated) {
      list.sort((a, b) => b.ratingAvg.compareTo(a.ratingAvg));
    }
    // Applied last, on top of whatever order this section asked for. A boost lifts; it
    // does not reshuffle — a merchant who bought nothing finds the list as they expect.
    return Boost.apply(list, boosted: boosted);
  }
}

/// What the list looks like while it is loading.
///
/// Three boxes the height of a card, so the page does not jump when the merchants
/// arrive — the same reason the card fixes its picture's aspect ratio.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++) ...[
            Container(
              // A row of two tiles, at the height the grid gives them.
              height: 116,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: Radii.cardAll,
              ),
            ),
            const SizedBox(height: Space.sm),
          ],
        ],
      ),
    );
  }
}
