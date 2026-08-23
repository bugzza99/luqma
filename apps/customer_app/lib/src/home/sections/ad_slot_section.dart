import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

/// A promotion slot on the home screen.
///
/// The slot *is* the placement: which promotions can appear here, how many rotate, and
/// how fast, are all read off this section's own parameters. That is why there is no
/// separate placements collection — one fewer place for the two to disagree.
///
/// Every render mode occupies the same 3:1 box, so the screen never jumps as banners
/// rotate. That constraint is enforced again on upload, where a banner that is not 3:1
/// is refused outright.
class AdSlotSection extends ConsumerWidget {
  const AdSlotSection({super.key, required this.section});

  final HomeSection section;

  int get _maxAds => switch (section.params['maxAds']) {
        final int n when n > 0 => n,
        _ => 1,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Promotions arrive in Phase 8. Until then the slot renders nothing at all rather
    // than a placeholder — an empty band on the home screen reads as a broken image, and
    // a merchant who has not bought a banner should cost the customer no space.
    const promotions = <Promotion>[];

    if (promotions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: AspectRatio(
        aspectRatio: Sizes.bannerAspect,
        child: PageView(
          children: [
            for (final promotion in promotions.take(_maxAds))
              _Banner(promotion: promotion),
          ],
        ),
      ),
    );
  }
}

/// Placeholder for the promotion model, which lands with the rest of Phase 8.
class Promotion {
  const Promotion();
}

class _Banner extends StatelessWidget {
  const _Banner({required this.promotion});

  final Promotion promotion;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
