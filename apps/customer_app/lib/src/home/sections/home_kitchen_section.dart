import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'section_header.dart';

/// Today's home-cooked meals.
///
/// The widest, warmest block on the screen, and deliberately not shaped like the
/// restaurant rows beside it — it is a different kind of thing, and it is the only thing
/// in this product nobody else in Edku offers. A restaurant list is table stakes.
///
/// Each card carries the two facts that actually decide whether someone taps: how many
/// portions are left, and when they can be collected.
class HomeKitchenSection extends ConsumerWidget {
  const HomeKitchenSection({super.key, required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Daily meals arrive in Phase 6. An empty section renders nothing rather than an
    // empty band — on a day with no home cooking, the screen should simply not mention it.
    const meals = <Object>[];
    if (meals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: section.titleAr.isEmpty ? 'أكل بيتي النهارده' : section.titleAr,
          onSeeAll: () {},
        ),
        SizedBox(
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            itemCount: meals.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) => const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// How much of a published meal is left.
///
/// A separate widget because the same meter appears on the card, on the meal screen and
/// in the merchant's own app, and the red state has to mean the same thing in all three.
class PortionsMeter extends StatelessWidget {
  const PortionsMeter({
    super.key,
    required this.remaining,
    required this.total,
  });

  final int remaining;
  final int total;

  /// Below this share of the batch, the meter turns to the danger colour.
  ///
  /// Scarcity is the honest signal here — a cook publishes fifteen portions and that is
  /// genuinely all there is — so it is shown rather than manufactured.
  static const scarceBelow = 0.25;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final fraction = total <= 0 ? 0.0 : (remaining / total).clamp(0.0, 1.0);
    final scarce = fraction > 0 && fraction <= scarceBelow;

    return ClipRRect(
      borderRadius: Radii.pillAll,
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 5,
        backgroundColor: colors.surface,
        valueColor: AlwaysStoppedAnimation(scarce ? colors.danger : colors.accent),
      ),
    );
  }
}
