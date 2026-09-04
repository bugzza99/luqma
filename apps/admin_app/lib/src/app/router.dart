import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:luqma_core/luqma_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../auth/admin_access.dart';
import '../auth/gate_screens.dart';
import '../auth/identity_provider.dart';
import '../about/about_editor_screen.dart';
import '../config/config_screen.dart';
import '../cuisines/cuisines_screen.dart';
import '../customers/customers_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../home_builder/home_builder_screen.dart';
import '../issues/issues_screen.dart';
import '../media/media_screen.dart';
import '../merchants/merchants_screen.dart';
import '../places/places_screen.dart';
import '../plans/plans_editor_screen.dart';
import '../promotions/promotions_screen.dart';
import '../settings/settings_screen.dart';
import '../dashboard/module_grid_screen.dart';
import '../shell/layout.dart';
import '../staff/staff_screen.dart';
import '../statistics/statistics_screen.dart';

part 'router.g.dart';

/// Every module in AdminApp, in the order the owner meets them.
///
/// One list, used twice: it is the grid on a phone and the rail on a desktop. Two lists
/// would drift, and the one that drifted would be the one nobody opened that week.
const _modules = [
  AdminModule(
    label: 'اليوم',
    icon: Icons.today,
    route: Routes.today,
    waiting: _ordersNeedingAttention,
  ),
  AdminModule(
    label: 'الصور',
    icon: Icons.photo_library,
    route: Routes.media,
    waiting: _pendingMedia,
  ),
  AdminModule(
    label: 'الشكاوى',
    icon: Icons.forum,
    route: Routes.issues,
    waiting: _openIssues,
  ),
  AdminModule(
    label: 'الإعلانات',
    icon: Icons.campaign,
    route: Routes.promotions,
    waiting: _requestedPromotions,
  ),
  AdminModule(
    label: 'المطاعم',
    icon: Icons.storefront,
    route: Routes.merchants,
    waiting: _pendingMerchants,
  ),
  AdminModule(label: 'العملاء', icon: Icons.people, route: Routes.customers),
  AdminModule(label: 'الأماكن', icon: Icons.place, route: Routes.zones),
  AdminModule(label: 'المطبخ', icon: Icons.restaurant_menu, route: Routes.cuisines),
  AdminModule(label: 'الصفحة الرئيسية', icon: Icons.dashboard, route: Routes.home),
  AdminModule(label: 'الإحصائيات', icon: Icons.bar_chart, route: Routes.statistics),
  AdminModule(label: 'الفريق', icon: Icons.badge, route: Routes.staff),
  AdminModule(label: 'الخطط', icon: Icons.workspace_premium, route: Routes.plans),
  AdminModule(label: 'حول لقمة', icon: Icons.info_outline, route: Routes.about),
  AdminModule(label: 'الإعدادات', icon: Icons.settings, route: Routes.settings),
];

// Named functions rather than closures: a const list cannot hold a lambda.
int _pendingMedia(AdminAttention a) => a.pendingMedia;
int _openIssues(AdminAttention a) => a.openIssues;
int _requestedPromotions(AdminAttention a) => a.requestedPromotions;
int _pendingMerchants(AdminAttention a) => a.pendingMerchants;
int _ordersNeedingAttention(AdminAttention a) => a.ordersNeedingAttention;


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
        builder: (context, state, child) => LuqmaTappedOrder(
          // AdminApp is told one thing about an order — that nobody answered it — and
          // اليوم is the screen that lists exactly those. `push`, not `go`, so back
          // returns to whatever the admin was in the middle of rather than exiting.
          onOpen: (_) => context.push(Routes.today),
          child: AdminShell(
            modules: _modules,
            currentRoute: state.matchedLocation,
            onDestination: (m) => context.go(m.route),
            child: child,
          ),
        ),
        routes: [
          // The grid is the home. What used to be here — the day's four numbers — is a
          // module inside it now, and it is where the owner goes rather than where they
          // land.
          GoRoute(
            path: Routes.dashboard,
            builder: (_, _) => const ModuleGridScreen(modules: _modules),
          ),
          GoRoute(path: Routes.today, builder: (_, _) => const DashboardScreen()),
          GoRoute(
            path: Routes.statistics,
            builder: (_, _) => const StatisticsScreen(),
          ),
          GoRoute(path: Routes.merchants, builder: (_, _) => const MerchantsScreen()),
          GoRoute(path: Routes.customers, builder: (_, _) => const CustomersScreen()),
          GoRoute(path: Routes.issues, builder: (_, _) => const IssuesScreen()),
          GoRoute(path: Routes.staff, builder: (_, _) => const StaffScreen()),
          GoRoute(path: Routes.zones, builder: (_, _) => const PlacesScreen()),
          GoRoute(path: Routes.media, builder: (_, _) => const MediaScreen()),
          GoRoute(
            path: Routes.promotions,
            builder: (_, _) => const PromotionsScreen(),
          ),
          GoRoute(path: Routes.home, builder: (_, _) => const HomeBuilderScreen()),
          GoRoute(path: Routes.settings, builder: (_, _) => const SettingsScreen()),
          GoRoute(path: Routes.config, builder: (_, _) => const ConfigScreen()),
          GoRoute(path: Routes.plans, builder: (_, _) => const PlansEditorScreen()),
          GoRoute(path: Routes.cuisines, builder: (_, _) => const CuisinesScreen()),
          GoRoute(path: Routes.about, builder: (_, _) => const AboutEditorScreen()),
        ],
      ),
    ],
  );
}
