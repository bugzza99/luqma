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

    // A window tall enough for the whole form.
    //
    // AdminApp is the one Luqma app that runs on more than a phone — the owner types six
    // hundred menu items on a real keyboard — so this is a size it genuinely renders at.
    // The default 800x600 test window puts the description field below the fold, and a
    // lazy ListView does not build what is below the fold: the field is then absent for
    // a reason that has nothing to do with the screen being wrong.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

  /// Taps save. Pinned below the scrolling form, so it is always reachable.
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(AboutEditorScreen.saveKey));
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
    await save(tester);

    expect(config.setCalls, hasLength(1));
    expect(
      config.setCalls.first['about_description'],
      'أكل بيتي على أصوله في إدكو.',
    );
  });
}
