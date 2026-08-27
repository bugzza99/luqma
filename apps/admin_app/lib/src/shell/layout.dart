import 'package:flutter/material.dart';
import 'package:luqma_core/luqma_core.dart';

import '../dashboard/module_grid_screen.dart';

/// How much room there is, and what to do with it.
///
/// AdminApp is the only Luqma app that runs on more than a phone. That is deliberate: the
/// launch plan has the owner typing roughly six hundred menu items personally, and doing
/// that on a phone keyboard rather than a real one is the difference between an afternoon
/// and a fortnight.
enum AdminLayout {
  /// Phone. Bottom bar, one pane.
  compact,

  /// Tablet or a narrow window. Rail, still one pane.
  medium,

  /// Laptop. Rail plus a list beside a detail, so entering a menu does not mean
  /// bouncing back to a list between every item.
  expanded;

  /// Material's breakpoints, used unchanged — there is nothing about this app that
  /// justifies inventing its own.
  static AdminLayout forWidth(double width) {
    if (width < 600) return AdminLayout.compact;
    if (width < 840) return AdminLayout.medium;
    return AdminLayout.expanded;
  }

  static AdminLayout of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);

  bool get showsTwoPanes => this == AdminLayout.expanded;
  bool get usesBottomNav => this == AdminLayout.compact;

  /// Text and form fields stop being readable long before a browser window stops getting
  /// wider. Capped here so no individual screen has to remember to.
  static const maxContentWidth = 1100.0;

  static double contentWidthFor(double available) =>
      available < maxContentWidth ? available : maxContentWidth;
}



/// The chrome around every AdminApp screen.
///
/// One widget tree at every size: the shell moves the navigation, the screens do not know
/// which layout they are in. Writing each screen twice is how the phone version and the
/// desktop version start behaving differently.
class AdminShell extends StatelessWidget {
  const AdminShell({
    super.key,
    required this.modules,
    required this.currentRoute,
    required this.onDestination,
    required this.child,
    this.detail,
  });

  final List<AdminModule> modules;
  final String currentRoute;
  final ValueChanged<AdminModule> onDestination;

  /// The primary pane.
  final Widget child;

  /// Shown beside [child] only where there is room. On a phone this is pushed as a route
  /// instead, which is why it is optional rather than required.
  final Widget? detail;

  int get _selectedIndex {
    final index = modules.indexWhere((d) => currentRoute.startsWith(d.route));
    // A route that belongs to no destination — the dashboard, a detail page — should
    // leave the navigation showing the first entry rather than crashing on -1.
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final layout = AdminLayout.of(context);
    final colors = Theme.of(context).luqma;

    final body = layout.showsTwoPanes && detail != null
        ? Row(
            children: [
              Expanded(flex: 2, child: child),
              VerticalDivider(width: 1, color: colors.hairline),
              Expanded(flex: 3, child: detail!),
            ],
          )
        : child;

    // No bottom bar on a phone. There are fourteen modules, and `NavigationBar` is a
    // component Material designs for three to five — eleven of them was already a row of
    // unreadable slivers. The grid at `/` is the navigation, and every module is one tap
    // from it and one back away.
    if (layout.usesBottomNav) {
      return Scaffold(body: SafeArea(child: body));
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            // The rail stays on a desktop, where fourteen labelled rows are readable
            // and a grid would mean a trip home between every module. Scrollable,
            // because fourteen of them is taller than a laptop screen.
            SingleChildScrollView(
              child: IntrinsicHeight(
                child: NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (i) => onDestination(modules[i]),
                  // Labels always shown: this is a tool used occasionally, not an app
                  // whose icons anyone will memorise.
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: colors.card,
                  destinations: [
                    for (final d in modules)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        label: Text(d.label),
                      ),
                  ],
                ),
              ),
            ),
            VerticalDivider(width: 1, color: colors.hairline),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Caps its child at a readable width and centres it.
class AdminContent extends StatelessWidget {
  const AdminContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AdminLayout.maxContentWidth),
        child: child,
      ),
    );
  }
}
