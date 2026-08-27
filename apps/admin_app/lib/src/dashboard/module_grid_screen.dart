import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:luqma_core/luqma_core.dart';

import '../shell/layout.dart';

/// One module on the home grid.
@immutable
class AdminModule {
  const AdminModule({
    required this.label,
    required this.icon,
    required this.route,
    this.waiting,
  });

  final String label;
  final IconData icon;
  final String route;

  /// How many things in this module are waiting, given what the server said. Null for a
  /// module where "waiting" means nothing — settings does not have a queue.
  final int Function(AdminAttention)? waiting;
}

/// The AdminApp home: every module, side by side.
///
/// It replaces an eleven-item `NavigationBar` — a component Material designs for three to
/// five. Eleven of them on a phone is a row of unreadable slivers, and the owner is the
/// only person who will ever use this screen.
///
/// The tiles carry live counts, because the question somebody opens this app with is
/// "what needs me today?", and eleven identical tiles answer it with nothing. A count is
/// drawn only when there is something to draw: a tile that says zero is a tile arguing
/// for attention it does not deserve.
class ModuleGridScreen extends ConsumerWidget {
  const ModuleGridScreen({super.key, required this.modules});

  final List<AdminModule> modules;

  static const gridKey = Key('adminHome.grid');
  static Key tileKey(String route) => Key('adminHome.tile.$route');
  static Key countKey(String route) => Key('adminHome.count.$route');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attention = ref.watch(adminAttentionProvider);
    // A failed count must not blank the grid: the modules are still reachable, and being
    // unable to say how many photographs are waiting is not a reason to hide the way to
    // the photographs.
    final counts = attention.value;

    return Scaffold(
      appBar: AppBar(title: const Text('لقمة')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminAttentionProvider),
        child: AdminContent(
          child: GridView.builder(
            key: gridKey,
            padding: const EdgeInsets.all(Space.gutter),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              // Two columns on a phone, more as the window grows. An extent rather than a
              // count, so the tablet and the browser are the same code.
              maxCrossAxisExtent: 200,
              mainAxisSpacing: Space.md,
              crossAxisSpacing: Space.md,
              childAspectRatio: 1.15,
            ),
            itemCount: modules.length,
            itemBuilder: (context, i) => _Tile(
              module: modules[i],
              waiting: counts == null ? null : modules[i].waiting?.call(counts),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.module, required this.waiting});

  final AdminModule module;

  /// Null while the counts are still loading or could not be read.
  final int? waiting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.luqma;
    final count = waiting ?? 0;
    final hasWork = count > 0;

    return Semantics(
      button: true,
      // One atomic label rather than a tile and a loose number beside it. A bare count
      // read out on its own — "three" — tells a screen-reader user nothing, and eleven
      // of them competing is worse than none.
      label: hasWork ? '${module.label}، $count في الانتظار' : module.label,
      child: ExcludeSemantics(
        child: Material(
          color: colors.card,
          borderRadius: Radii.cardAll,
          child: InkWell(
            key: ModuleGridScreen.tileKey(module.route),
            onTap: () => context.go(module.route),
            borderRadius: Radii.cardAll,
            child: Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                borderRadius: Radii.cardAll,
                border: Border.all(color: colors.hairline),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(module.icon, size: 32, color: colors.brand),
                  const SizedBox(height: Space.sm),
                  Text(
                    module.label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: Space.xs),
                  // Nothing at all when there is nothing waiting. A row of tiles each
                  // saying "0" is a screen shouting about work that does not exist.
                  if (hasWork)
                    Container(
                      key: ModuleGridScreen.countKey(module.route),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        // Burgundy, not the accent: orange is for prices, offers and
                        // ratings. "Three photographs are waiting" is none of those.
                        color: colors.brand,
                        borderRadius: Radii.imageAll,
                      ),
                      child: Text(
                        '$count',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.onBrand),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
