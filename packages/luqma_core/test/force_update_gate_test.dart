import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The gate is the one widget allowed to stand between a person and the app, so its
/// two directions both get proven: an old build is stopped at the door with a way out,
/// and a current build walks straight through.
void main() {
  Widget harness({
    required String minSupportedVersion,
    String currentVersion = '1.4.0',
  }) {
    return ProviderScope(
      overrides: [
        remoteConfigServiceProvider.overrideWithValue(
          RemoteConfigService(FakeConfigFetcher({
            if (minSupportedVersion.isNotEmpty)
              'min_supported_version': minSupportedVersion,
          })),
        ),
      ],
      child: MaterialApp(
        // The view reads LuqmaColors off the theme, so it has to be one of ours.
        theme: LuqmaTheme.light,
        locale: const Locale('ar'),
        supportedLocales: LuqmaStrings.supportedLocales,
        localizationsDelegates: const [
          ...LuqmaStrings.localizationsDelegates,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: LuqmaForceUpdateGate(
          currentVersion: currentVersion,
          storeUrl: Uri.parse('https://play.google.com/store/apps/details?id=x'),
          child: const Text('التطبيق'),
        ),
      ),
    );
  }

  group('LuqmaForceUpdateGate', () {
    testWidgets('a build below the floor is stopped', (tester) async {
      await tester.pumpWidget(harness(minSupportedVersion: '2.0.0'));
      await tester.pump();

      expect(find.byKey(const Key('force-update.button')), findsOneWidget);
      expect(find.text('التطبيق'), findsNothing);
    });

    testWidgets('a build at the floor passes', (tester) async {
      await tester.pumpWidget(harness(
        minSupportedVersion: '1.4.0',
        currentVersion: '1.4.0',
      ));
      await tester.pump();

      expect(find.text('التطبيق'), findsOneWidget);
    });

    testWidgets('a build above the floor passes', (tester) async {
      await tester.pumpWidget(harness(
        minSupportedVersion: '1.3.9',
        currentVersion: '1.4.0',
      ));
      await tester.pump();

      expect(find.text('التطبيق'), findsOneWidget);
    });

    testWidgets('no floor set means nobody is stopped', (tester) async {
      await tester.pumpWidget(harness(minSupportedVersion: ''));
      await tester.pump();

      expect(find.text('التطبيق'), findsOneWidget);
    });

    testWidgets('a nonsense floor stops nobody — the owner cannot lock the city out by typo', (tester) async {
      await tester.pumpWidget(harness(minSupportedVersion: 'not.a.version'));
      await tester.pump();

      expect(find.text('التطبيق'), findsOneWidget);
    });
  });
}
