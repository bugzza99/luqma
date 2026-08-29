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
            // Slivers. `LuqmaAsyncView` is a box widget and cannot be one of these —
            // this is the only screen in the product that builds its states as slivers,
            // and one exception is cheaper than a second widget nobody else would use.
            switch (sections) {
              // One failed read of the arrangement should not hide the search field or
              // the bar — the customer can still look for what they wanted. It comes
              // first and matches on `hasError`, not on the `AsyncError` type: a stream
              // that fails before it has ever emitted stays `AsyncLoading` with the
              // error hanging off it, so a type match never fires.
              AsyncValue(hasError: true, :final error?) =>
                SliverToBoxAdapter(child: LuqmaErrorView(failure: error, onRetry: () => ref.invalidate(homeSectionsProvider))),
              AsyncValue(hasValue: true, :final value?) =>
                _Sections(sections: value),
              _ => const SliverToBoxAdapter(child: _Loading()),
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
      return const SliverToBoxAdapter(child: LuqmaEmptyView(
            key: HomeScreen.emptyKey,
            message: 'لسه مفيش مطاعم هنا.',
          ));
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
          icon: Icon(Icons.expand_more_rounded, size: 18, color: colors.onBrand),
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


