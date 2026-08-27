import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'merchant_card.dart';

import 'section_header.dart';

/// A list of merchants, ordered by whatever the section asked for.
///
/// One widget behind three section types — `merchantList`, `mostOrdered`, `topRated` —
/// because they differ only in sort order. Three near-identical widgets would be three
/// places to fix the same card.
class MerchantListSection extends ConsumerWidget {
  const MerchantListSection({
    super.key,
    required this.section,
    this.mostOrdered = false,
    this.topRated = false,
  });

  final HomeSection section;
  final bool mostOrdered;
  final bool topRated;

  String get _title {
    if (section.titleAr.isNotEmpty) return section.titleAr;
    if (mostOrdered) return 'الأكتر طلباً';
    if (topRated) return 'الأعلى تقييماً';
    return 'كل المطاعم';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchants = ref.watch(merchantsProvider(ref.watch(currentCityProvider)));
    // Nothing on the card says which merchant paid. Saying so would make the placement
    // worth less than it cost.
    final boosted = ref.watch(boostedMerchantsProvider);

    return switch (merchants) {
      // An error here costs this section, not the screen: the home is assembled from
      // several independent blocks, and one failing feed should not blank the others.
      // First, and on `hasError`: a stream that fails before it has ever emitted stays
      // `AsyncLoading`, and a skeleton that never resolves is worse than nothing.
      AsyncValue(hasError: true) => const SizedBox.shrink(),
      AsyncValue(hasValue: true, :final value?) when value.isEmpty =>
        const SizedBox.shrink(),
      AsyncValue(hasValue: true, :final value?) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: _title),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: Column(
                children: [
                  for (final merchant in _sorted(value, boosted)) ...[
                    MerchantCard(merchant: merchant),
                    const SizedBox(height: Space.sm),
                  ],
                ],
              ),
            ),
          ],
        ),
          _ => const _Skeleton(),
};
  }

  List<Merchant> _sorted(List<Merchant> merchants, Set<String> boosted) {
    final list = [...merchants];
    if (topRated) {
      list.sort((a, b) => b.ratingAvg.compareTo(a.ratingAvg));
    } else if (mostOrdered) {
      // Standing in for an order count, which arrives with the first real orders.
      list.sort((a, b) => b.ratingCount.compareTo(a.ratingCount));
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
              // A card is a 16:9 picture plus two lines; the skeleton matches it.
              height: 230,
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
