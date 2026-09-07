import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// A card taking a press.
///
/// `Motion.tap` and the press feedback it was meant to drive went unread for the whole
/// product's life — a card changed nothing under a finger. This is the one widget that
/// answers a touch, and the two things that matter are that it is visible and that it is
/// gone for anybody who asked for reduced motion.
void main() {
  Widget harness({VoidCallback? onTap, bool reducedMotion = false}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: MaterialApp(
        theme: LuqmaTheme.light,
        home: Scaffold(
          body: Center(
            child: LuqmaPressable(
              onTap: onTap ?? () {},
              child: const SizedBox(width: 120, height: 80),
            ),
          ),
        ),
      ),
    );
  }

  double scaleTarget(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('draws back under a press and springs back on release',
      (tester) async {
    await tester.pumpWidget(harness());
    expect(scaleTarget(tester), 1.0);

    final press = await tester.startGesture(
      tester.getCenter(find.byType(LuqmaPressable)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(scaleTarget(tester), lessThan(1.0));

    await press.up();
    await tester.pumpAndSettle();
    expect(scaleTarget(tester), 1.0);
  });

  testWidgets('does not move at all under reduced motion', (tester) async {
    await tester.pumpWidget(harness(reducedMotion: true));

    final press = await tester.startGesture(
      tester.getCenter(find.byType(LuqmaPressable)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(scaleTarget(tester), 1.0, reason: 'the press is felt, not seen');

    await press.up();
    await tester.pumpAndSettle();
  });

  // The tap that most needs answering is the fast one, and it was the one that went
  // unanswered: a press and release inside a single frame moved the scale target to 0.97
  // and back before anything painted, so the card never visibly moved. The release now
  // waits for the press to have been seen.
  //
  // Nothing covered this. Every other test here holds the gesture for 150ms, so removing
  // the hold entirely would have left the whole file green — the fix would have been
  // deleted by the next person with no test to stop them.
  testWidgets('a tap too fast to see still shows the press', (tester) async {
    await tester.pumpWidget(harness());

    final press = await tester.startGesture(
      tester.getCenter(find.byType(LuqmaPressable)),
    );
    // Up on the very next frame — faster than any human, and the shape of the bug.
    await tester.pump();
    await press.up();
    await tester.pump();

    expect(scaleTarget(tester), lessThan(1.0),
        reason: 'the press was held long enough to be seen');

    await tester.pumpAndSettle();
    expect(scaleTarget(tester), 1.0, reason: 'and then let go');
  });

  testWidgets('still reports the tap under reduced motion', (tester) async {
    var taps = 0;
    // This said "still reports the tap" and then never turned reduced motion on, so it
    // tested the ordinary path twice and the one it was named for not at all.
    await tester.pumpWidget(
      harness(onTap: () => taps++, reducedMotion: true),
    );

    await tester.tap(find.byType(LuqmaPressable));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('reports the tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(harness(onTap: () => taps++));

    await tester.tap(find.byType(LuqmaPressable));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });

  testWidgets('the tap is not held for the animation', (tester) async {
    var taps = 0;
    await tester.pumpWidget(harness(onTap: () => taps++));

    // No settle: the callback has to have run on tap-up, not after the scale eases back.
    await tester.tap(find.byType(LuqmaPressable));
    await tester.pump();

    expect(taps, 1);
  });
}
