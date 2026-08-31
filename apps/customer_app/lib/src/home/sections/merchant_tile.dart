import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../../merchant/open_merchant.dart';

/// One merchant, small enough that two fit across a phone.
///
/// The full-width [MerchantCard] gives a shop a 16:9 photograph and most of the fold, so
/// a customer scrolling the home sees two shops before the screen ends and has to scroll
/// to learn there are more. Half-width means six, which is the difference between a list
/// somebody browses and a list somebody gives up on.
///
/// What survives the shrink is what a customer chooses on: whose shop it is (the logo and
/// the name), whether it is any good (the stars), and what kind of food it is (one line
/// the merchant writes). The cover photograph does not — at this size it is a smear, and
/// a logo is the thing a regular customer recognises without reading.
class MerchantTile extends ConsumerWidget {
  const MerchantTile({super.key, required this.merchant, this.onTap});

  final Merchant merchant;
  final VoidCallback? onTap;

  static Key tileKey(String id) => Key('merchantTile.$id');
  static const ratingKey = Key('merchantTile.rating');
  static const closedKey = Key('merchantTile.closed');
  static const descriptionKey = Key('merchantTile.description');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final config = ref.watch(appConfigProvider);
    final open = merchant.acceptsOrdersAt(ref.watch(clockProvider)());
    final description = merchant.description?.trim() ?? '';

    return InkWell(
      key: tileKey(merchant.id),
      onTap: onTap ?? () => openMerchant(context, merchant.id),
      borderRadius: Radii.cardAll,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
          boxShadow: Elevations.card,
        ),
        padding: const EdgeInsets.all(Space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Square and clipped to the image radius rather than a circle: a shop's
                // logo is usually a rectangle with words in it, and a circle crops the
                // words off — which is the one thing on the tile that names the shop
                // twice.
                Opacity(
                  opacity: open ? 1 : 0.45,
                  child: ClipRRect(
                    borderRadius: Radii.imageAll,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: LuqmaImage(
                        url: merchant.logoUrl ?? merchant.coverUrl,
                        name: merchant.name,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchant.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: Space.xs - 2),
                      if (merchant.ratingCount >= config.minRatingsToShow)
                        Row(
                          key: ratingKey,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: Sizes.iconSm - 4,
                              // On white, not on the orange pill: `#D67F2B` clears
                              // contrast on white only from 18sp, and this is smaller.
                              color: colors.accent,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              merchant.ratingAvg.toStringAsFixed(1),
                              style: LuqmaType.priceSmall
                                  .copyWith(color: colors.price),
                            ),
                          ],
                        )
                      else
                        Text(
                          // Not an empty gap: a tile with nothing where the stars go
                          // reads as a shop whose rating failed to load.
                          'جديد',
                          style: LuqmaType.caption
                              .copyWith(color: colors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              Text(
                description,
                key: descriptionKey,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ],
            if (!open) ...[
              const SizedBox(height: Space.sm),
              Text(
                'مقفول دلوقتي',
                key: closedKey,
                style: theme.textTheme.bodySmall?.copyWith(color: colors.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
