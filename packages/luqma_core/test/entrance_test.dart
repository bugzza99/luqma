import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// List items arriving.
///
/// `docs/14` §4 asks for a 40ms stagger capped at six items, and `Motion.stagger` /
/// `Motion.staggerMax` have held those numbers since Phase 0 with nothing reading them.
/// The cap is the part that matters: past six the last row lands late enough to read as
/// the app being slow rather than as it arriving.
void main() {
  Widget harness({required int count, bool reducedMotion = false}) {
    return MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: MaterialApp(
        theme: LuqmaTheme.light,
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < count; i++)
                LuqmaEntrance(index: i, child: Text('صف $i')),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('an item starts hidden and finishes visible', (tester) async {
    await tester.pumpWidget(harness(count: 3));

    expect(opacityOf(tester, 'صف 0'), lessThan(1.0));

    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'صف 0'), 1.0);
    expect(opacityOf(tester, 'صف 2'), 1.0);
  });

  testWidgets('a later item arrives after an earlier one', (tester) async {
    await tester.pumpWidget(harness(count: 3));

    // One stagger step in: the first row is further along than the third, which is the
    // whole point of a stagger over a single fade.
    await tester.pump(Motion.stagger * 2);

    expect(opacityOf(tester, 'صف 0'), greaterThan(opacityOf(tester, 'صف 2')));
  });

  // Past the cap every remaining row shares the last delay. Without it the twentieth
  // item on a merchant's menu waits 800ms, which is not an entrance — it is a wait.
  testWidgets('the delay stops growing after the cap', (tester) async {
    await tester.pumpWidget(harness(count: 12));

    await tester.pump(Motion.stagger * Motion.staggerMax);

    // The sixth row and the twelfth are on the same schedule, so they are at the same
    // point — a stagger that kept counting would leave the twelfth still invisible.
    expect(
      opacityOf(tester, 'صف ${Motion.staggerMax}'),
      opacityOf(tester, 'صف 11'),
    );
  });

  testWidgets('reduced motion shows everything at once', (tester) async {
    await tester.pumpWidget(harness(count: 6, reducedMotion: true));
    await tester.pump();

    for (var i = 0; i < 6; i++) {
      expect(opacityOf(tester, 'صف $i'), 1.0, reason: 'row $i');
    }
  });
}

/// The opacity actually being painted for the row carrying [text].
double opacityOf(WidgetTester tester, String text) {
  final opacity = tester.widget<FadeTransition>(
    find.ancestor(of: find.text(text), matching: find.byType(FadeTransition)).first,
  );
  return opacity.opacity.value;
}
