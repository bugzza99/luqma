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
    expect(find.text('اتحفظ'), findsOneWidget);
  });

  testWidgets('validates facebook, instagram and whatsapp with inline errors', (tester) async {
    await pump(tester);

    await tester.enterText(find.byKey(DeveloperEditorScreen.facebookKey), 'http://facebook.com/me');
    await tester.enterText(find.byKey(DeveloperEditorScreen.instagramKey), 'instagram.com/me');
    await tester.enterText(find.byKey(DeveloperEditorScreen.whatsappKey), '12345');
    await save(tester);

    expect(find.text('الرابط لازم يبدأ بـ https://'), findsNWidgets(2));
    expect(find.text('اكتب رقم موبايل مصري صحيح'), findsOneWidget);
    expect(config.setCalls, isEmpty);

    // Fix them with valid inputs
    await tester.enterText(find.byKey(DeveloperEditorScreen.facebookKey), 'https://facebook.com/me');
    await tester.enterText(find.byKey(DeveloperEditorScreen.instagramKey), 'https://instagram.com/me');
    await tester.enterText(find.byKey(DeveloperEditorScreen.whatsappKey), '01012345678');
    await save(tester);

    expect(find.text('الرابط لازم يبدأ بـ https://'), findsNothing);
    expect(find.text('اكتب رقم موبايل مصري صحيح'), findsNothing);
    expect(config.setCalls, hasLength(1));
    expect(config.setCalls.first['developer_facebook'], 'https://facebook.com/me');
    expect(config.setCalls.first['developer_instagram'], 'https://instagram.com/me');
    expect(config.setCalls.first['developer_whatsapp'], '01012345678');
    expect(find.text('اتحفظ'), findsOneWidget);
  });

  testWidgets('leaving with unsaved changes shows confirmation dialog', (tester) async {
    await pump(tester, seed: {'developer_name': 'علي'});

    await tester.enterText(find.byKey(DeveloperEditorScreen.nameKey), 'عمر');
    await tester.pump();

    final dynamic widgetsAppState = tester.state(find.byType(WidgetsApp));
    await widgetsAppState.didPopRoute();
    await tester.pumpAndSettle();

    expect(find.text('تسيب التعديلات من غير حفظ؟'), findsOneWidget);
  });

  // A typo in a link used to be found by a customer (QA review 2026-09-19).
  testWidgets('the page can be previewed as typed, before it is saved', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(DeveloperEditorScreen.nameKey), 'أحمد المطور');
    await tester.enterText(
        find.byKey(DeveloperEditorScreen.facebookKey), 'https://facebook.com/ahmed');
    await tester.tap(find.byKey(DeveloperEditorScreen.previewKey));
    await tester.pumpAndSettle();

    expect(find.byKey(DeveloperEditorScreen.previewDialogKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(DeveloperEditorScreen.previewDialogKey),
        matching: find.text('أحمد المطور'),
      ),
      findsOneWidget,
    );
    expect(find.text('جرّب رابط فيسبوك'), findsOneWidget);
    expect(find.text('جرّب رابط واتساب'), findsNothing);
  });
}
