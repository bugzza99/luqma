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
              return LuqmaChip(
                key: CategoryChipsSection.allChipKey,
                label: 'الكل',
                selected: selected == null,
                onTap: () =>
                    ref.read(selectedCuisineProvider.notifier).select(null),
              );
            }
            final cuisine = value[i - 1];
            return LuqmaChip(
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
