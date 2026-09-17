import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// «موثّق» beside a shop's name, when its active plan includes the badge.
///
/// Decided 2026-09-17. It means something because a person stands behind it: a plan is
/// activated by the owner of the platform after speaking to the shop and seeing the money
/// arrive. Draws nothing while the perks are loading or could not be read.
class VerifiedBadge extends ConsumerWidget {
  const VerifiedBadge({super.key, required this.merchantId});

  final String merchantId;

  static const badgeKey = Key('merchant.verified');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final verified = ref.watch(merchantPerksProvider).value?[merchantId]?.verified ?? false;
    if (!verified) return const SizedBox.shrink();
    final colors = Theme.of(context).luqma;
    return Row(
      key: badgeKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: Space.xs),
        Icon(Icons.verified, size: Sizes.iconSm, color: colors.success),
        const SizedBox(width: 2),
        Text(
          'موثّق',
          style: LuqmaType.caption.copyWith(color: colors.success, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
