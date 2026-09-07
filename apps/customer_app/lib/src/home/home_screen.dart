import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../address/address_list_screen.dart';
import '../search/search_screen.dart';
import '../shell/customer_tab.dart';
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
            SliverToBoxAdapter(
              // The skeleton, an error and the arranged sections cross-fade into one
              // another rather than snapping. `Motion.of` collapses the duration to zero
              // under reduced motion, so for anybody who asked for that it is a plain
              // swap.
              child: AnimatedSwitcher(
                duration: Motion.of(context, Motion.sheet),
                switchInCurve: Motion.enter,
                switchOutCurve: Motion.exit,
                // Top-aligned rather than the default centre: the outgoing skeleton is
                // short and the incoming sections are tall, and a centred overlap slides
                // the skeleton down as it fades.
                layoutBuilder: (currentChild, previousChildren) => Stack(
                  alignment: AlignmentDirectional.topStart,
                  children: [...previousChildren, ?currentChild],
                ),
                child: switch (sections) {
                  // One failed read of the arrangement should not hide the search field
                  // or the bar — the customer can still look for what they wanted. It
                  // comes first and matches on `hasError`, not on the `AsyncError` type:
                  // a stream that fails before it has ever emitted stays `AsyncLoading`
                  // with the error hanging off it, so a type match never fires.
                  AsyncValue(hasError: true, :final error?) => LuqmaErrorView(
                      key: const ValueKey('home.error'),
                      failure: error,
                      onRetry: () => ref.invalidate(homeSectionsProvider),
                    ),
                  AsyncValue(hasValue: true, :final value?) => _Sections(
                      key: const ValueKey('home.sections'),
                      sections: value,
                    ),
                  _ => const _Loading(key: ValueKey('home.loading')),
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
          ],
        ),
      ),
    );
  }
}

class _Sections extends StatelessWidget {
  const _Sections({super.key, required this.sections});

  final List<HomeSection> sections;

  @override
  Widget build(BuildContext context) {
    final plan = HomeSectionRegistry.plan(sections);

    if (plan.isEmpty) {
      return const LuqmaEmptyView(
        key: HomeScreen.emptyKey,
        message: 'لسه مفيش مطاعم هنا.',
      );
    }

    return Column(
      children: [
        for (var i = 0; i < plan.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.xl - 4),
          // Each section settles into place on its own short delay, capped at six so a
          // long home still lands as an arrival rather than a wait. `LuqmaEntrance` is a
          // no-op under reduced motion.
          LuqmaEntrance(
            index: i,
            child: HomeSectionRegistry.build(plan[i]) ?? const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }
}

class _HomeBar extends ConsumerWidget implements PreferredSizeWidget {
  const _HomeBar();

  @override
  Size get preferredSize => const Size.fromHeight(Sizes.appBarHeight);

  /// The zone of the address an order would actually go to.
  ///
  /// The address carries a `zoneId`; the name is on the zone. A zone the list does not
  /// have — deleted, or not loaded yet — reads as unknown rather than as an id, which is
  /// not a place anybody recognises.
  static String? _zoneName(WidgetRef ref) {
    final address = ref.watch(chosenAddressProvider).value;
    if (address == null) return null;

    final zones = ref.watch(zonesProvider).value ?? const <Zone>[];
    return zones.where((z) => z.id == address.zoneId).firstOrNull?.name;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);
    // Null covers signed out, no address saved, and a zone list that has not arrived —
    // all three are honestly "we do not know yet", and the label asks rather than
    // asserts. Guessing here is what produced the compiled-in answer this replaced.
    final zone = _zoneName(ref);

    return AppBar(
      // Drawn from the vector lockup, never typed: Lemonada is not a bundled font, so a
      // Text widget here would silently render the name in the wrong face.
      title: const LuqmaLockup.appBar(),
      titleSpacing: Space.gutter,
      actions: [
        // The delivery zone belongs in the bar because it decides the delivery fee and
        // which merchants can even take the order — it is not a setting, it is context.
        //
        // It read `'المعمورة'`, compiled in, above an `onPressed: () {}`. A control that
        // states the wrong fact and refuses to be corrected is worse than no control:
        // "المعمورة" is not even a zone of Edku, so every customer in the city was told
        // their food was going somewhere else and had no way to say otherwise.
        TextButton.icon(
          key: HomeScreen.zoneKey,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AddressListScreen(
                onSignIn: () {
                  Navigator.of(context).pop();
                  ref.read(customerTabProvider.notifier).goToAccount();
                },
              ),
            ),
          ),
          icon: Icon(Icons.expand_more_rounded,
              size: Sizes.iconSm, color: colors.onBrand),
          label: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '${zone == null ? strings.chooseZone : strings.deliveringTo} ',
                  style: LuqmaType.caption.copyWith(
                    color: colors.onBrand.withValues(alpha: 0.85),
                  ),
                ),
                if (zone != null)
                  TextSpan(
                    text: zone,
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
        // Read-only on purpose: this is a button that looks like a field. Typing happens
        // on the search screen, which owns the query, the debounce and the results.
        readOnly: true,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
        ),
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

/// A skeleton of the home — a pill row, a banner, then a couple of cards — so the swap to
/// real content reads as the page arriving rather than as one layout replacing another.
class _Loading extends StatelessWidget {
  const _Loading({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).luqma;

    Widget block(double height, {BorderRadius? radius}) => Container(
          height: height,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: radius ?? Radii.cardAll,
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: Sizes.minTarget,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: Space.sm),
                  SizedBox(
                    width: 72,
                    child: Center(
                      child: block(Space.xxl, radius: Radii.pillAll),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.xl - 4),
          AspectRatio(
            aspectRatio: Sizes.bannerAspect,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: Radii.cardAll,
              ),
            ),
          ),
          const SizedBox(height: Space.xl - 4),
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(height: Space.sm),
            block(96),
          ],
        ],
      ),
    );
  }
}


