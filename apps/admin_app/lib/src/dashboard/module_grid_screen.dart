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
    this.adminOnly = false,
  });

  final String label;
  final IconData icon;
  final String route;

  /// Whether a moderator is shown this module at all.
  ///
  /// The database refuses them the money, the roster and the control plane whatever the
  /// app draws, and a refusal reaches the screen as an ordinary Arabic "مش من حقك" — so
  /// this is not the boundary. It is here because a tile that always ends in that
  /// sentence is a tile somebody taps every day and learns nothing from.
  final bool adminOnly;

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
      body: AdminContent(
        child: Column(
          children: [
            // The grid is where the admin lives; «اليوم» may never be opened. Asked only
            // there, the permission was never asked at all, and the unanswered-order alert
            // was dropped silently.
            const LuqmaNotificationBanner(
              reason:
                  'أوردر محدش ردّ عليه بيوصلك بتنبيه — بس لو التنبيهات شغالة.',
              margin: EdgeInsets.fromLTRB(
                Space.gutter,
                Space.gutter,
                Space.gutter,
                0,
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(adminAttentionProvider),
                child: GridView.builder(
                  key: gridKey,
                  padding: const EdgeInsets.all(Space.gutter),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    // Two columns on a phone, more as the window grows. An extent rather than a
                    // count, so the tablet and the browser are the same code.
                    // Three across on a phone: seventeen sections were nine rows of two tall
                    // tiles, most of each tile empty (QA review 2026-09-19).
                    maxCrossAxisExtent: 140,
                    mainAxisSpacing: Space.sm,
                    crossAxisSpacing: Space.sm,
                    childAspectRatio: 1.05,
                  ),
                  itemCount: modules.length,
                  itemBuilder: (context, i) => _Tile(
                    module: modules[i],
                    waiting: counts == null
                        ? null
                        : modules[i].waiting?.call(counts),
                  ),
                ),
              ),
            ),
          ],
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
      // The tap lives here too: the node a screen reader lands on is this one, and the
      // InkWell's own action is excluded below along with its label, so double-tapping a
      // tile used to do nothing at all.
      onTap: () => context.push(module.route),
      child: ExcludeSemantics(
        child: Material(
          color: colors.card,
          borderRadius: Radii.cardAll,
          child: InkWell(
            key: ModuleGridScreen.tileKey(module.route),
            // `push`, not `go`. The grid is the home and a module opened from it is a
            // drill-down, so it belongs on top of the grid rather than in place of it —
            // `go` replaces the whole stack, which left system back with nothing to pop
            // and closed the app instead of returning here. The rail on wider layouts
            // still uses `go`, because switching destinations there is lateral and the
            // rail itself is always on screen to get back with.
            onTap: () => context.push(module.route),
            borderRadius: Radii.cardAll,
            child: Container(
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                borderRadius: Radii.cardAll,
                border: Border.all(color: colors.hairline),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(module.icon, size: 28, color: colors.brand),
                  const SizedBox(height: Space.xs),
                  Text(
                    module.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
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
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onBrand,
                        ),
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
