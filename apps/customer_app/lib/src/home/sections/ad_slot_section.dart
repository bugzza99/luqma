import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../../merchant/open_merchant.dart';

/// A promotion slot on the home screen.
///
/// The slot *is* the placement: which promotions can appear here and how many rotate are
/// read off this section's own parameters. That is why there is no separate placements
/// collection — one fewer place for the two to disagree.
///
/// Every render mode occupies the same 3:1 box, so the screen never jumps as banners
/// rotate. The same ratio is enforced on upload, where a banner that is not 3:1 is
/// refused outright.
class AdSlotSection extends ConsumerWidget {
  const AdSlotSection({super.key, required this.section});

  final HomeSection section;

  static Key slotKey(String sectionKey) => Key('adSlot.$sectionKey');
  static Key bannerKey(String promotionId) => Key('adSlot.banner.$promotionId');

  int get _maxAds => switch (section.params['maxAds']) {
        final int n when n > 0 => n,
        _ => 1,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(livePromotionsProvider).value ?? const <Promotion>[];

    final banners = live
        .where((p) =>
            p.channel == PromotionChannel.homeBanner &&
            p.belongsIn(section.key) &&
            // A banner promising a picture and carrying none renders as a broken box on
            // the home screen of every customer in the city.
            p.canRender)
        .take(_maxAds)
        .toList();

    // Nothing sold means no space taken. An empty band under nothing reads as a broken
    // image, and a customer should not pay attention for a merchant who paid nothing.
    // A failed read lands here too, deliberately: the home is assembled from independent
    // blocks, and one that cannot load should cost itself and not the restaurants.
    if (banners.isEmpty) return const SizedBox.shrink();

    return Padding(
      key: slotKey(section.key),
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: AspectRatio(
        aspectRatio: Sizes.bannerAspect,
        child: banners.length == 1
            ? _Banner(promotion: banners.first)
            : PageView(
                children: [
                  for (final promotion in banners) _Banner(promotion: promotion),
                ],
              ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.promotion});

  final Promotion promotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return InkWell(
      key: AdSlotSection.bannerKey(promotion.id),
      onTap: () => openMerchant(context, promotion.merchantId),
      borderRadius: Radii.cardAll,
      child: ClipRRect(
        borderRadius: Radii.cardAll,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The gradient is the fallback as well as the text mode's background: a
            // merchant with no artwork gets a banner that still looks made on purpose,
            // which is the whole commercial point of the text mode.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [colors.brand, colors.brandPressed],
                ),
              ),
            ),
            if (promotion.renderMode != PromotionRender.text)
              // The image itself arrives with Storage; until then the gradient stands in
              // rather than a grey box, so the slot never looks broken.
              const SizedBox.shrink(),
            if (promotion.renderMode == PromotionRender.imageWithText)
              DecoratedBox(
                decoration: BoxDecoration(color: colors.scrim),
              ),
            if (promotion.renderMode != PromotionRender.image)
              Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      promotion.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colors.onBrand,
                      ),
                    ),
                    if (promotion.body.isNotEmpty) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        promotion.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onBrand.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
