import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';

/// Arranging the customer's home screen without shipping an app.
///
/// The boundary this screen enforces is the whole of "dynamic": the owner picks which
/// **registered** blocks appear, in what order, and whether they are visible. They cannot
/// describe a new kind of block — the app owns the map of types to widgets, and a type
/// outside it draws nothing. That is what keeps this from becoming server-driven UI,
/// which would have cost three times the work and been far harder to keep from breaking.
///
/// So a type is *chosen from a list*, never typed. A string typed here would be a typo
/// that renders as a blank space on every phone in the city.
class HomeBuilderScreen extends ConsumerWidget {
  const HomeBuilderScreen({super.key});

  static const emptyKey = Key('homeBuilder.empty');
  static const errorKey = Key('homeBuilder.error');
  static const addKey = Key('homeBuilder.add');

  static Key rowKey(String key) => Key('homeBuilder.row.$key');
  static Key hiddenKey(String key) => Key('homeBuilder.hidden.$key');
  static Key unknownKey(String key) => Key('homeBuilder.unknown.$key');
  static Key visibilityKey(String key) => Key('homeBuilder.visibility.$key');
  static Key upKey(String key) => Key('homeBuilder.up.$key');
  static Key downKey(String key) => Key('homeBuilder.down.$key');
  static Key typeKey(String type) => Key('homeBuilder.type.$type');

  /// The types CustomerApp actually registered.
  ///
  /// This list and the customer's section registry have to agree. They are kept apart
  /// because AdminApp runs in a browser and cannot import the customer's widgets — so
  /// the flag is the `unknownKey` row below, which shows an admin a block their build
  /// cannot draw rather than letting it disappear silently.
  static const knownTypes = [
    'categoryChips',
    'adSlot',
    'homeKitchenToday',
    'merchantList',
    'topRated',
    'mostOrdered',
  ];

  static const typeNames = {
    'categoryChips': 'شرائح الفئات',
    'adSlot': 'مكان إعلان',
    'homeKitchenToday': 'أكل بيتي النهارده',
    'merchantList': 'قائمة المطاعم',
    'topRated': 'الأعلى تقييماً',
    'mostOrdered': 'الأكثر طلباً',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final strings = LuqmaStrings.of(context);
    final sections = ref.watch(homeSectionsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(title: const Text('ترتيب الرئيسية')),
      body: AdminContent(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.gutter,
                vertical: Space.sm + 2,
              ),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  bottom: BorderSide(color: colors.hairline),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: Sizes.iconSm,
                    color: colors.price,
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      strings.homeBuilderBanner,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.price,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LuqmaAsyncView(
                value: sections,
                errorKey: HomeBuilderScreen.errorKey,
                onRetry: () => ref.invalidate(homeSectionsProvider),
                empty: LuqmaEmptyView(
                  key: HomeBuilderScreen.emptyKey,
                  title: 'الرئيسية فاضية',
                  message:
                      'ضيف بلوك واحد على الأقل، وإلا العميل هيفتح على شاشة فاضية.',
                ),
                isEmpty: (value) => value.isEmpty,
                builder: (context, value) => ListView.separated(
                  padding: const EdgeInsets.all(Space.gutter),
                  itemCount: value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
                  itemBuilder: (context, i) => _Row(
                    section: value[i],
                    order: value.map((s) => s.key).toList(),
                    index: i,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: addKey,
        onPressed: () => _add(context, ref, sections.value ?? const []),
        icon: const Icon(Icons.add_rounded),
        label: const Text('ضيف بلوك', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: colors.brand,
        foregroundColor: colors.background,
      ),
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    List<HomeSection> existing,
  ) async {
    final colors = Theme.of(context).luqma;
    final strings = LuqmaStrings.of(context);

    final type = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.card,
      shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: Space.md),
                  decoration: BoxDecoration(
                    color: colors.hairline,
                    borderRadius: Radii.pillAll,
                  ),
                ),
              ),
              Text(
                strings.homeBuilderAddTitle,
                style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                strings.homeBuilderAddSubtitle,
                style: LuqmaType.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: Space.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final type in knownTypes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Sizes.targetGap),
                          child: OutlinedButton(
                            key: typeKey(type),
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(type),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(56),
                              side: BorderSide(color: colors.hairline),
                              shape: const RoundedRectangleBorder(
                                borderRadius: Radii.cardAll,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: Space.md,
                                vertical: Space.sm,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        typeNames[type] ?? type,
                                        style: Theme.of(sheetContext)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: colors.textPrimary,
                                            ),
                                      ),
                                      Text(
                                        type,
                                        style: LuqmaType.caption.copyWith(
                                          color: colors.textSecondary,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: colors.brand,
                                  size: Sizes.iconMd,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (type == null || !context.mounted) return;

    // Two ad slots on one screen is a real arrangement — one near the top, one further
    // down — so a second block of a type gets its own key rather than overwriting the
    // first. The key is the identity; the type is only what it draws.
    final taken = existing.map((s) => s.key).toSet();
    var key = type;
    for (var n = 2; taken.contains(key); n++) {
      key = '$type$n';
    }

    await ref.read(homeSectionRepositoryProvider).save(
          HomeSection(
            key: key,
            type: type,
            // Added at the bottom rather than the top: an owner adding a block is not
            // saying it is the most important thing on the screen.
            sortOrder: existing.length,
            cityId: ref.read(currentCityProvider),
          ),
        );
  }
}

class _Row extends ConsumerWidget {
  const _Row({
    required this.section,
    required this.order,
    required this.index,
  });

  final HomeSection section;
  final List<String> order;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final known = HomeBuilderScreen.knownTypes.contains(section.type);

    return Opacity(
      opacity: section.isVisible ? 1.0 : 0.6,
      child: Container(
        key: HomeBuilderScreen.rowKey(section.key),
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: Radii.cardAll,
          border: Border.all(color: colors.hairline),
          boxShadow: Elevations.card,
        ),
        child: Row(
          children: [
            Icon(
              Icons.drag_handle_rounded,
              color: colors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    HomeBuilderScreen.typeNames[section.type] ?? section.type,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    section.key == section.type
                        ? section.type
                        : '${section.type} • ${section.key}',
                    style: LuqmaType.caption.copyWith(
                      color: colors.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (!section.isVisible)
                    Padding(
                      key: HomeBuilderScreen.hiddenKey(section.key),
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Row(
                        children: [
                          Icon(
                            Icons.visibility_off_outlined,
                            size: 14,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              // Hidden is not deleted. Hiding the home-kitchen band on a day
                              // nobody is cooking and putting it back tomorrow keeps its
                              // settings.
                              'مخفي عن العملاء',
                              style: LuqmaType.bodySmall.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (!known)
                    Padding(
                      key: HomeBuilderScreen.unknownKey(section.key),
                      padding: const EdgeInsets.only(top: Space.xs),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: colors.danger,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              // It renders as nothing on the customer's phone. An admin who
                              // cannot see it here cannot fix it anywhere.
                              'النوع ده التطبيق مش عارفه — مش هيظهر لحد',
                              style: LuqmaType.bodySmall.copyWith(
                                color: colors.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              key: HomeBuilderScreen.visibilityKey(section.key),
              tooltip: section.isVisible ? 'اخفي' : 'اظهر',
              icon: Icon(
                section.isVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: section.isVisible
                    ? colors.success
                    : colors.textSecondary,
              ),
              onPressed: () => ref
                  .read(homeSectionRepositoryProvider)
                  .setVisible(section.key, !section.isVisible,
                      cityId: ref.read(currentCityProvider)),
            ),
            IconButton(
              key: HomeBuilderScreen.upKey(section.key),
              tooltip: 'اطلع فوق',
              icon: const Icon(Icons.arrow_upward_rounded),
              onPressed: index == 0 ? null : () => _move(ref, index - 1),
            ),
            IconButton(
              key: HomeBuilderScreen.downKey(section.key),
              tooltip: 'انزل تحت',
              icon: const Icon(Icons.arrow_downward_rounded),
              onPressed:
                  index == order.length - 1 ? null : () => _move(ref, index + 1),
            ),
          ],
        ),
      ),
    );
  }

  /// Moves this block to [to], rewriting the whole order.
  ///
  /// The whole list rather than two documents, because sort orders that drift apart are
  /// how two blocks end up claiming the same position and the screen settles on
  /// whichever loaded first.
  Future<void> _move(WidgetRef ref, int to) async {
    final next = [...order]
      ..removeAt(index)
      ..insert(to, section.key);
    await ref.read(homeSectionRepositoryProvider).reorder(
          next,
          cityId: ref.read(currentCityProvider),
        );
  }
}


