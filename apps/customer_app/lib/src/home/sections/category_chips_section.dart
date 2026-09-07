import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../selected_cuisine.dart';

/// The cuisines, as a scrolling row of pills across the top of the home.
///
/// Edku will have on the order of thirty merchants — not enough to fill a tab of its own,
/// which is why this ended up inside the home screen. Being a section rather than fixed
/// chrome also means the owner can move it or hide it like anything else here.
///
/// The first pill is "الكل": pressing it clears the filter, and it reads as pressed
/// whenever nothing else is. Every other pill is one cuisine, and pressing the pressed one
/// releases it — the same gesture in and out, so nobody hunts for a way back to "all".
class CategoryChipsSection extends ConsumerWidget {
  const CategoryChipsSection({super.key, required this.section});

  final HomeSection section;

  static const allChipKey = Key('cuisines.all');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuisines = ref.watch(cuisinesProvider);
    final selected = ref.watch(selectedCuisineProvider);

    return LuqmaAsyncView(
      value: cuisines,
      empty: const SizedBox.shrink(),
      isEmpty: (value) => value.isEmpty,
      loading: const _Skeleton(),
      builder: (context, value) => SizedBox(
        height: Sizes.minTarget,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          // One extra for the "الكل" pill that sits before the cuisines.
          itemCount: value.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
          itemBuilder: (context, i) {
            if (i == 0) {
              return _Chip(
                key: CategoryChipsSection.allChipKey,
                label: 'الكل',
                selected: selected == null,
                onTap: () =>
                    ref.read(selectedCuisineProvider.notifier).select(null),
              );
            }
            final cuisine = value[i - 1];
            return _Chip(
              key: ValueKey('cuisine.${cuisine.id}'),
              label: cuisine.name,
              selected: cuisine.id == selected,
              onTap: () =>
                  ref.read(selectedCuisineProvider.notifier).toggle(cuisine.id),
            );
          },
        ),
      ),
    );
  }
}

/// One pill.
///
/// Selecting animates the fill and the ink rather than rebuilding into place —
/// `AnimatedContainer` and `AnimatedDefaultTextStyle` over `Motion.quick`, which
/// `Motion.of` drops to zero under reduced motion so the change simply appears.
class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final duration = Motion.of(context, Motion.quick);

    return LuqmaPressable(
      onTap: onTap,
      selected: selected,
      // The pill is shorter than the row it sits in; the row height carries the touch
      // target, so a thin pill is still 48 tall to the finger.
      child: Center(
        widthFactor: 1,
        child: AnimatedContainer(
          duration: duration,
          curve: Motion.emphasis,
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            // Burgundy, not the accent. Orange is reserved for prices, offers and
            // ratings — the moment it also means "selected" it stops meaning value
            // anywhere, and every price on every screen loses its pull.
            color: selected ? colors.brand : colors.card,
            borderRadius: Radii.pillAll,
            border: Border.all(
              color: selected ? colors.brand : colors.border,
            ),
          ),
          child: AnimatedDefaultTextStyle(
            duration: duration,
            curve: Motion.emphasis,
            style: theme.textTheme.bodySmall!.copyWith(
              color: selected ? colors.onBrand : colors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
            ),
            child: Text(label, maxLines: 1),
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    return SizedBox(
      height: Sizes.minTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: 5,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (_, _) => Center(
          widthFactor: 1,
          child: Container(
            width: 64,
            height: Space.xxl,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: Radii.pillAll,
            ),
          ),
        ),
      ),
    );
  }
}
