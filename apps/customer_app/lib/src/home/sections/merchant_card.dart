import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../../merchant/open_merchant.dart';

/// One merchant, as the customer meets it.
///
/// The card the whole home screen is made of, so what it says and what it leaves out is
/// most of what the app feels like. Four things: the picture, how good it is, how long
/// the kitchen takes, and what delivery costs.
///
/// Deliberately not a fifth. The minimum order is enforced in the basket and stated on
/// the merchant's own screen — four numbers on a card this size is noise, and the card
/// is for choosing rather than for the terms.
class MerchantCard extends ConsumerWidget {
  const MerchantCard({super.key, required this.merchant, this.onTap});

  final Merchant merchant;

  /// Overrides where the card goes. Left null it opens the merchant, which is what
  /// every list on the home wants.
  final VoidCallback? onTap;

  static const ratingKey = Key('merchantCard.rating');
  static const deliveryKey = Key('merchantCard.delivery');
  static const closedKey = Key('merchantCard.closed');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final config = ref.watch(appConfigProvider);
    // Never DateTime.now(): whether a shop is open depends on the hour, and a widget
    // that reads the wall clock can only be tested by waiting for the right one.
    final open = merchant.acceptsOrdersAt(ref.watch(clockProvider)());

    return InkWell(
      onTap: onTap ?? () => openMerchant(context, merchant.id),
      borderRadius: Radii.cardAll,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          // White with a soft shadow. Surface is 1.24:1 against cream — a card painted
          // in it is a card nobody can find the edge of.
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
          boxShadow: Elevations.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                // A fixed ratio, so the card is its final height from the first frame.
                // A picture that lands and pushes everything down moves the row somebody
                // is already reaching for.
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Opacity(
                    opacity: open ? 1 : 0.45,
                    // The shop's own photograph, once an admin has approved it. This was
                    // a literal `null` — so the media pipeline ran end to end, the owner
                    // approved covers in the queue, and every card in the city still drew
                    // the tinted mark because nothing ever asked for the address.
                    child: LuqmaImage(url: merchant.coverUrl, name: merchant.name),
                  ),
                ),
                if (merchant.ratingCount >= config.minRatingsToShow)
                  Positioned(
                    top: Space.sm,
                    right: Space.sm,
                    child: _RatingPill(value: merchant.ratingAvg),
                  ),
                // A closed shop stays on the list, dimmed and labelled. Hiding it leaves
                // the customer wondering where their usual place went.
                if (!open)
                  Positioned(
                    bottom: Space.sm,
                    right: Space.sm,
                    child: Container(
                      key: closedKey,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.sm,
                        vertical: Space.xs,
                      ),
                      decoration: BoxDecoration(
                        color: colors.textPrimary,
                        borderRadius: Radii.imageAll,
                      ),
                      child: Text(
                        'مقفول دلوقتي',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.background),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(Space.md - 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(merchant.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: Space.xs),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: Sizes.iconSm - 3,
                        color: colors.textSecondary,
                      ),
                      const SizedBox(width: Space.xs),
                      Text(
                        '${merchant.prepMinutes} دقيقة تقريباً',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.textSecondary),
                      ),
                      const SizedBox(width: Space.sm),
                      Text(
                        '·',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.border),
                      ),
                      const SizedBox(width: Space.sm),
                      Flexible(child: _Delivery(merchant: merchant)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What delivery costs, or that it costs nothing.
///
/// Free delivery is an offer, so it may wear the accent — but at this size it has to be
/// `priceStrong`: `#D67F2B` clears contrast on white only at 18sp and above, and this
/// line is fifteen.
class _Delivery extends ConsumerWidget {
  const _Delivery({required this.merchant});

  final Merchant merchant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final fee = merchant.deliveryFeeOverride;

    if (fee == 0) {
      return Text(
        'توصيل مجاني',
        key: MerchantCard.deliveryKey,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: colors.price, fontWeight: FontWeight.w700),
      );
    }

    return Text(
      fee == null ? 'التوصيل حسب المنطقة' : 'التوصيل ${strings.price(fee)}',
      key: MerchantCard.deliveryKey,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
    );
  }
}

/// The rating, over the photograph.
///
/// Orange belongs here — ratings are one of the four things the accent is reserved for.
/// The text on it is **dark**, never white: white on `#D67F2B` is 3.03:1 and fails, and
/// it is the single most common mistake this palette invites.
class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return Container(
      key: MerchantCard.ratingKey,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: Radii.imageAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: Sizes.iconSm - 3, color: colors.onAccent),
          const SizedBox(width: Space.xs - 1),
          Text(
            value.toStringAsFixed(1),
            style: LuqmaType.priceSmall.copyWith(color: colors.onAccent),
          ),
        ],
      ),
    );
  }
}
