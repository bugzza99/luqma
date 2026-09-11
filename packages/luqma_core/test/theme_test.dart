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

    // The home's promotion banner puts small orange text on the brand gradient, which is
    // the only place in the product where orange sits on a dark ground. The first
    // implementation reached for `colors.accent` — the theme's orange — and that is the
    // wrong one: it is `#D67F2B` in the light theme and scores 3.70:1 here, under the
    // 4.5:1 that 12sp normal text needs. The banner's ground is brand burgundy in *both*
    // themes, so its ink cannot be the swatch that swaps with the theme.
    test('small orange text on the brand gradient uses the light orange', () {
      // Both ends of the gradient, because text crosses the whole of it.
      for (final ground in [LuqmaPalette.bannerTop, LuqmaPalette.bannerBottom]) {
        expect(Contrast.passesText(LuqmaPalette.orangeLight, ground), isTrue);
      }
      // The one that was used. It fails on the light end and passes on the dark end —
      // 3.70:1 on `bannerTop`, 5.11:1 on `bannerBottom` — which is the trap: checked
      // against the darker half it looks fine, and the text runs across both.
      expect(Contrast.passesText(LuqmaPalette.orange, LuqmaPalette.bannerTop), isFalse);
      expect(
        Contrast.passesText(LuqmaPalette.orange, LuqmaPalette.bannerBottom),
        isTrue,
      );
    });

    // The half of the rule that the first version of this test missed, and the miss was
    // the whole point: it lived in the light-theme group and read `c.brand`, so it proved
    // the banner was legible in the theme it happened to check and said nothing about the
    // other one. `LuqmaColors.dark.brand` is the *lighter* burgundy — swapped on purpose,
    // because plain burgundy is too dark on a near-black page — and `orangeLight` scores
    // only 3.83:1 on it. The banner was still failing in dark mode after the fix that was
    // supposed to have fixed it.
    //
    // Which is why the ground is a fixed pair rather than the theme's brand, and why this
    // assertion names the themes explicitly instead of taking whichever one the
    // surrounding group happens to be about.
    test('and the banner ground does not follow the theme', () {
      for (final theme in [LuqmaColors.light, LuqmaColors.dark]) {
        expect(
          Contrast.passesText(LuqmaPalette.orangeLight, theme.brand),
          theme == LuqmaColors.light,
          reason: 'the theme brand is only safe for this text in one theme, '
              'which is why the banner does not use it',
        );
      }
      // What it uses instead is safe in both, because it is the same in both.
      expect(Contrast.passesText(LuqmaPalette.orangeLight, LuqmaPalette.bannerTop),
          isTrue);
      expect(Contrast.passesText(LuqmaColors.dark.onBrand, LuqmaPalette.bannerTop),
          isTrue);
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

    // `docs/14` has said 15sp since Phase 0, and this asked it of one token while
    // `bodySmall` sat at 13 and carried a hundred call sites across the three apps —
    // merchant and dish descriptions, secondary rows, the lines under every card. The
    // published rule and the token set disagreed for nine phases because the test only
    // ever looked at the token that already complied.
    //
    // Settled on 2026-09-11: the token moves. `caption` stays at 12 and is deliberately
    // not in this list — it is a label, not body text, and the rule was never about it.
    test('no style used for body text drops below 15sp', () {
      for (final (name, style) in [
        ('body', LuqmaType.body),
        ('bodyStrong', LuqmaType.bodyStrong),
        ('bodySmall', LuqmaType.bodySmall),
      ]) {
        expect(style.fontSize, greaterThanOrEqualTo(15),
            reason: '$name is body text, and Arabic loses legibility faster than Latin');
      }
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
