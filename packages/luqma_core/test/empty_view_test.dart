import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// The one empty state, shared by all three apps.
///
/// It replaced twelve private `_Empty` widgets that had drifted exactly the way the
/// seventeen `_Error` copies before them did: seven drew an icon and five did not, one
/// used a different padding from the other eleven, and the text alignment varied. So
/// "no orders yet" did not look like "no photos yet", and nothing could change how an
/// empty screen reads without editing twelve files.
///
/// None of the twelve could offer the person a way forward either. An empty basket that
/// cannot say "browse the shops" is a dead end on the screen most likely to be somebody's
/// first, which is why [LuqmaEmptyView] takes an action from the start.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LuqmaTheme.light,
        locale: const Locale('ar'),
        localizationsDelegates: LuqmaStrings.localizationsDelegates,
        supportedLocales: LuqmaStrings.supportedLocales,
        home: Scaffold(
          body: Directionality(textDirection: TextDirection.rtl, child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a title alone is a complete empty state', (tester) async {
    await pump(tester, const LuqmaEmptyView(title: 'مفيش طلبات تحت التحضير'));

    expect(find.text('مفيش طلبات تحت التحضير'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('a message alone is one too', (tester) async {
    await pump(tester, const LuqmaEmptyView(message: 'مفيش صور مستنية مراجعة.'));

    expect(find.text('مفيش صور مستنية مراجعة.'), findsOneWidget);
  });

  testWidgets('a title and a message read as heading then explanation',
      (tester) async {
    await pump(tester, const LuqmaEmptyView(
      title: 'لسه مفيش عناوين محفوظة.',
      message: 'ضيف عنوانك مرة واحدة وهيفضل موجود.',
    ));

    expect(find.text('لسه مفيش عناوين محفوظة.'), findsOneWidget);
    expect(find.text('ضيف عنوانك مرة واحدة وهيفضل موجود.'), findsOneWidget);
  });

  testWidgets('an icon is drawn when one is given, and not when it is not',
      (tester) async {
    await pump(tester, const LuqmaEmptyView(
      icon: Icons.location_off_outlined,
      title: 'لسه مفيش عناوين',
    ));
    expect(find.byIcon(Icons.location_off_outlined), findsOneWidget);

    await pump(tester, const LuqmaEmptyView(title: 'لسه مفيش عناوين'));
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('an action is offered when there is one, and pressed', (tester) async {
    var pressed = false;
    await pump(tester, LuqmaEmptyView(
      title: 'السلة فاضية',
      action: FilledButton(
        onPressed: () => pressed = true,
        child: const Text('اتفرّج على المطاعم'),
      ),
    ));

    await tester.tap(find.text('اتفرّج على المطاعم'));
    expect(pressed, isTrue,
        reason: 'the whole point of consolidating these was to make this possible');
  });

  testWidgets('with no action nothing is drawn where a button would be',
      (tester) async {
    await pump(tester, const LuqmaEmptyView(title: 'السلة فاضية'));

    // A dead control is worse than none — the same rule `LuqmaErrorView` follows.
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('the key it is given is the key a screen can find it by',
      (tester) async {
    const key = Key('some.screen.empty');
    await pump(tester, const LuqmaEmptyView(key: key, title: 'فاضي'));

    // Twelve screens identify their empty state by their own key, and their tests find
    // it that way. Consolidating must not take that away.
    expect(find.byKey(key), findsOneWidget);
  });
}
