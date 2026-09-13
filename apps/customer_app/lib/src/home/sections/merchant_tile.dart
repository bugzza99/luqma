import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../../merchant/open_merchant.dart';

/// One merchant, as a full-width row.
///
/// It was half a phone wide and two across, on the reasoning that six shops on a screen
/// beat two. The design answers that differently and better: a compact **row** puts six
/// shops on the screen *and* gives each one a whole line to say what it is, where a
/// half-width tile had to choose between the description and the rating and usually
/// showed a truncated one of each.
///
/// What a customer chooses on, in reading order: whose shop it is, what kind of food and
/// how long it takes, and whether it is any good. The rating sits at the end of the row
/// because it is the tie-breaker, not the headline — and because a column of numbers down
/// one edge is scannable in a way the same numbers scattered mid-tile are not.
///
/// The logo rather than the cover: at 52 a photograph of a shopfront is a smear, and a
/// logo is what a regular recognises without reading.
class MerchantTile extends ConsumerWidget {
  const MerchantTile({super.key, required this.merchant, this.onTap});

  final Merchant merchant;
  final VoidCallback? onTap;

  static Key tileKey(String id) => Key('merchantTile.$id');
  static const ratingKey = Key('merchantTile.rating');
  static const closedKey = Key('merchantTile.closed');
  static const descriptionKey = Key('merchantTile.description');

  /// The artboard's thumbnail. Not a [Space] step — it is an image size chosen against
  /// the row's height, the way [Sizes] holds the other measured ones.
  static const _thumb = 52.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final config = ref.watch(appConfigProvider);
    final open = merchant.acceptsOrdersAt(ref.watch(clockProvider)());
    final description = merchant.description?.trim() ?? '';

    // The whole row dims, not just the logo. A shut shop is one thing the eye should skip
    // over, and dimming a single element inside a row at full strength reads as an image
    // that failed to load rather than as a shop that is closed.
    return Opacity(
      opacity: open ? 1 : 0.72,
      child: LuqmaPressable(
        key: tileKey(merchant.id),
        onTap: onTap ?? () => openMerchant(context, merchant.id),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: Radii.cardAll,
            border: Border.all(color: colors.hairline),
            boxShadow: Elevations.card,
          ),
          padding: const EdgeInsets.all(Space.sm + 2),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: Radii.fieldAll,
                child: SizedBox(
                  width: _thumb,
                  height: _thumb,
                  child: LuqmaImage(
                    url: merchant.logoUrl ?? merchant.coverUrl,
                    name: merchant.name,
                  ),
                ),
              ),
              const SizedBox(width: Space.md - 1),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      merchant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    // Closed replaces the description rather than joining it. The one
                    // thing worth knowing about a shut shop is when it opens; its menu
                    // description is not that thing, and two lines of grey under a shop
                    // nobody can order from is the row earning attention it should not.
                    if (!open)
                      Text(
                        'مقفول دلوقتي',
                        key: closedKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.danger),
                      )
                    else if (description.isNotEmpty)
                      Text(
                        description,
                        key: descriptionKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                  ],
                ),
              ),
              // The rating keeps its place at the end of every row whether or not the
              // shop has one, so the column of numbers stays a column.
              if (open) ...[
                const SizedBox(width: Space.sm),
                if (merchant.ratingCount >= config.minRatingsToShow)
                  Row(
                    key: ratingKey,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star_rounded,
                        size: Sizes.iconSm - 3,
                        // `price`, not `accent`: the star sits on white beside 13sp
                        // digits, and orange only clears contrast on white from 18sp.
                        color: colors.price,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        merchant.ratingAvg.toStringAsFixed(1),
                        style: LuqmaType.priceSmall
                            .copyWith(color: colors.price),
                      ),
                    ],
                  )
                else
                  Text(
                    // Not an empty gap: a row with nothing where the stars go reads as a
                    // rating that failed to load rather than a shop nobody has rated.
                    'جديد',
                    style:
                        LuqmaType.caption.copyWith(color: colors.textSecondary),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
