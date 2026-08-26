import 'package:admin_app/src/about/about_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The "حول لقمة" editor.
void main() {
  late FakeConfigRepository config;

  Future<void> pump(WidgetTester tester, {Map<String, Object> seed = const {}}) async {
    config = FakeConfigRepository(seed: seed);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [configRepositoryProvider.overrideWithValue(config)],
        child: MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          localizationsDelegates: LuqmaStrings.localizationsDelegates,
          supportedLocales: LuqmaStrings.supportedLocales,
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: AboutEditorScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the current values', (tester) async {
    await pump(tester, seed: {'about_facebook': 'https://facebook.com/luqma'});

    expect(
      tester
          .widget<TextField>(find.byKey(AboutEditorScreen.descriptionKey))
          .controller!
          .text,
      isEmpty,
    );
    expect(find.text('https://facebook.com/luqma'), findsOneWidget);
  });

  testWidgets('saving writes the about fields through the repository', (tester) async {
    await pump(tester);

    await tester.enterText(
      find.byKey(AboutEditorScreen.descriptionKey),
      'أكل بيتي على أصوله في إدكو.',
    );
    await tester.tap(find.byKey(AboutEditorScreen.saveKey));
    await tester.pumpAndSettle();

    expect(config.setCalls, hasLength(1));
    expect(
      config.setCalls.first['about_description'],
      'أكل بيتي على أصوله في إدكو.',
    );
  });
}
