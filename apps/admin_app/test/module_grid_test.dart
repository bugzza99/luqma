import 'package:admin_app/src/dashboard/module_grid_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The AdminApp home.
///
/// It replaced an eleven-item `NavigationBar` — a component Material designs for three to
/// five, which on a phone rendered as a row of slivers nobody could read or hit.
///
/// The tiles carry counts because the question somebody opens this app with is "what
/// needs me today?", and a grid of identical tiles answers it with nothing.
// Top-level, because a const list cannot hold a closure — the same reason the router's
// module list uses named functions.
int mediaOf(AdminAttention a) => a.pendingMedia;
int issuesOf(AdminAttention a) => a.openIssues;

const modules = [
  AdminModule(
    label: 'الصور',
    icon: Icons.photo_library,
    route: '/media',
    waiting: mediaOf,
  ),
  AdminModule(
    label: 'الشكاوى',
    icon: Icons.forum,
    route: '/issues',
    waiting: issuesOf,
  ),
  AdminModule(label: 'الإعدادات', icon: Icons.settings, route: '/settings'),
];

void main() {
  Future<void> pump(
    WidgetTester tester, {
    AdminAttention? attention,
    Failure? failure,
  }) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminRepositoryProvider.overrideWithValue(
            FakeAdminRepository(attentionValue: attention, failure: failure),
          ),
        ],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: ModuleGridScreen(modules: modules),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every module is on it', (tester) async {
    await pump(tester, attention: const AdminAttention());

    for (final module in modules) {
      expect(find.byKey(ModuleGridScreen.tileKey(module.route)), findsOneWidget);
    }
  });

  testWidgets('a module with work waiting says how much', (tester) async {
    await pump(tester, attention: const AdminAttention(pendingMedia: 3));

    expect(find.byKey(ModuleGridScreen.countKey('/media')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  // A row of tiles each saying "0" is a screen shouting about work that does not exist.
  testWidgets('a module with nothing waiting says nothing', (tester) async {
    await pump(tester, attention: const AdminAttention(pendingMedia: 0));

    expect(find.byKey(ModuleGridScreen.countKey('/media')), findsNothing);
  });

  testWidgets('a module that has no queue never shows one', (tester) async {
    await pump(tester, attention: const AdminAttention(pendingMedia: 3));

    expect(find.byKey(ModuleGridScreen.countKey('/settings')), findsNothing);
  });

  // Being unable to say how many photographs are waiting is not a reason to hide the way
  // to the photographs.
  testWidgets('a failed count leaves every module reachable', (tester) async {
    await pump(tester, failure: const OfflineFailure());

    for (final module in modules) {
      expect(find.byKey(ModuleGridScreen.tileKey(module.route)), findsOneWidget);
    }
  });

  // A bare number read out on its own tells a screen-reader user nothing, and several of
  // them competing is worse than none. Each tile is one atomic sentence.
  testWidgets('a waiting tile is announced as one sentence', (tester) async {
    await pump(tester, attention: const AdminAttention(openIssues: 2));

    expect(find.bySemanticsLabel('الشكاوى، 2 في الانتظار'), findsOneWidget);
  });

  testWidgets('and a quiet one is announced by its name alone', (tester) async {
    await pump(tester, attention: const AdminAttention());

    expect(find.bySemanticsLabel('الشكاوى'), findsOneWidget);
  });
}
