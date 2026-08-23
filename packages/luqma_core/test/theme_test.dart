import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// These tests turn the rules in `docs/14-design-system.md` into something that fails
/// out loud. Every ratio here was measured before a screen existed; if a token changes
/// and a pair drops under threshold, this suite is where it shows up — not in review,
/// and not on a user's phone.
void main() {
  group('contrast — light theme', () {
    const c = LuqmaColors.light;

    test('body text on every ground it can sit on', () {
      expect(Contrast.passesText(c.textPrimary, c.background), isTrue);
      expect(Contrast.passesText(c.textPrimary, c.card), isTrue);
      expect(Contrast.passesText(c.textSecondary, c.background), isTrue);
      expect(Contrast.passesText(c.textSecondary, c.card), isTrue);
    });

    test('primary button', () {
      expect(Contrast.passesText(c.onBrand, c.brand), isTrue);
      expect(Contrast.passesText(c.onBrand, c.brandPressed), isTrue);
    });

    test('an accent badge carries dark text, never white', () {
      expect(Contrast.passesText(c.onAccent, c.accent), isTrue);
      // The mistake this palette invites. Kept as a test so nobody re-introduces it.
      expect(Contrast.passesText(const Color(0xFFFFFFFF), c.accent), isFalse);
    });

    test('price colour: accent is large-only on white and fails on cream', () {
      expect(Contrast.passesLarge(c.accent, c.card), isTrue);
      expect(Contrast.passesText(c.accent, c.background), isFalse);
      // …which is exactly why `price` exists, and it passes on both.
      expect(Contrast.passesText(c.price, c.card), isTrue);
      expect(Contrast.passesText(c.price, c.background), isTrue);
    });

    test('interactive outlines clear the 3:1 boundary rule', () {
      expect(Contrast.passesLarge(c.border, c.background), isTrue);
      expect(Contrast.passesLarge(c.border, c.card), isTrue);
      // The decorative hairline does not, which is why it is decorative only.
      expect(Contrast.passesLarge(c.hairline, c.background), isFalse);
    });

    test('status colours', () {
      expect(Contrast.passesText(c.success, c.background), isTrue);
      expect(Contrast.passesText(c.danger, c.background), isTrue);
      expect(Contrast.passesText(c.success, c.card), isTrue);
      expect(Contrast.passesText(c.danger, c.card), isTrue);
    });
  });

  group('contrast — dark theme', () {
    const c = LuqmaColors.dark;

    test('body text', () {
      expect(Contrast.passesText(c.textPrimary, c.background), isTrue);
      expect(Contrast.passesText(c.textPrimary, c.card), isTrue);
      expect(Contrast.passesText(c.textSecondary, c.card), isTrue);
    });

    test('primary button and accent', () {
      expect(Contrast.passesText(c.onBrand, c.brand), isTrue);
      expect(Contrast.passesText(c.onAccent, c.accent), isTrue);
      expect(Contrast.passesText(c.price, c.card), isTrue);
    });

    test('outlines stay visible on a dark ground', () {
      expect(Contrast.passesLarge(c.border, c.card), isTrue);
      expect(Contrast.passesLarge(c.border, c.background), isTrue);
    });

    test('status colours', () {
      expect(Contrast.passesText(c.success, c.card), isTrue);
      expect(Contrast.passesText(c.danger, c.card), isTrue);
    });
  });

  group('theme wiring', () {
    test('both themes expose the colour roles', () {
      expect(LuqmaTheme.light.luqma, LuqmaColors.light);
      expect(LuqmaTheme.dark.luqma, LuqmaColors.dark);
    });

    test('dark is measured, not inverted', () {
      // A naive inversion would reuse the brand burgundy on a dark ground, where it
      // barely separates from the surface.
      expect(LuqmaColors.dark.brand, isNot(LuqmaColors.light.brand));
      expect(
        Contrast.ratio(LuqmaPalette.burgundy, LuqmaColors.dark.card) < 3.0,
        isTrue,
        reason: 'the light brand really is too dark to sit on the dark surface',
      );
    });

    test('every text style is Cairo, and the display face is absent', () {
      final styles = [
        LuqmaType.screenTitle,
        LuqmaType.sectionTitle,
        LuqmaType.cardTitle,
        LuqmaType.button,
        LuqmaType.body,
        LuqmaType.bodySmall,
        LuqmaType.caption,
        LuqmaType.price,
        LuqmaType.display,
      ];
      for (final s in styles) {
        expect(s.fontFamily, LuqmaType.family);
        expect(s.fontVariations, isNotEmpty,
            reason: 'a variable font needs an explicit wght axis or every '
                'weight renders identically');
      }
      expect(styles.map((s) => s.fontFamily), isNot(contains('Lemonada')));
    });

    test('body text never drops below 15sp', () {
      expect(LuqmaType.body.fontSize, greaterThanOrEqualTo(15));
    });

    test('prices use tabular figures so columns line up', () {
      expect(LuqmaType.price.fontFeatures, contains(const FontFeature.tabularFigures()));
    });
  });

  group('dimens', () {
    test('touch targets meet the Android minimum', () {
      expect(Sizes.minTarget, greaterThanOrEqualTo(48));
      expect(Sizes.targetGap, greaterThanOrEqualTo(8));
    });

    test('spacing stays on the 4/8 rhythm', () {
      for (final v in [Space.xs, Space.sm, Space.md, Space.lg, Space.xl, Space.xxl]) {
        expect(v % 4, 0);
      }
    });
  });

  group('LuqmaLockup', () {
    testWidgets('renders and is announced as the brand name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LuqmaTheme.light,
          locale: const Locale('ar'),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: Center(child: LuqmaLockup())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LuqmaLockup), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(LuqmaLockup)).label,
        'لقمة',
      );
    });

    testWidgets('the app bar form is the documented 21dp', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: Center(child: LuqmaLockup.appBar())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(LuqmaLockup)).height, 21);
    });
  });

  group('LuqmaSplash', () {
    testWidgets('assembles the lockup, then reports finished', (tester) async {
      var finished = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: LuqmaTheme.light,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: LuqmaSplash(onFinished: () => finished = true),
          ),
        ),
      );

      await tester.pump();
      expect(find.byType(LuqmaLockup), findsNWidgets(2)); // mark and wordmark
      expect(finished, isFalse, reason: 'it must not finish on the first frame');

      await tester.pumpAndSettle();
      expect(finished, isTrue);
    });

    testWidgets('waits for slow start-up instead of cutting the fade short',
        (tester) async {
      final ready = Completer<void>();
      var finished = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: LuqmaSplash(ready: ready.future, onFinished: () => finished = true),
          ),
        ),
      );

      await tester.pump(Motion.splash + const Duration(milliseconds: 100));
      await tester.pump();
      expect(finished, isFalse, reason: 'the animation is done but the app is not');

      ready.complete();
      await tester.pumpAndSettle();
      expect(finished, isTrue);
    });

    testWidgets('reduced motion shows the finished lockup immediately',
        (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: LuqmaSplash(),
            ),
          ),
        ),
      );
      await tester.pump();

      final wordmark = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(wordmark.opacity, 1.0);
    });

    // splashMinMillis is one of the values the owner controls, so the splash has to
    // actually read it rather than carry its own hardcoded duration.
    testWidgets('honours a configured duration', (tester) async {
      var finished = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: LuqmaSplash(
              minimumDuration: const Duration(milliseconds: 400),
              onFinished: () => finished = true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(finished, isFalse);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(finished, isTrue);
    });
  });
}
