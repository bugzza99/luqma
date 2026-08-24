import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../../merchant/open_merchant.dart';
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
                    MerchantRow(merchant: merchant),
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

/// One merchant, as the customer meets it.
class MerchantRow extends ConsumerWidget {
  const MerchantRow({super.key, required this.merchant, this.onTap});

  /// Overrides where the row goes. Left null it opens the merchant, which is what every
  /// list on the home wants.

  final Merchant merchant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final config = ref.watch(appConfigProvider);
    final open = merchant.acceptsOrdersAt(DateTime.now());

    return Opacity(
      // A closed merchant stays on the list, dimmed. Hiding it would leave the customer
      // wondering where their usual place went, and it still tells them when it reopens.
      opacity: open ? 1 : 0.6,
      child: InkWell(
        onTap: onTap ?? () => openMerchant(context, merchant.id),
        borderRadius: Radii.cardAll,
        child: Container(
          padding: const EdgeInsets.all(Space.sm + 2),
          constraints: const BoxConstraints(minHeight: Sizes.minTarget + 24),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: Radii.cardAll,
            border: Border.all(color: colors.hairline),
            boxShadow: Elevations.card,
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: Radii.imageAll,
                ),
              ),
              const SizedBox(width: Space.md - 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(merchant.name, style: theme.textTheme.titleMedium),
                    Text(
                      open ? _openSubtitle() : 'مقفول دلوقتي',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: open ? colors.textSecondary : colors.danger,
                        fontWeight: open ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Ratings stay hidden until there are enough of them: one bad review must
              // not sink a new merchant in a town where everyone knows everyone.
              if (merchant.ratingCount >= config.minRatingsToShow)
                _Rating(value: merchant.ratingAvg),
            ],
          ),
        ),
      ),
    );
  }

  String _openSubtitle() =>
      merchant.type == MerchantType.homeKitchen ? 'أكل بيتي' : 'مطعم';
}

class _Rating extends StatelessWidget {
  const _Rating({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: Sizes.iconSm - 3, color: colors.price),
        const SizedBox(width: Space.xs - 1),
        Text(
          value.toStringAsFixed(1),
          style: LuqmaType.priceSmall.copyWith(color: colors.price),
        ),
      ],
    );
  }
}

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
              height: 74,
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
