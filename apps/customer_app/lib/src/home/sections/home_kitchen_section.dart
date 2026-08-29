import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../../kitchen/open_meal.dart';
import '../../shell/customer_tab.dart';
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
    final meals = ref.watch(todaysMealsProvider).value ?? const <DailyMeal>[];

    // On a day with no home cooking the screen should simply not mention it. An empty
    // band under a heading reads as something broken. A failed read lands here too, and
    // that is deliberate: the home is several independent blocks, and one that cannot
    // load should cost itself, not the screen.
    if (meals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: section.titleAr.isEmpty ? 'أكل بيتي النهارده' : section.titleAr,
        ),
        SizedBox(
          height: 268,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            itemCount: meals.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) => MealCard(meal: meals[i]),
          ),
        ),
      ],
    );
  }
}

/// One meal, as it appears in the band.
///
/// Wider and taller than a restaurant row on purpose: it is a different kind of thing,
/// and it is the only thing in this product nobody else in Edku offers.
class MealCard extends ConsumerWidget {
  const MealCard({super.key, required this.meal});

  final DailyMeal meal;

  static Key cardKey(String id) => Key('meal.card.$id');
  static Key portionsKey(String id) => Key('meal.portions.$id');
  static Key windowKey(String id) => Key('meal.window.$id');
  static Key soldOutKey(String id) => Key('meal.soldOut.$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);

    return SizedBox(
      width: 236,
      child: InkWell(
        key: cardKey(meal.id),
        onTap: () => openMeal(
          context,
          meal.id,
          // The registry builds this section from a server-chosen string and has no
          // callbacks to hand it, so the account tab is reached through the provider
          // the shell now reads.
          onSignIn: () => ref.read(customerTabProvider.notifier).goToAccount(),
        ),
        borderRadius: Radii.cardAll,
        child: Container(
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: Radii.cardAll,
            border: Border.all(color: colors.hairline),
            boxShadow: Elevations.card,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    height: 116,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: const BorderRadius.vertical(top: Radii.card),
                    ),
                  ),
                  if (meal.isSoldOut)
                    Positioned.fill(
                      child: Container(
                        key: soldOutKey(meal.id),
                        decoration: BoxDecoration(
                          color: colors.scrim,
                          borderRadius: const BorderRadius.vertical(top: Radii.card),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'خلص النهارده',
                          style: LuqmaType.bodyStrong.copyWith(color: colors.onBrand),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      // When it can be collected. Half of what decides a tap: a window
                      // somebody cannot make is a meal they should not reserve.
                      key: windowKey(meal.id),
                      'الاستلام ${formatWindow(meal)}',
                      style: LuqmaType.caption.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: Space.sm),
                    Padding(
                      key: portionsKey(meal.id),
                      padding: const EdgeInsets.only(bottom: Space.xs),
                      child: PortionsMeter(
                        remaining: meal.remainingOrZero,
                        total: meal.totalQty,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            strings.portionsLeft(meal.remainingOrZero),
                            style: LuqmaType.caption.copyWith(
                              color: meal.isSoldOut
                                  ? colors.danger
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          strings.price(meal.price),
                          style: LuqmaType.priceSmall.copyWith(color: colors.price),
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

/// The collection window as a person would say it: `1:00 — 4:00`.
///
/// Minutes from midnight are what the model stores, because they sort and survive a
/// timezone change; nobody reads them.
String formatWindow(DailyMeal meal) {
  String clock(int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final display = hour % 12 == 0 ? 12 : hour % 12;
    return '$display:${minute.toString().padLeft(2, '0')}';
  }

  return '${clock(meal.pickupWindowStart)} — ${clock(meal.pickupWindowEnd)}';
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
