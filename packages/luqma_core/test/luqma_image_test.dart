import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Every picture in the product, and what stands in when there isn't one.
///
/// On launch day there is no photograph of anything: the owner shoots them one merchant
/// at a time over the following weeks. So the empty case is not an edge — it is the
/// whole screen, for a while, and it has to look deliberate rather than broken.
void main() {
  /// The monogram's own box.
  ///
  /// Scoped to the widget: `find.byType(ColoredBox).first` picks up a transparent one
  /// from Material's own scaffolding, and then every colour comparison in here is
  /// transparent-versus-transparent — which passes the "same tint" test and fails the
  /// "different tint" one, both for reasons that have nothing to do with the code.
  Color tintOf(WidgetTester tester) => tester
      .widget<ColoredBox>(find.descendant(
        of: find.byType(LuqmaImage),
        matching: find.byType(ColoredBox),
      ))
      .color;

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LuqmaTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Center(child: SizedBox(width: 200, height: 120, child: child)),
        ),
      ),
    );
  }

  group('with no picture', () {
    testWidgets('shows the first letter of the name', (tester) async {
      await pump(tester, const LuqmaImage(url: null, name: 'مطعم البحر'));

      expect(find.text('م'), findsOneWidget);
    });

    // A grid of twenty identical marks reads as broken, not as empty. A tint drawn from
    // the name gives each shop its own look from the first day, and it is replaced by
    // the photograph without anybody noticing the swap.
    testWidgets('two different names do not look the same', (tester) async {
      await pump(tester, const LuqmaImage(url: null, name: 'مطعم البحر'));
      final first = tintOf(tester);

      await pump(tester, const LuqmaImage(url: null, name: 'كشري الأمير'));
      final second = tintOf(tester);

      expect(first, isNot(second));
    });

    // The same shop must not change colour between the home screen and its own page.
    testWidgets('one name always gets the same tint', (tester) async {
      await pump(tester, const LuqmaImage(url: null, name: 'مطعم البحر'));
      final first = tintOf(tester);

      await pump(tester, const LuqmaImage(url: null, name: 'مطعم البحر'));
      final second = tintOf(tester);

      expect(first, second);
    });

    testWidgets('a nameless thing still draws something', (tester) async {
      await pump(tester, const LuqmaImage(url: null, name: ''));

      expect(tester.takeException(), isNull);
      expect(find.byType(ColoredBox), findsWidgets);
    });

    // Arabic is written in joined forms; taking a UTF-16 code unit rather than a
    // grapheme splits a letter from its diacritic and draws a broken glyph.
    testWidgets('a name starting with a combined character is not split',
        (tester) async {
      await pump(tester, const LuqmaImage(url: null, name: 'أُسرة'));

      expect(tester.takeException(), isNull);
    });
  });

  // The monogram is text on a colour, so it is bound by the same rule as every other
  // pair in this product — and it is the one that would be easiest to miss, because it
  // is generated rather than chosen.
  test('every tint a name can land on is readable under it', () {
    for (final tint in LuqmaImage.tintsFor(LuqmaTheme.light.luqma)) {
      expect(
        Contrast.passesLarge(LuqmaTheme.light.luqma.background, tint),
        isTrue,
        reason: 'the letter is large, so 3:1 — $tint fails it',
      );
    }
  });

  group('accessibility', () {
    // A photo of a dish carries no information a blind customer needs beyond what the
    // name already says — so it is labelled by that name, not announced as "image".
    testWidgets('is announced by the name it belongs to', (tester) async {
      await pump(tester, const LuqmaImage(url: null, name: 'مطعم البحر'));

      expect(
        find.bySemanticsLabel('مطعم البحر'),
        findsOneWidget,
      );
    });
  });
}
