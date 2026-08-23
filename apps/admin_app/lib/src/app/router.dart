import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../auth/admin_access.dart';
import '../auth/gate_screens.dart';
import '../auth/identity_provider.dart';
import '../dashboard/dashboard_screen.dart';
import '../merchants/merchants_screen.dart';
import '../places/places_screen.dart';
import '../shell/layout.dart';

part 'router.g.dart';

const _destinations = [
  AdminDestination(label: 'اليوم', icon: Icons.today, route: Routes.dashboard),
  AdminDestination(label: 'المطاعم', icon: Icons.storefront, route: Routes.merchants),
  AdminDestination(label: 'الأماكن', icon: Icons.place, route: Routes.zones),
  AdminDestination(label: 'الصور', icon: Icons.photo_library, route: Routes.media),
];

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  // Read, then listen. Watching would rebuild the whole router on every session change
  // and throw away the navigation stack with it.
  final access = ValueNotifier(ref.read(adminAccessProvider));
  ref.listen(adminAccessProvider, (_, next) => access.value = next);
  ref.onDispose(access.dispose);

  return GoRouter(
    initialLocation: Routes.starting,
    refreshListenable: access,
    // The gate is one function, tested on its own in access_test.dart. Keeping it out of
    // here is what stops the redirect rules from being spread across route definitions.
    redirect: (context, state) =>
        redirectFor(access: access.value, location: state.matchedLocation),
    routes: [
      GoRoute(path: Routes.starting, builder: (_, _) => const StartingScreen()),
      GoRoute(path: Routes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: Routes.noAccess, builder: (_, _) => const NoAccessScreen()),
      ShellRoute(
        builder: (context, state, child) => AdminShell(
          destinations: _destinations,
          currentRoute: state.matchedLocation,
          onDestination: (d) => context.go(d.route),
          child: child,
        ),
        routes: [
          GoRoute(path: Routes.dashboard, builder: (_, _) => const DashboardScreen()),
          GoRoute(path: Routes.merchants, builder: (_, _) => const MerchantsScreen()),
          GoRoute(path: Routes.zones, builder: (_, _) => const PlacesScreen()),
          GoRoute(path: Routes.media, builder: (_, _) => const _Placeholder('الصور')),
        ],
      ),
    ],
  );
}

/// Stands in for a screen that lands later in this phase, so the navigation is complete
/// and walkable now rather than half of it leading nowhere.
class _Placeholder extends StatelessWidget {
  const _Placeholder(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: Text('قريب')),
      );
}
