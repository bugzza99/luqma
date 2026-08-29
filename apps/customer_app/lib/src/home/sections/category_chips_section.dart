import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../selected_cuisine.dart';

/// The cuisines, as a scrolling row of circles across the top of the home.
///
/// Edku will have on the order of thirty merchants — not enough to fill a tab of its
/// own, which is why this ended up inside the home screen. Being a section rather than
/// fixed chrome also means the owner can move it or hide it like anything else here.
///
/// Until now it rendered four Arabic words compiled into the app and filtered nothing.
class CategoryChipsSection extends ConsumerWidget {
  const CategoryChipsSection({super.key, required this.section});

  final HomeSection section;

  static const circleKey = Key('cuisines.circle');

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
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            itemCount: value.length,
            separatorBuilder: (_, _) => const SizedBox(width: Space.md),
            itemBuilder: (context, i) => _Circle(
              cuisine: value[i],
              selected: value[i].id == selected,
              onTap: () =>
                  ref.read(selectedCuisineProvider.notifier).toggle(value[i].id),
            ),
          ),
        )
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({
    required this.cuisine,
    required this.selected,
    required this.onTap,
  });

  final Cuisine cuisine;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: CategoryChipsSection.circleKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(40),
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Burgundy, not the accent. Orange is reserved for prices, offers and
                  // ratings — the moment it also means "selected" it stops meaning value
                  // anywhere, and every price on every screen loses its pull.
                  border: selected
                      ? Border.all(color: colors.brand, width: 3)
                      : null,
                ),
                child: ClipOval(
                  child: LuqmaImage(url: cuisine.imageUrl, name: cuisine.name),
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                cuisine.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: selected ? colors.textPrimary : colors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
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
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: Space.md),
        itemBuilder: (_, _) => Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(shape: BoxShape.circle, color: colors.surface),
        ),
      ),
    );
  }
}
