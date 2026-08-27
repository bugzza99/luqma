import 'package:admin_app/src/app/router.dart';
import 'package:admin_app/src/auth/admin_access.dart';
import 'package:admin_app/src/auth/gate_screens.dart';
import 'package:admin_app/src/auth/identity_provider.dart';
import 'package:admin_app/src/dashboard/module_grid_screen.dart';
import 'package:admin_app/src/places/places_screen.dart';
import 'package:admin_app/src/shell/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The gate, end to end — the router, the redirect and the screens together.
///
/// `access_test.dart` proves the rules in isolation; this proves they are actually wired
/// to the router and that each answer lands on a real screen. A redirect pointing at a
/// path the router does not serve is a blank page with no error anywhere.
void main() {
  Future<void> pumpWith(WidgetTester tester, AdminAccess access) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adminAccessProvider.overrideWithValue(access),
          geographyRepositoryProvider.overrideWithValue(
            FakeGeographyRepository(),
          ),
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
  }

  testWidgets('an unresolved session shows the splash, not a login form',
      (tester) async {
    await pumpWith(tester, AdminAccess.unknown);

    expect(find.byType(StartingScreen), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });

  testWidgets('signed out lands on the sign-in screen', (tester) async {
    await pumpWith(tester, AdminAccess.signedOut);

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byKey(SignInScreen.submitKey), findsOneWidget);
  });

  testWidgets('a signed-in non-admin is told so and offered a way out',
      (tester) async {
    await pumpWith(tester, AdminAccess.notAuthorised);

    expect(find.byType(NoAccessScreen), findsOneWidget);
    expect(find.text('تسجيل الخروج'), findsOneWidget);
  });

  // An admin lands on the grid of modules. The day's four numbers used to be here; they
  // are a module inside it now — somewhere the owner goes rather than where they land.
  testWidgets('an admin lands on the module grid inside the shell', (tester) async {
    await pumpWith(tester, AdminAccess.granted);

    expect(find.byType(ModuleGridScreen), findsOneWidget);
    expect(find.byType(AdminShell), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });

  testWidgets('the navigation reaches the places screen', (tester) async {
    await pumpWith(tester, AdminAccess.granted);

    await tester.tap(find.text('الأماكن').first);
    await tester.pumpAndSettle();

    expect(find.byType(PlacesScreen), findsOneWidget);
    expect(find.byType(AdminShell), findsOneWidget, reason: 'the shell persists');
  });

  testWidgets('every destination in the rail leads somewhere', (tester) async {
    await pumpWith(tester, AdminAccess.granted);

    for (final label in ['اليوم', 'المطاعم', 'الأماكن', 'الصور']) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      // A route the router does not serve renders nothing and reports nothing; the shell
      // still being here is what says the destination resolved.
      expect(find.byType(AdminShell), findsOneWidget, reason: label);
    }
  });
}
