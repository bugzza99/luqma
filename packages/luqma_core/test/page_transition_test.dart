import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luqma_core/luqma_core.dart';

/// Screen-to-screen motion.
///
/// `docs/14` §4 asks for a 300ms easeOutCubic page transition, and `Motion.page` has
/// held that number since Phase 0 with nothing reading it — every push in all three apps
/// ran on whatever Material's default for the platform happened to be. Setting it on the
/// theme is what makes the answer the same everywhere without a single screen having to
/// ask for it.
void main() {
  Widget harness() {
    return MaterialApp(
      theme: LuqmaTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('التانية')),
                ),
              ),
              child: const Text('روح'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a push animates rather than cutting straight to the next screen',
      (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('روح'));
    await tester.pump();
    // Part-way through: the incoming screen exists but the outgoing one has not left,
    // which is what says a transition is running at all.
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('التانية'), findsOneWidget);
    expect(find.text('روح'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('روح'), findsNothing);
  });

  testWidgets('and settles within the page token', (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('روح'));
    await tester.pump();
    // One frame past the token. A transition still running here is slower than the
    // number the design system publishes.
    await tester.pump(Motion.page + const Duration(milliseconds: 16));

    expect(find.text('روح'), findsNothing);
    expect(find.text('التانية'), findsOneWidget);
  });

  // Reduced motion is on for people who get motion sick and for people using a screen
  // reader. A screen that slides anyway is the one setting they asked us to respect.
  //
  // Set on the platform dispatcher rather than by wrapping a `MediaQuery`, because that
  // is where the setting actually arrives from — and because a route's duration is read
  // before any `BuildContext` exists to ask.
  testWidgets('reduced motion arrives with no transition at all', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures.allOn;
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(harness());

    await tester.tap(find.text('روح'));
    await tester.pump();
    await tester.pump();

    expect(find.text('التانية'), findsOneWidget);
    expect(find.text('روح'), findsNothing);
  });
}
