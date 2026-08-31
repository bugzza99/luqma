import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../../merchant/open_merchant.dart';

/// One dish, small.
///
/// The home's "الأكتر طلباً" shelf used to be a second copy of the merchant list, sorted
/// by review count — a heading about food that showed shops, ranked by something that is
/// not ordering. What somebody wants from that heading is the food itself: a picture, a
/// name, a price, and a tap that lands in the shop that makes it.
///
/// It opens the merchant rather than adding to the basket. A dish carries options and a
/// minimum order and a shop that may be shut, and none of that fits on a tile this size —
/// so the tile is a way in, not a checkout.
class ItemTile extends ConsumerWidget {
  const ItemTile({super.key, required this.item, this.width = 150});

  final MenuItem item;

  /// Fixed, because the shelf scrolls sideways: tiles that size themselves to their
  /// content make a row whose rhythm changes with the length of a dish's name.
  final double width;

  static Key tileKey(String id) => Key('itemTile.$id');
  static const ratingKey = Key('itemTile.rating');
  static const shopKey = Key('itemTile.shop');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final shop = item.merchantName?.trim() ?? '';

    return SizedBox(
      width: width,
      child: InkWell(
        key: tileKey(item.id),
        onTap: () => openMerchant(context, item.merchantId),
        borderRadius: Radii.cardAll,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: Radii.cardAll,
            border: Border.all(color: colors.hairline),
            boxShadow: Elevations.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 4:3, and fixed before the picture arrives so the shelf is its final
              // height from the first frame.
              //
              // Not square: at 150 wide a square picture plus a name, a shop and a price
              // is taller than a shelf has any business being, and the section under it
              // gets pushed off the fold to make room for one row of food.
              AspectRatio(
                aspectRatio: 4 / 3,
                child: LuqmaImage(url: item.imageUrl, name: item.name),
              ),
              Padding(
                padding: const EdgeInsets.all(Space.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (shop.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        shop,
                        key: shopKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LuqmaType.caption
                            .copyWith(color: colors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: Space.xs),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            strings.price(item.price),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // `priceStrong`, not the accent: this sits on white below
                            // 18sp, where `#D67F2B` is 2.58:1 and fails.
                            style: LuqmaType.priceSmall
                                .copyWith(color: colors.price),
                          ),
                        ),
                        if (item.ratingCount > 0)
                          Row(
                            key: ratingKey,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: Sizes.iconSm - 4,
                                color: colors.accent,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                item.ratingAvg.toStringAsFixed(1),
                                style: LuqmaType.caption
                                    .copyWith(color: colors.textSecondary),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
