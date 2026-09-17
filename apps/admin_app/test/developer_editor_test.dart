import 'package:admin_app/src/developer/developer_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The «عن المطور» editor — the person, apart from the product.
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
            child: DeveloperEditorScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps save. Pinned below the scrolling form, so it is always reachable.
  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(DeveloperEditorScreen.saveKey));
    await tester.pumpAndSettle();
  }

  testWidgets('shows what is already set, including what was carried over', (tester) async {
    await pump(tester, seed: {
      'developer_name': 'محمد',
      'developer_facebook': 'https://facebook.com/me',
    });

    expect(find.text('محمد'), findsOneWidget);
    expect(find.text('https://facebook.com/me'), findsOneWidget);
  });

  testWidgets('saving writes the developer keys, and never the product description',
      (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(DeveloperEditorScreen.nameKey), 'محمد رمضان');
    await tester.enterText(find.byKey(DeveloperEditorScreen.bioKey), 'من إدكو.');
    await save(tester);

    final written = config.setCalls.single;
    expect(written['developer_name'], 'محمد رمضان');
    expect(written['developer_bio'], 'من إدكو.');
    expect(written.keys.where((k) => k.startsWith('about_')), isEmpty);
  });
}
