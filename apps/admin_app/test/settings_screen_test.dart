import 'package:admin_app/src/about/about_editor_screen.dart';
import 'package:admin_app/src/app/router.dart';
import 'package:admin_app/src/auth/admin_access.dart';
import 'package:admin_app/src/auth/identity_provider.dart';
import 'package:admin_app/src/config/config_screen.dart';
import 'package:admin_app/src/plans/plans_editor_screen.dart';
import 'package:admin_app/src/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// الإعدادات — three tiles and nothing else.
///
/// A screen this thin looks like it needs no test, and that is exactly the shape of
/// screen that quietly breaks: every tile is a `context.push` of a path string, and a
/// path the router does not serve renders nothing and reports nothing. The owner taps,
/// the screen does not change, and there is no error anywhere to notice.
///
/// So it is driven through the real router rather than pumped on its own — the tap has
/// to land on an actual screen for the test to pass.
void main() {
  Future<void> pumpSettings(WidgetTester tester) async {
    // Wide, like `router_test`: the shell is a rail on this width, and the whole point
    // is to check the real navigation rather than a phone layout.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminAccessProvider.overrideWithValue(AdminAccess.granted),
          geographyRepositoryProvider.overrideWithValue(FakeGeographyRepository()),
          configRepositoryProvider.overrideWithValue(FakeConfigRepository()),
          billingRepositoryProvider.overrideWithValue(FakeBillingRepository()),
          adminRepositoryProvider.overrideWithValue(FakeAdminRepository()),
          mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: LuqmaTheme.light,
            locale: const Locale('ar'),
            supportedLocales: LuqmaStrings.supportedLocales,
            localizationsDelegates: LuqmaStrings.localizationsDelegates,
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('الإعدادات').first);
    await tester.pumpAndSettle();
  }

  testWidgets('the settings screen offers its three doors', (tester) async {
    await pumpSettings(tester);

    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byKey(SettingsScreen.configKey), findsOneWidget);
    expect(find.byKey(SettingsScreen.plansKey), findsOneWidget);
    expect(find.byKey(SettingsScreen.aboutKey), findsOneWidget);
  });

  testWidgets('each tile says what is behind it, not just its name', (tester) async {
    await pumpSettings(tester);

    // A list of three bare words makes the owner open all three to find the one they
    // wanted. The subtitles are what stop that.
    expect(find.text('الميزات والحدود والتحديثات'), findsOneWidget);
    expect(find.text('أسعار الاشتراك وحدود الميزات'), findsOneWidget);
    expect(find.text('صورة المالك والروابط والوصف'), findsOneWidget);
  });

  testWidgets('the config tile lands on the config screen', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(SettingsScreen.configKey));
    await tester.pumpAndSettle();

    expect(find.byType(ConfigScreen), findsOneWidget);
  });

  testWidgets('the plans tile lands on the plans editor', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(SettingsScreen.plansKey));
    await tester.pumpAndSettle();

    expect(find.byType(PlansEditorScreen), findsOneWidget);
  });

  testWidgets('the about tile lands on the about editor', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.byKey(SettingsScreen.aboutKey));
    await tester.pumpAndSettle();

    expect(find.byType(AboutEditorScreen), findsOneWidget);
  });
}
