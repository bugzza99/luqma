import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import 'section_registry.dart';

/// The customer's home.
///
/// Only two things here are fixed: the bar and the search field. Everything below them is
/// arranged by the owner from AdminApp — which sections, in what order, with what
/// parameters — and this screen simply renders that arrangement through the registry.
///
/// The chrome stays put no matter what the arrangement says, so a home that is empty,
/// misconfigured, or still loading is never a blank screen with no way out of it.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const searchKey = Key('home.search');
  static const emptyKey = Key('home.empty');
  static const zoneKey = Key('home.zone');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(homeSectionsProvider);

    return Scaffold(
      appBar: const _HomeBar(),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(homeSectionsProvider),
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: Space.md + 2)),
            const SliverToBoxAdapter(child: _SearchField()),
            const SliverToBoxAdapter(child: SizedBox(height: Space.xl - 4)),
            switch (sections) {
              AsyncLoading() => const SliverToBoxAdapter(child: _Loading()),
              // One failed read of the arrangement should not hide the search field or
              // the bar — the customer can still look for what they wanted.
              AsyncError(:final error) =>
                SliverToBoxAdapter(child: _Error(failure: error)),
              AsyncData(:final value) => _Sections(sections: value),
            },
            const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
          ],
        ),
      ),
    );
  }
}

class _Sections extends StatelessWidget {
  const _Sections({required this.sections});

  final List<HomeSection> sections;

  @override
  Widget build(BuildContext context) {
    final plan = HomeSectionRegistry.plan(sections);

    if (plan.isEmpty) {
      return const SliverToBoxAdapter(child: _Empty());
    }

    return SliverList.separated(
      itemCount: plan.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.xl - 4),
      itemBuilder: (context, i) =>
          HomeSectionRegistry.build(plan[i]) ?? const SizedBox.shrink(),
    );
  }
}

class _HomeBar extends ConsumerWidget implements PreferredSizeWidget {
  const _HomeBar();

  @override
  Size get preferredSize => const Size.fromHeight(Sizes.appBarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    return AppBar(
      // Drawn from the vector lockup, never typed: Lemonada is not a bundled font, so a
      // Text widget here would silently render the name in the wrong face.
      title: const LuqmaLockup.appBar(),
      titleSpacing: Space.gutter,
      actions: [
        // The delivery zone belongs in the bar because it decides the delivery fee and
        // which merchants can even take the order — it is not a setting, it is context.
        TextButton.icon(
          key: HomeScreen.zoneKey,
          onPressed: () {},
          icon: Icon(Icons.expand_more_rounded, size: 18, color: colors.onBrand),
          label: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${strings.deliveringTo} ',
                  style: LuqmaType.caption.copyWith(
                    color: colors.onBrand.withValues(alpha: 0.85),
                  ),
                ),
                TextSpan(
                  text: 'المعمورة',
                  style: LuqmaType.bodySmall.copyWith(
                    color: colors.onBrand,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: Space.sm),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: TextField(
        key: HomeScreen.searchKey,
        readOnly: true,
        onTap: () {},
        decoration: InputDecoration(
          hintText: strings.searchHint,
          prefixIcon: Icon(Icons.search_rounded, color: colors.textSecondary),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: Space.md),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++) ...[
            Container(
              height: 74,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: Radii.cardAll,
              ),
            ),
            const SizedBox(height: Space.sm),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: HomeScreen.emptyKey,
      padding: const EdgeInsets.all(Space.xxl),
      child: Center(
        child: Text(
          'لسه مفيش مطاعم هنا.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.luqma.textSecondary),
        ),
      ),
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.failure});

  final Object failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = LuqmaStrings.of(context);

    return Padding(
      padding: const EdgeInsets.all(Space.xxl),
      child: Center(
        child: Text(
          switch (failure) {
            OfflineFailure() => strings.errorOffline,
            PermissionFailure() => strings.errorPermission,
            _ => strings.errorUnknown,
          },
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.luqma.textSecondary),
        ),
      ),
    );
  }
}
