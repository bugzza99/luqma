import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool selected,
    VoidCallback? onTap,
    bool reducedMotion = false,
    bool dashed = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LuqmaTheme.light,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Scaffold(
            // A `Wrap`, deliberately, because that is what the merchant screen lays these
            // out in and it sizes a child to its intrinsic height. Inside a `Center` the
            // chip is stretched to the whole page, and the touch-target test below then
            // passes whether or not the widget carries a minimum of its own.
            body: Wrap(
              children: [
                LuqmaChip(
                  label: 'مشويات',
                  selected: selected,
                  dashed: dashed,
                  onTap: onTap ?? () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration decoration(WidgetTester tester) {
    return tester
        .widget<AnimatedContainer>(find.byType(AnimatedContainer))
        .decoration! as BoxDecoration;
  }

  group('LuqmaChip', () {
    // The chip is a pill inside whatever lays it out, and on the merchant screen that is
    // a plain wrap rather than a fixed-height row. A touch target that comes from the
    // parent is one that silently stops being 48 the first time the chip is reused.
    testWidgets('is at least a full touch target tall wherever it is put',
        (tester) async {
      await pump(tester, selected: false);

      expect(
        tester.getSize(find.byType(LuqmaChip)).height,
        greaterThanOrEqualTo(Sizes.minTarget),
      );
    });

    // Orange means price, offer and rating. The moment it also means "selected" it stops
    // meaning value on every screen at once, so selection is the brand burgundy.
    testWidgets('fills with the brand when selected, never the accent',
        (tester) async {
      await pump(tester, selected: true);
      final colors = LuqmaTheme.light.luqma;

      expect(decoration(tester).color, colors.brand);
      expect(decoration(tester).color, isNot(colors.accent));
    });

    testWidgets('is a card with a border when it is not', (tester) async {
      await pump(tester, selected: false);
      final colors = LuqmaTheme.light.luqma;

      expect(decoration(tester).color, colors.card);
    });

    testWidgets('the other-place outline is dashed only while unselected', (tester) async {
      await pump(tester, selected: false, dashed: true);
      final painters = find.descendant(
        of: find.byType(LuqmaChip), matching: find.byType(CustomPaint),
      );
      expect(tester.widgetList<CustomPaint>(painters)
        .where((p) => p.foregroundPainter != null), hasLength(1));
      await pump(tester, selected: true, dashed: true);
      expect(tester.widgetList<CustomPaint>(painters)
        .where((p) => p.foregroundPainter != null), isEmpty);
      expect(decoration(tester).color, LuqmaTheme.light.luqma.brand);
    });

    testWidgets('reports the tap', (tester) async {
      var taps = 0;
      await pump(tester, selected: false, onTap: () => taps++);

      await tester.tap(find.byType(LuqmaChip));
      expect(taps, 1);
    });

    // Announced as a selectable control, not as a word on a screen — otherwise a chip row
    // reads to a screen reader as a sentence and nothing says which one is on.
    testWidgets('tells a screen reader whether it is on', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, selected: true);

      expect(
        tester.getSemantics(find.byType(LuqmaChip)),
        matchesSemantics(
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
          // The chip is reachable by keyboard and by Switch Access, not only by a
          // finger — that is what `LuqmaPressable` buys by being an `InkWell`.
          hasFocusAction: true,
          isFocusable: true,
          label: 'مشويات',
        ),
      );
      handle.dispose();
    });

    testWidgets('animates the change, and does not under reduced motion',
        (tester) async {
      await pump(tester, selected: false);
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer))
            .duration,
        Motion.quick,
      );

      await pump(tester, selected: false, reducedMotion: true);
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer))
            .duration,
        Duration.zero,
      );
    });
  });
}
