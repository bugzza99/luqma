import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../see_all_screen.dart';
import '../selected_cuisine.dart';
import 'merchant_tile.dart';

import 'section_header.dart';
import 'section_gap.dart';

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

    return SectionGap(
      child: LuqmaAsyncView(
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
              // A column of full-width rows rather than a two-across grid. The grid fitted
              // six shops on a screen by halving each one, which forced every tile to
              // choose between saying what the food is and saying whether the shop is any
              // good — and usually truncated both. A row fits the same six and has a
              // whole line for each.
              //
              // Built by hand rather than with a `ListView`: this sits inside the home's
              // own scroll view, and a nested scrollable traps the gesture — a drag
              // starting on a shop would move the list a pixel instead of the page.
              // `shrinkWrap` avoids that too, at the cost of laying out every child on
              // every frame, which a `Column` of a dozen rows does not need.
              child: Column(
                children: [
                  // A pressed circle with nobody in it yet. The heading stays, so the
                  // page does not jump, and a sentence under it says the list is empty on
                  // purpose — a heading over nothing reads as a load that failed.
                  if (inCuisine != null &&
                      _filtered(value, inCuisine).isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.md),
                      child: Text(
                        'لسه مفيش محلات في النوع ده. جرّب نوع تاني أو دوس «الكل».',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).luqma.textSecondary,
                            ),
                      ),
                    ),
                  for (final (i, merchant)
                      in _shown(value, inCuisine, boosted,
                              minRatings:
                                  ref.watch(appConfigProvider).minRatingsToShow)
                          .indexed) ...[
                    if (i > 0) const SizedBox(height: Space.sm + 1),
                    // Indexed so the rows arrive in order rather than all at once.
                    // `Motion.staggerMax` caps it, so a long list still lands as an
                    // arrival rather than a wait.
                    LuqmaEntrance(index: i, child: MerchantTile(merchant: merchant)),
                  ],
                ],
              ),
            ),
          ],
        )
    ),
    );
  }

  /// What this section actually draws: filtered, sorted, boosted.
  List<Merchant> _shown(
    List<Merchant> all,
    Set<String>? inCuisine,
    Set<String> boosted, {
    required int minRatings,
  }) =>
      _sorted(_filtered(all, inCuisine), boosted, minRatings: minRatings);

  /// «الأعلى تقييماً», ranked on what the shop page is willing to show (B12).
  ///
  /// It sorted on the average alone, so one five-star rating outranked two hundred that
  /// averaged 4.8 — a ranking built on a number the shop's own page refuses to display
  /// below [minRatings]. A shop with too few ratings to show goes after every shop with
  /// enough, and among those the average decides; among the few-rated, the one rated by
  /// more people comes first.
  static List<Merchant> rankByRating(List<Merchant> merchants, {required int minRatings}) {
    final list = [...merchants];
    list.sort((a, b) {
      final aShown = a.ratingCount >= minRatings;
      final bShown = b.ratingCount >= minRatings;
      if (aShown != bShown) return aShown ? -1 : 1;
      if (!aShown) return b.ratingCount.compareTo(a.ratingCount);
      final byAvg = b.ratingAvg.compareTo(a.ratingAvg);
      return byAvg != 0 ? byAvg : b.ratingCount.compareTo(a.ratingCount);
    });
    return list;
  }

  /// Narrowed to the pressed cuisine, if one is pressed.
  List<Merchant> _filtered(List<Merchant> merchants, Set<String>? inCuisine) =>
      inCuisine == null
          ? merchants
          : merchants.where((m) => inCuisine.contains(m.id)).toList();

  List<Merchant> _sorted(
    List<Merchant> merchants,
    Set<String> boosted, {
    required int minRatings,
  }) {
    final list = topRated
        ? rankByRating(merchants, minRatings: minRatings)
        : [...merchants];
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
